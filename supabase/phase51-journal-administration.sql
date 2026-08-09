-- ============================================================
-- PHASE 51 - Journal des actions d'administration
--
-- Trace qui approuve, refuse, désactive, promeut, renumérote ou supprime,
-- et quand. Utile le jour où il y a un désaccord sur « qui a fait quoi ».
--
-- PARTI PRIS : des DÉCLENCHEURS sur les tables, et non une modification de
-- chaque fonction RPC. Deux raisons :
--   - la trace est prise quel que soit le chemin d'écriture, y compris
--     depuis le Studio ou une future fonction qu'on oublierait d'équiper ;
--   - les fonctions existantes (approve_or_reject_user, set_user_role,
--     set_member_years, update_member_card, delete_member…) ne sont pas
--     touchées, donc aucun risque de régression sur l'existant.
--
-- auth.uid() reste celui de l'administrateur connecté à l'intérieur d'une
-- fonction SECURITY DEFINER : c'est une donnée du jeton, pas du rôle
-- Postgres. Le journal identifie donc bien la personne, pas le service.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create table if not exists public.audit_log (
  id         bigserial primary key,
  cree_le    timestamptz not null default now(),
  acteur_id  uuid,
  acteur_nom text,
  action     text not null,
  cible_id   uuid,
  cible_nom  text,
  details    jsonb
);

create index if not exists audit_log_date_idx on public.audit_log (cree_le desc);
create index if not exists audit_log_cible_idx on public.audit_log (cible_id, cree_le desc);

alter table public.audit_log enable row level security;
-- Aucune policy : la table n'est jamais lue ni écrite directement depuis le
-- site. L'écriture passe par les déclencheurs, la lecture par
-- public.lire_journal() plus bas. Un journal modifiable par ceux qu'il
-- surveille n'aurait aucune valeur.

-- ===== Écriture =====
create or replace function public.journaliser(
  p_action text, p_cible_id uuid, p_cible_nom text, p_details jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text;
begin
  select full_name into v_nom from public.profiles where id = auth.uid();

  insert into public.audit_log (acteur_id, acteur_nom, action, cible_id, cible_nom, details)
  values (auth.uid(), coalesce(v_nom, '(système)'), p_action, p_cible_id, p_cible_nom, p_details);
exception when others then
  -- Le journal ne doit JAMAIS empêcher l'action qu'il observe : mieux vaut
  -- une ligne manquante qu'une validation de compte impossible.
  raise warning 'journaliser(%) a échoué : %', p_action, sqlerrm;
end;
$$;

-- ===== Déclencheur sur les comptes =====
create or replace function public.trg_journal_profil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cible text := coalesce(new.full_name, new.email, '(sans nom)');
begin
  if new.status is distinct from old.status then
    perform public.journaliser(
      case new.status when 'approved' then 'compte_approuve'
                      when 'rejected' then 'compte_refuse'
                      else 'compte_statut' end,
      new.id, v_cible,
      jsonb_build_object('avant', old.status, 'apres', new.status));
  end if;

  if new.role is distinct from old.role then
    perform public.journaliser('role_modifie', new.id, v_cible,
      jsonb_build_object('avant', old.role, 'apres', new.role));
  end if;

  if new.is_active is distinct from old.is_active then
    perform public.journaliser(
      case when new.is_active is false then 'compte_desactive' else 'compte_reactive' end,
      new.id, v_cible, null);
  end if;

  if new.legacy_card_number is distinct from old.legacy_card_number then
    perform public.journaliser('carte_modifiee', new.id, v_cible,
      jsonb_build_object('avant', old.legacy_card_number, 'apres', new.legacy_card_number));
  end if;

  if new.member_since is distinct from old.member_since
     or new.card_valid_until is distinct from old.card_valid_until then
    perform public.journaliser('annees_modifiees', new.id, v_cible,
      jsonb_build_object(
        'adhesion_avant', old.member_since, 'adhesion_apres', new.member_since,
        'validite_avant', old.card_valid_until, 'validite_apres', new.card_valid_until));
  end if;

  return new;
end;
$$;

drop trigger if exists journal_profil on public.profiles;
create trigger journal_profil
  after update on public.profiles
  for each row
  execute function public.trg_journal_profil();

-- ===== Suppression définitive =====
-- La ligne du membre disparaît : sans cette trace, une suppression ne
-- laisserait aucune empreinte, précisément le cas où elle compte le plus.
create or replace function public.trg_journal_profil_suppr()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.journaliser('compte_supprime', old.id,
    coalesce(old.full_name, old.email, '(sans nom)'),
    jsonb_build_object('email', old.email, 'carte', old.legacy_card_number));
  return old;
end;
$$;

drop trigger if exists journal_profil_suppr on public.profiles;
create trigger journal_profil_suppr
  before delete on public.profiles
  for each row
  execute function public.trg_journal_profil_suppr();

-- ===== Paiements =====
create or replace function public.trg_journal_paiement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text;
begin
  if new.status is distinct from old.status then
    select full_name into v_nom from public.profiles where id = new.user_id;
    perform public.journaliser('paiement_' || new.status, new.user_id,
      coalesce(v_nom, '(membre inconnu)'),
      jsonb_build_object('type', tg_argv[0], 'montant', new.amount_fcfa,
                         'avant', old.status, 'apres', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists journal_paiement_validite on public.card_validity_payments;
create trigger journal_paiement_validite
  after update on public.card_validity_payments
  for each row
  execute function public.trg_journal_paiement('validite');

drop trigger if exists journal_paiement_cotisation on public.cotisation_payments;
create trigger journal_paiement_cotisation
  after update on public.cotisation_payments
  for each row
  execute function public.trg_journal_paiement('cotisation');

-- ===== Lecture (Super Administrateur uniquement) =====
create or replace function public.lire_journal(
  p_limite int default 200, p_recherche text default null
)
returns setof public.audit_log
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Réservé au Super Administrateur : le journal sert notamment à
  -- surveiller les administrateurs, il ne doit pas leur être ouvert.
  if not public.is_super_admin() then
    raise exception 'Accès refusé.';
  end if;

  return query
    select *
      from public.audit_log
     where p_recherche is null
        or btrim(p_recherche) = ''
        or acteur_nom ilike '%' || p_recherche || '%'
        or cible_nom  ilike '%' || p_recherche || '%'
        or action     ilike '%' || p_recherche || '%'
     order by cree_le desc
     limit greatest(1, least(coalesce(p_limite, 200), 1000));
end;
$$;

revoke all on function public.lire_journal(int, text) from public;
revoke all on function public.lire_journal(int, text) from anon;
grant execute on function public.lire_journal(int, text) to authenticated;
