-- ============================================================
-- PHASE 99 - Confirmer un don depuis Telegram
--
-- LE MANQUE. La notification « Don déclaré » arrivait dans le groupe
-- d'administration SANS AUCUN BOUTON, alors que les inscriptions et les
-- paiements en ont depuis la phase 84. Il fallait ouvrir le site pour
-- confirmer, et une déclaration qui attend ne figure pas dans la jauge :
-- le montant public est alors faux PAR LE BAS, et le donateur qui vient
-- vérifier ne voit pas son don.
--
-- CE QUE CETTE PHASE APPORTE.
--   1. Le déclencheur transmet désormais l'IDENTIFIANT du don. Sans lui,
--      la fonction Edge ne pose aucun bouton - un bouton qui ne sait pas
--      sur quoi agir vaut moins que pas de bouton du tout, et c'est la
--      règle déjà suivie par les autres notifications.
--   2. action_telegram() apprend « don:ok » et « don:no », qui appellent
--      valider_don() - la même fonction que l'écran d'administration.
--      Un seul chemin de validation, donc un seul comportement.
--
-- LE RESTE DE action_telegram EST REPRIS MOT POUR MOT de la phase 87 :
-- elle porte sept branches, et la recopier à la main aurait été le bon
-- moyen d'en perdre une.
--
-- IL FAUT AUSSI REDEPLOYER DEUX FONCTIONS EDGE :
--   notify-admin      - pour qu'elle pose les boutons
--   telegram-webhook  - pour que « Voir la fiche » mène au bon écran
--
-- PRÉREQUIS : phases 84, 87, 98.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. LE DÉCLENCHEUR TRANSMET L'IDENTIFIANT
-- ============================================================
create or replace function public.notify_admin_on_don()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source = 'public' then
    perform public.notify_admin('don_declare', jsonb_build_object(
      -- SANS CET IDENTIFIANT, PAS DE BOUTONS. La fonction Edge ne propose
      -- une action que si elle sait sur quelle ligne agir.
      'id', new.id,
      'donateur_nom', coalesce(nullif(btrim(coalesce(new.donateur_nom, '')), ''), 'Anonyme'),
      'montant', new.montant_fcfa,
      'methode', coalesce(new.methode, '-'),
      'reference', coalesce(new.reference, '-'),
      'contact', coalesce(new.donateur_contact, '-'),
      'message', coalesce(new.message, '')
    ));
  end if;
  return new;
end;
$$;

drop trigger if exists on_don_created_notify_admin on public.dons;
create trigger on_don_created_notify_admin
  after insert on public.dons
  for each row execute function public.notify_admin_on_don();

