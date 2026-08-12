-- ============================================================
-- NETTOYAGE - Supprimer deux paiements de validité de test
--
-- Deux paiements factices (références « sfsfsf » et « xwxw », 4 000 F et
-- 2 000 F, Wave, 16/07/2026) faussent les encaissements 2026. Ils sont
-- rattachés au compte drmouhamedbadji@gmail.com.
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
-- La ligne « zgfezgege » (5 000 F, membre supprimé) apparaît aussi : elle
-- ressemble à un test mais n'était pas dans la demande - voir l'étape 5.
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

-- ===== 5. La ligne « zgfezgege » (COMMENTÉ - probablement un test aussi) =====
-- 5 000 F, 5 ans, rattachée à un compte supprimé (aucun profil ne la
-- porte plus, d'où le « - » à l'écran). Son effet sur card_valid_until a
-- disparu avec le compte ; ne reste que le montant dans les statistiques.
--
--   delete from public.card_validity_payments
--    where payment_reference = 'zgfezgege' and user_id is null;

-- ===== 6. Contrôle : les encaissements 2026 recalculés =====
select count(*) as paiements_confirmes,
       coalesce(sum(amount_fcfa), 0) as total_fcfa
  from public.card_validity_payments
 where status = 'confirmed'
   and extract(year from created_at) = 2026;
