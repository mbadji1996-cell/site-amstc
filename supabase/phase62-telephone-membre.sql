-- ============================================================
-- PHASE 62 - Le téléphone ne manque plus jamais
--
-- Le téléphone est déjà obligatoire sur les trois formulaires destinés
-- aux membres (inscription, écran de complétion, fiche profil). Restent
-- deux trous, tous deux constatés en production :
--
--   1. Les comptes antérieurs à ces règles - typiquement une inscription
--      Google jamais complétée - n'ont pas de numéro. Aucun écran ne
--      permettait à l'administration d'en saisir un, alors qu'elle
--      connaît ces personnes. Impossible donc de les prévenir par
--      WhatsApp... pour leur demander de compléter leur profil.
--
--   2. Un membre invité depuis sa carte arrivait sans numéro, alors que
--      la carte en porte un - c'est même par lui que l'invitation a été
--      envoyée. Il est désormais recopié à l'activation du compte.
--
-- PRÉREQUIS : phase51 (journal) et phase59 (invitations).
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. L'administration peut saisir un numéro manquant =====
create or replace function public.set_member_phone(target_user_id uuid, new_phone text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_avant text;
  v_nom text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  v_phone := nullif(btrim(coalesce(new_phone, '')), '');

  -- Contrôle volontairement souple : les numéros sont saisis avec des
  -- espaces, des points ou l'indicatif, et le lien WhatsApp les normalise
  -- déjà. On refuse seulement ce qui ne peut pas être un numéro.
  if v_phone is not null then
    if length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 9 then
      raise exception 'Numéro trop court : au moins 9 chiffres attendus.';
    end if;
  end if;

  select phone, full_name into v_avant, v_nom
    from public.profiles where id = target_user_id;

  update public.profiles set phone = v_phone where id = target_user_id;

  perform public.journaliser('telephone_modifie', target_user_id,
    coalesce(v_nom, '(sans nom)'),
    jsonb_build_object('avant', coalesce(v_avant, '(aucun)'),
                       'apres', coalesce(v_phone, '(aucun)')));

  return v_phone;
end;
$$;

revoke all on function public.set_member_phone(uuid, text) from public, anon;
grant execute on function public.set_member_phone(uuid, text) to authenticated;

-- ===== 2. L'invitation recopie le téléphone de la carte =====
create or replace function public.utiliser_invitation(p_jeton text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.invitations_carte%rowtype;
  v_carte public.member_cards%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;

  -- Verrou : deux envois simultanés du formulaire ne doivent pas
  -- rattacher la même carte à deux comptes.
  select * into v_inv from public.invitations_carte where jeton = p_jeton for update;

  if v_inv.id is null then
    raise exception 'Ce lien d''invitation est inconnu.';
  end if;
  if v_inv.used_at is not null then
    raise exception 'Ce lien a déjà été utilisé.';
  end if;
  if now() > v_inv.expire_le then
    raise exception 'Ce lien a expiré.';
  end if;

  select * into v_carte from public.member_cards where id = v_inv.card_id;

  -- Le compte est approuvé d'emblée et hérite de la carte : ancienneté,
  -- numéro, ville, et désormais le téléphone - c'est par lui que
  -- l'invitation a été envoyée, il n'y a aucune raison de le redemander.
  update public.profiles
     set status             = 'approved',
         legacy_card_number = coalesce(v_carte.card_number, legacy_card_number),
         member_since       = coalesce(v_carte.member_since, member_since),
         city               = coalesce(nullif(btrim(coalesce(city, '')), ''), v_carte.city),
         phone              = coalesce(nullif(btrim(coalesce(phone, '')), ''), v_carte.phone),
         applicant_type     = coalesce(applicant_type, 'membre_existant')
   where id = auth.uid();

  update public.member_cards
     set claim_status = 'confirmed', claimed_by = auth.uid(),
         claimed_at = now(), confirmed_at = now()
   where id = v_inv.card_id;

  update public.invitations_carte
     set used_at = now(), used_by = auth.uid()
   where id = v_inv.id;

  perform public.journaliser('invitation_utilisee', auth.uid(),
    coalesce(v_carte.full_name, '(sans nom)'),
    jsonb_build_object('carte', v_carte.card_number));
end;
$$;

revoke all on function public.utiliser_invitation(text) from public, anon;
grant execute on function public.utiliser_invitation(text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : combien de membres approuvés restent sans numéro ?
select count(*) as sans_telephone
  from public.profiles
 where status = 'approved' and is_active is not false
   and coalesce(btrim(phone), '') = '';