-- ============================================================
-- 2. LES DEUX NOUVELLES ACTIONS
-- ============================================================
create or replace function public.action_telegram(
  p_action text,
  p_id uuid,
  p_qui text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin    uuid;
  v_nom      text;
  v_resultat text;
  v_qui      text := nullif(btrim(coalesce(p_qui, '')), '');
  v_montant  int;
begin
  select id into v_admin
    from public.profiles
   where role in ('admin', 'super_admin')
     and coalesce(is_active, true) is true
   order by case when role = 'super_admin' then 0 else 1 end, created_at
   limit 1;

  if v_admin is null then
    return 'Aucun administrateur actif : action impossible.';
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_admin::text)::text, true);

  case p_action
    when 'ins:ok' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'approved');
      v_resultat := 'Inscription approuvée : ' || coalesce(v_nom, '');

    when 'ins:no' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'rejected');
      v_resultat := 'Inscription refusée : ' || coalesce(v_nom, '');

    -- NOUVEAU : prévenir le membre que son compte est actif. N'agit que
    -- sur un compte APPROUVÉ - prévenir quelqu'un dont l'inscription est
    -- encore en attente lui promettrait un accès qu'il n'a pas.
    when 'ins:msg' then
      select full_name into v_nom from public.profiles
       where id = p_id and status = 'approved';
      if v_nom is null then
        return 'Ce compte n''est pas (ou plus) approuvé : approuvez-le d''abord.';
      end if;
      v_resultat := public.prevenir_membre_auto(p_id, 'compte_active');

    when 'val:ok' then
      if not exists (select 1 from public.card_validity_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      select p.full_name into v_nom
        from public.card_validity_payments v join public.profiles p on p.id = v.user_id
       where v.id = p_id;
      perform public.confirm_card_validity_payment(p_id);
      v_resultat := 'Paiement de validité confirmé.';

    when 'val:no' then
      select p.full_name into v_nom
        from public.card_validity_payments v join public.profiles p on p.id = v.user_id
       where v.id = p_id;
      update public.card_validity_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      v_resultat := 'Paiement de validité refusé.';

    when 'cot:ok' then
      if not exists (select 1 from public.cotisation_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      select p.full_name into v_nom
        from public.cotisation_payments c join public.profiles p on p.id = c.user_id
       where c.id = p_id;
      perform public.confirm_cotisation_payment(p_id);
      v_resultat := 'Paiement de cotisation confirmé.';

    when 'cot:no' then
      select p.full_name into v_nom
        from public.cotisation_payments c join public.profiles p on p.id = c.user_id
       where c.id = p_id;
      update public.cotisation_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      v_resultat := 'Paiement de cotisation refusé.';

    -- NOUVEAU (phase 99) : confirmer ou rejeter un don déclaré depuis le
    -- site public. Le meme geste que l'ecran d'administration, mais sans
    -- quitter Telegram.
    --
    -- POURQUOI CELA COMPTE. Une déclaration qui dort dans la file ne
    -- figure pas dans la jauge : le montant affiché est alors FAUX PAR LE
    -- BAS, et le donateur qui vient vérifier ne voit pas son don. Plus la
    -- confirmation est à portée de pouce, moins cet écart dure.
    when 'don:ok' then
      select coalesce(nullif(btrim(coalesce(d.donateur_nom, '')), ''), '(anonyme)'),
             d.montant_fcfa
        into v_nom, v_montant
        from public.dons d where d.id = p_id and d.status = 'en_attente';
      if v_nom is null then return 'Ce don a déjà été traité, ou n''existe plus.'; end if;
      perform public.valider_don(p_id, 'confirme');
      v_resultat := 'Don confirmé : ' || v_montant::text || ' FCFA.';

    when 'don:no' then
      select coalesce(nullif(btrim(coalesce(d.donateur_nom, '')), ''), '(anonyme)'),
             d.montant_fcfa
        into v_nom, v_montant
        from public.dons d where d.id = p_id and d.status = 'en_attente';
      if v_nom is null then return 'Ce don a déjà été traité, ou n''existe plus.'; end if;
      perform public.valider_don(p_id, 'rejete');
      v_resultat := 'Don rejeté : ' || v_montant::text || ' FCFA.';

    else
      return 'Action inconnue : ' || coalesce(p_action, '(vide)');
  end case;

  begin
    perform public.journaliser('action_telegram', p_id, coalesce(v_nom, '(sans nom)'),
      jsonb_build_object(
        'qui', coalesce(v_qui, '(inconnu)'),
        'action', p_action,
        'resultat', v_resultat,
        'canal', 'telegram'));
  exception when others then
    raise warning 'action_telegram : journalisation échouée : %', sqlerrm;
  end;

  return v_resultat;

exception when others then
  return 'Échec : ' || sqlerrm;
end;
$$;

revoke all on function public.action_telegram(text, uuid, text) from public, anon, authenticated;
grant execute on function public.action_telegram(text, uuid, text) to service_role;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES
-- ============================================================
-- a) Les deux nouvelles actions sont-elles bien dans la fonction ?
select position('don:ok' in pg_get_functiondef(oid)) > 0 as sait_confirmer,
       position('don:no' in pg_get_functiondef(oid)) > 0 as sait_rejeter
  from pg_proc where proname = 'action_telegram';

-- b) Le déclencheur transmet-il l'identifiant ? Sans lui, pas de boutons.
select position('''id'', new.id' in pg_get_functiondef(oid)) > 0 as transmet_l_identifiant
  from pg_proc where proname = 'notify_admin_on_don';

-- c) Les sept branches d'origine sont-elles toujours là ?
select position('ins:ok' in d) > 0 as ins_ok, position('ins:no' in d) > 0 as ins_no,
       position('ins:msg' in d) > 0 as ins_msg, position('val:ok' in d) > 0 as val_ok,
       position('val:no' in d) > 0 as val_no, position('cot:ok' in d) > 0 as cot_ok,
       position('cot:no' in d) > 0 as cot_no
  from (select pg_get_functiondef(oid) as d from pg_proc where proname = 'action_telegram') x;

-- d) Un don en attente sur lequel essayer, s'il y en a un.
select id, coalesce(donateur_nom, '(anonyme)') as donateur, montant_fcfa, methode, created_at
  from public.dons where status = 'en_attente' order by created_at limit 5;
