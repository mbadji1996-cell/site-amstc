-- ============================================================
-- PHASE 41 — Corriger une carte existante (coquilles de saisie).
--
-- Une carte peut contenir une faute : nom mal orthographié, téléphone
-- erroné, numéro de carte incorrect. Cette fonction permet de la corriger
-- depuis membres/cartes-admin.html.
--
-- Pourquoi une fonction plutôt qu'un update direct : si la carte est déjà
-- attribuée à un membre, corriger son numéro doit aussi corriger celui
-- affiché sur le profil du membre (profiles.legacy_card_number), sans quoi
-- les deux divergent - exactement le désaccord réparé en phase40. Or
-- l'écriture directe sur profiles échoue ("permission denied for table
-- profiles", cf. phase39) : seule une fonction SECURITY DEFINER y parvient.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create or replace function public.update_member_card(
  card_id uuid,
  new_full_name text,
  new_phone text,
  new_card_number text,
  new_member_since int,
  new_city text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed_by   uuid;
  v_claim_status text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if btrim(coalesce(new_full_name, '')) = '' then
    raise exception 'Le nom est obligatoire.';
  end if;

  if btrim(coalesce(new_phone, '')) = '' then
    raise exception 'Le téléphone est obligatoire.';
  end if;

  -- Deux cartes ne doivent pas porter le même numéro.
  if btrim(coalesce(new_card_number, '')) <> '' and exists (
    select 1 from public.member_cards
    where card_number = btrim(new_card_number) and id <> card_id
  ) then
    raise exception 'Ce numéro de carte est déjà utilisé par une autre carte.';
  end if;

  select claimed_by, claim_status
    into v_claimed_by, v_claim_status
  from public.member_cards
  where id = card_id
  for update;

  if v_claim_status is null then
    raise exception 'Carte introuvable.';
  end if;

  update public.member_cards
     set full_name    = btrim(new_full_name),
         phone        = btrim(new_phone),
         card_number  = nullif(btrim(coalesce(new_card_number, '')), ''),
         member_since = new_member_since,
         city         = nullif(btrim(coalesce(new_city, '')), '')
   where id = card_id;

  -- Carte déjà attribuée : le membre doit afficher le numéro corrigé.
  if v_claim_status = 'confirmed' and v_claimed_by is not null then
    update public.profiles
       set legacy_card_number = nullif(btrim(coalesce(new_card_number, '')), '')
     where id = v_claimed_by;
  end if;
end;
$$;
