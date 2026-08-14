-- ============================================================
-- NETTOYAGE - Supprimer trois paiements de validité de test
--
-- Trois paiements factices du 16/07/2026 faussent les encaissements
-- 2026 : « sfsfsf » (4 000 F) et « xwxw » (2 000 F) sur le compte
-- drmouhamedbadji@gmail.com, et « zgfezgege » (5 000 F) sur un compte de
-- test déjà supprimé.
--
-- ATTENTION, LA LIGNE N'EST PAS LA SEULE TRACE. Confirmer un paiement de
-- validité ÉTEND profiles.card_valid_until du nombre d'années payées
-- (phase7). Ces deux tests ont donc allongé la validité de la carte du
-- compte de 4 + 2 = 6 ans. Supprimer les lignes corrige les
-- encaissements, mais pas la validité : l'étape 4 s'en charge,
-- volontairement commentée - voir plus bas.
--
-- À exécuter dans Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger : la seconde exécution ne trouve plus rien.
-- ============================================================

-- ===== 1. Ce qui va être supprimé, avant d'y toucher =====
select v.id, p.email, v.years_requested, v.amount_fcfa, v.payment_method,
       v.payment_reference, v.status, v.created_at
  from public.card_validity_payments v
  left join public.profiles p on p.id = v.user_id
 where v.payment_reference in ('sfsfsf', 'xwxw', 'zgfezgege')
 order by v.created_at;

-- ===== 2. Suppression des deux tests =====
-- Ciblage par référence ET par compte : une référence est saisie
-- librement par le membre, elle pourrait en théorie se répéter ailleurs.
delete from public.card_validity_payments
 where payment_reference in ('sfsfsf', 'xwxw')
   and user_id = (select id from public.profiles where email = 'drmouhamedbadji@gmail.com');

-- ===== 3. État de la validité du compte de test =====
-- Les tests ont ajouté 6 ans à cette valeur. Notez-la avant l'étape 4.
select email, card_valid_until, legacy_card_number
  from public.profiles
 where email = 'drmouhamedbadji@gmail.com';

-- ===== 4. Corriger la validité (COMMENTÉ - à décider au vu de l'étape 3) =====
-- L'extension étant purement additive, retirer 6 ans restaure la valeur
-- d'avant les tests... SAUF si la validité a été corrigée à la main
-- depuis (écran Membres > années). Dans ce cas, fixez directement la
-- bonne année au lieu de soustraire.
--
--   update public.profiles
--      set card_valid_until = card_valid_until - 6
--    where email = 'drmouhamedbadji@gmail.com';

-- ===== 5. La ligne « zgfezgege » : un test aussi, confirmé =====
-- CORRECTION DU 14/08/2026. La première version supprimait « où
-- user_id is null » : condition IMPOSSIBLE, la colonne est non nulle
-- par construction (et la suppression d'un profil emporte ses
-- paiements en cascade). Le « - » à l'écran vient d'une fiche liée
-- sans nom, pas d'une fiche absente - la ligne n'était donc jamais
-- supprimée, comme constaté.

-- 5a. Identifier le PORTEUR réel avant de toucher quoi que ce soit :
--     notez user_id, email et card_valid_until pour l'étape 5c.
select v.id, v.user_id, p.email, p.full_name, p.status, p.card_valid_until
  from public.card_validity_payments v
  left join public.profiles p on p.id = v.user_id
 where v.payment_reference = 'zgfezgege';

-- 5b. Supprimer la ligne de test, ciblée par sa référence ET son
--     contenu exact (5 ans, 5 000 F) pour ne pas emporter un éventuel
--     homonyme légitime.
delete from public.card_validity_payments
 where payment_reference = 'zgfezgege'
   and years_requested = 5
   and amount_fcfa = 5000;

-- 5c. (COMMENTÉ - à décider au vu de 5a) Ce paiement étant CONFIRMÉ,
--     il a étendu card_valid_until du porteur de 5 ans. Si la fiche vue
--     en 5a existe encore et que sa validité n'a pas été corrigée à la
--     main depuis, retirez ces 5 ans en remplaçant l'identifiant :
--
--   update public.profiles
--      set card_valid_until = card_valid_until - 5
--    where id = '<user_id vu en 5a>';

-- ===== 6. Contrôle : les encaissements 2026 recalculés =====
select count(*) as paiements_confirmes,
       coalesce(sum(amount_fcfa), 0) as total_fcfa
  from public.card_validity_payments
 where status = 'confirmed'
   and extract(year from created_at) = 2026;
