-- ============================================================
-- PHASE 68 - La région rejoint la carte de membre.
--
-- POURQUOI. Les cartes sont créées avant les comptes : elles sont
-- importées d'un tableur, puis le membre les récupère par invitation, et
-- la carte transmet alors ce qu'elle porte à son profil (ancienneté,
-- numéro, localité, téléphone). Depuis phase66 le profil a une région,
-- mais la carte n'en avait pas : un membre invité arrivait donc avec sa
-- localité et sans sa région, alors que le tableur d'origine la
-- connaissait.
--
-- Même liste fermée que profiles.region : les deux colonnes se recopient
-- l'une dans l'autre, elles ne peuvent pas admettre des valeurs
-- différentes.
--
-- À exécuter après phase66. Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. La colonne =====
alter table public.member_cards add column if not exists region text;

alter table public.member_cards drop constraint if exists member_cards_region_check;
alter table public.member_cards add constraint member_cards_region_check
  check (region is null or region in (
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
    'Thiès', 'Ziguinchor'
  ));

-- ===== 2. L'invitation transmet la région au profil =====
-- Copie EXACTE de la version de phase62, à la seule ligne « region »
-- près. Le verrou « for update » et les trois messages d'erreur distincts
-- sont repris tels quels : les réécrire de mémoire aurait fait perdre le
-- verrou qui empêche deux envois simultanés de rattacher la même carte à
-- deux comptes.
--
-- Même règle que pour la localité : la carte ne comble qu'un champ vide,
-- elle n'écrase jamais ce que le membre a lui-même saisi.
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
  -- numéro, ville, téléphone, et désormais la région.
  update public.profiles
     set status             = 'approved',
         legacy_card_number = coalesce(v_carte.card_number, legacy_card_number),
         member_since       = coalesce(v_carte.member_since, member_since),
         city               = coalesce(nullif(btrim(coalesce(city, '')), ''), v_carte.city),
         region             = coalesce(region, v_carte.region),
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

-- Contrôle : la colonne existe et la contrainte porte les 14 régions.
select column_name from information_schema.columns
 where table_name = 'member_cards' and column_name = 'region';
