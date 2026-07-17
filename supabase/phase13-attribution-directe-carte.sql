-- ============================================================
-- PHASE 13 — Attribution directe d'une carte par l'admin, sans attendre
-- que le membre la réclame lui-même.
--
-- Reprend exactement la logique de confirm_member_card_claim (phase9),
-- mais accepte directement l'id du membre destinataire au lieu d'exiger
-- qu'une ligne member_cards soit déjà passée par claim_member_card
-- (claimed_by déjà posé, claim_status='pending').
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase5, phase9).
-- ============================================================

create or replace function public.assign_member_card(card_id uuid, member_id uuid, expiry_year int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card_number  text;
  v_member_since int;
  v_title        text;
  v_domain       text;
  v_domain_autre text;
  v_specialty    text;
  v_claim_status text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if expiry_year is null then
    raise exception 'Année de fin de validité obligatoire.';
  end if;

  select card_number, member_since, title, domain, domain_autre, specialty, claim_status
    into v_card_number, v_member_since, v_title, v_domain, v_domain_autre, v_specialty, v_claim_status
  from public.member_cards
  where id = card_id
  for update;

  if v_claim_status is null then
    raise exception 'Carte introuvable.';
  end if;

  if v_claim_status = 'confirmed' then
    raise exception 'Cette carte a déjà été attribuée à un membre.';
  end if;

  update public.member_cards
     set claimed_by = member_id, claim_status = 'confirmed', claimed_at = now(), confirmed_at = now()
   where id = card_id;

  update public.profiles
     set legacy_card_number = coalesce(v_card_number, legacy_card_number),
         member_since = coalesce(v_member_since, member_since),
         card_valid_until = expiry_year,
         title = coalesce(v_title, title),
         domain = coalesce(v_domain, domain),
         domain_autre = coalesce(v_domain_autre, domain_autre),
         specialty = coalesce(v_specialty, specialty)
   where id = member_id;
end;
$$;
