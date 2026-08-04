-- ============================================================
-- PHASE 40 — Numéroter les cartes importées sans numéro, et reporter le
-- numéro sur les membres à qui elles ont déjà été attribuées.
--
-- Cause : des trois chemins de création d'une carte dans
-- membres/cartes-admin.html, seul l'import Excel n'attribuait pas de
-- card_number (la création manuelle et l'import par collage génèrent
-- « AMSTC-<année>-<n> »). Ces cartes arrivaient donc vides, et
-- assign_member_card ne pouvant recopier qu'un numéro existant, le membre
-- destinataire n'affichait aucun numéro - quelle que soit la page ayant
-- servi à l'attribution.
--
-- Le code est corrigé (l'import Excel numérote désormais comme les
-- autres) ; ce script rattrape l'existant.
--
-- Sans danger et ré-exécutable : ne touche qu'aux lignes dont le numéro
-- est absent, et poursuit la numérotation après le dernier numéro déjà
-- utilisé pour chaque année, sans jamais écraser un numéro existant.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

-- ===== 1. Numéroter les cartes qui n'ont pas de numéro =====
with existants as (
  -- Dernier numéro déjà attribué pour chaque année, pour enchaîner sans
  -- créer de doublon.
  select
    (regexp_match(card_number, '^AMSTC-(\d{4})-(\d+)$'))[1]::int as annee,
    max(((regexp_match(card_number, '^AMSTC-(\d{4})-(\d+)$'))[2])::int) as dernier
  from public.member_cards
  where card_number ~ '^AMSTC-\d{4}-\d+$'
  group by 1
),
a_numeroter as (
  select
    id,
    coalesce(member_since, extract(year from created_at)::int) as annee,
    row_number() over (
      partition by coalesce(member_since, extract(year from created_at)::int)
      order by created_at, id
    ) as rang
  from public.member_cards
  where card_number is null or btrim(card_number) = ''
)
update public.member_cards c
   set card_number = 'AMSTC-' || a.annee || '-'
                     || lpad((coalesce(e.dernier, 0) + a.rang)::text, 3, '0')
  from a_numeroter a
  left join existants e on e.annee = a.annee
 where c.id = a.id;

-- ===== 2. Reporter le numéro sur les membres déjà servis =====
-- Les cartes attribuées avant ce correctif ont laissé profiles.
-- legacy_card_number vide : on le renseigne maintenant que la carte a un
-- numéro. On ne remplace jamais un numéro déjà présent sur le profil.
update public.profiles p
   set legacy_card_number = c.card_number
  from public.member_cards c
 where c.claimed_by = p.id
   and c.claim_status = 'confirmed'
   and c.card_number is not null
   and (p.legacy_card_number is null or btrim(p.legacy_card_number) = '');
