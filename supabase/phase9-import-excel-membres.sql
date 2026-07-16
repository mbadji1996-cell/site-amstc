-- ============================================================
-- PHASE 9 — Enrichit member_cards pour l'import Excel (domaine, spécialité,
-- titre, année de validité attendue) et reporte ces champs sur le profil au
-- moment de la confirmation d'une réclamation.
-- À exécuter après phase7-validite-cotisations.sql.
-- ============================================================

alter table public.member_cards add column if not exists domain text;
alter table public.member_cards drop constraint if exists member_cards_domain_check;
alter table public.member_cards add constraint member_cards_domain_check
  check (domain is null or domain in ('medecine', 'pharmacie', 'odontologie', 'soins_infirmiers', 'soins_obstetricaux', 'autre'));

alter table public.member_cards add column if not exists domain_autre text;
alter table public.member_cards add column if not exists specialty text;

alter table public.member_cards add column if not exists title text;
alter table public.member_cards drop constraint if exists member_cards_title_check;
alter table public.member_cards add constraint member_cards_title_check
  check (title is null or title in ('Dr', 'Pr'));

-- Année de fin de validité attendue (issue de l'import), simple suggestion :
-- l'admin doit toujours la confirmer/l'ajuster explicitement dans
-- cartes-admin.html, ce champ ne fait que pré-remplir le champ de saisie.
alter table public.member_cards add column if not exists expiry_hint int;

-- La vue publique (cartes non réclamées) inclut désormais le domaine, pour
-- aider à distinguer des homonymes lors de la recherche.
drop view if exists public.member_cards_unclaimed;
create or replace view public.member_cards_unclaimed as
  select id, full_name, member_since, city, domain, domain_autre
  from public.member_cards
  where claim_status = 'unclaimed' and public.is_approved_member();

grant select on public.member_cards_unclaimed to authenticated;

-- confirm_member_card_claim reporte maintenant aussi titre/domaine/spécialité
-- sur le profil, en plus du numéro de carte et de l'année d'adhésion déjà
-- gérés depuis la Phase 7.
create or replace function public.confirm_member_card_claim(card_id uuid, expiry_year int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed_by    uuid;
  v_card_number   text;
  v_member_since  int;
  v_title         text;
  v_domain        text;
  v_domain_autre  text;
  v_specialty     text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if expiry_year is null then
    raise exception 'Année de fin de validité obligatoire.';
  end if;

  select claimed_by, card_number, member_since, title, domain, domain_autre, specialty
    into v_claimed_by, v_card_number, v_member_since, v_title, v_domain, v_domain_autre, v_specialty
  from public.member_cards
  where id = card_id and claim_status = 'pending';

  if v_claimed_by is null then
    raise exception 'Aucune réclamation en attente pour cette carte.';
  end if;

  update public.member_cards
     set claim_status = 'confirmed', confirmed_at = now()
   where id = card_id;

  update public.profiles
     set legacy_card_number = coalesce(v_card_number, legacy_card_number),
         member_since = coalesce(v_member_since, member_since),
         card_valid_until = expiry_year,
         title = coalesce(v_title, title),
         domain = coalesce(v_domain, domain),
         domain_autre = coalesce(v_domain_autre, domain_autre),
         specialty = coalesce(v_specialty, specialty)
   where id = v_claimed_by;
end;
$$;
