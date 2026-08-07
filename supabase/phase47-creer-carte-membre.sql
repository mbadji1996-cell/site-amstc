-- ============================================================
-- PHASE 47 - Créer une carte de membre pour un inscrit, en un clic.
--
-- « Attribuer une carte » (validation.html) ne fait que rattacher une
-- carte EXISTANTE (importée ou saisie dans cartes-admin.html). Pour un
-- nouvel inscrit qui n'a jamais eu de carte, l'admin devait d'abord la
-- créer à la main dans cartes-admin.html puis revenir l'attribuer.
--
-- Cette fonction fait tout : numérotation automatique (même règle que
-- phase40/43 : AMSTC-<année>-<n° sur 3 chiffres>, l'année étant celle
-- d'adhésion du membre, sinon l'année en cours), création de la carte
-- avec les informations du profil, rattachement confirmé, et report du
-- numéro sur profiles.legacy_card_number.
--
-- Renvoie le numéro créé. Refuse si le membre a déjà une carte.
--
-- À exécuter une seule fois, APRÈS phase43 (dont elle réutilise
-- next_card_number) : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create or replace function public.creer_carte_membre(member_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profil record;
  v_annee  int;
  v_numero text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select id, full_name, first_name, last_name, phone, city, member_since,
         title, domain, domain_autre, specialty, status, legacy_card_number
    into v_profil
  from public.profiles
  where id = member_id
  for update;

  if not found then
    raise exception 'Membre introuvable.';
  end if;
  if v_profil.status <> 'approved' then
    raise exception 'Ce membre n''est pas encore approuvé.';
  end if;
  if v_profil.legacy_card_number is not null and btrim(v_profil.legacy_card_number) <> '' then
    raise exception 'Ce membre a déjà la carte %.', v_profil.legacy_card_number;
  end if;
  if exists (
    select 1 from public.member_cards
    where claimed_by = member_id and claim_status in ('pending', 'confirmed')
  ) then
    raise exception 'Une carte est déjà rattachée ou réclamée pour ce membre.';
  end if;

  v_annee := coalesce(v_profil.member_since, extract(year from now())::int);
  v_numero := public.next_card_number(v_annee);

  insert into public.member_cards
    (full_name, phone, card_number, member_since, city,
     title, domain, domain_autre, specialty,
     claim_status, claimed_by, claimed_at, confirmed_at)
  values
    (coalesce(nullif(btrim(v_profil.full_name), ''),
              nullif(btrim(concat_ws(' ', v_profil.first_name, v_profil.last_name)), ''),
              'Membre'),
     coalesce(nullif(btrim(v_profil.phone), ''), '-'),
     v_numero, v_annee, v_profil.city,
     v_profil.title, v_profil.domain, v_profil.domain_autre, v_profil.specialty,
     'confirmed', member_id, now(), now());

  update public.profiles
     set legacy_card_number = v_numero
   where id = member_id;

  return v_numero;
end;
$$;

grant execute on function public.creer_carte_membre(uuid) to authenticated;
