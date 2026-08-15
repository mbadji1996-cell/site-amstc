-- ============================================================
-- NETTOYAGE - Supprimer les commandes de test de la boutique
--
-- Constat du 15/08/2026 : l'onglet Commandes ne contient que des essais -
-- six commandes « Blouse manche courte » à 5 000 F, toutes ANNULÉES, avec
-- des références manifestement saisies au hasard : « test » (×3),
-- « sdzsfs », « feff », « DGDFD ».
--
-- POURQUOI PAS DE CIBLAGE « SANS MEMBRE ». Trois lignes affichent « - »
-- dans la colonne Membre, mais ce n'est PAS un lien manquant :
-- orders.user_id est déclaré « not null ». Le tiret vient de l'écran, qui
-- affiche « - » quand la fiche liée n'a pas de nom. Cibler « user_id is
-- null » ne trouverait donc rien - exactement l'erreur commise sur le
-- paiement « zgfezgege », qui a survécu à plusieurs exécutions.
-- On cible par RÉFÉRENCE, ce qui est vérifiable à l'œil.
--
-- Les articles ne sont pas dans une table séparée : ils vivent dans la
-- colonne « items » (jsonb) de la commande. Supprimer la ligne suffit,
-- aucun orphelin possible.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger : la seconde exécution ne trouve plus rien.
-- ============================================================

-- ===== 1. TOUTES les commandes, avant d'y toucher =====
-- À LIRE AVANT DE CONTINUER : si cette liste contient une commande
-- réelle, ne lancez pas l'étape 2 telle quelle - retirez sa référence
-- de la liste.
select o.id, o.status, o.payment_method, o.payment_reference,
       o.total_fcfa, o.created_at,
       coalesce(p.full_name, '(fiche sans nom)') as membre, p.email
  from public.orders o
  left join public.profiles p on p.id = o.user_id
 order by o.created_at desc;

-- ===== 2. Suppression des commandes de test =====
-- Double condition : la référence ET le statut « annulée ». Une commande
-- réelle qui porterait par malchance l'une de ces références serait
-- forcément dans un autre statut (payée, en traitement, expédiée) et
-- resterait donc intacte.
delete from public.orders
 where status = 'cancelled'
   and payment_reference in ('test', 'sdzsfs', 'feff', 'DGDFD');

-- ===== 3. Contrôle =====
select count(*) as commandes_restantes from public.orders;

select o.status, o.payment_reference, o.total_fcfa, o.created_at
  from public.orders o
 order by o.created_at desc;

-- ============================================================
-- VARIANTE (COMMENTÉE) - vider complètement la table
--
-- Si l'étape 1 confirme qu'AUCUNE commande réelle n'existe - ce qui est
-- probable, la boutique n'ayant pas encore servi - cette ligne repart
-- d'une table vide, y compris pour d'éventuels essais futurs portant
-- d'autres références :
--
--   delete from public.orders;
--
-- ============================================================
-- À SIGNALER, sans rapport avec ce nettoyage mais repéré en le
-- préparant : la définition de la table est contradictoire.
--
--   user_id uuid not null references auth.users(id) on delete set null
--
-- « not null » et « on delete set null » se contredisent : le jour où
-- vous supprimerez un compte ayant passé commande, Postgres tentera de
-- mettre user_id à NULL, ce que « not null » interdit - et c'est la
-- SUPPRESSION DU COMPTE qui échouera, avec un message peu parlant.
--
-- Le correctif, à décider séparément (garder la commande en la
-- détachant du compte supprimé, ce qui préserve l'historique
-- comptable) :
--
--   alter table public.orders alter column user_id drop not null;
--
-- Ou, si vous préférez que les commandes disparaissent avec le compte :
--
--   alter table public.orders drop constraint orders_user_id_fkey;
--   alter table public.orders add constraint orders_user_id_fkey
--     foreign key (user_id) references auth.users(id) on delete cascade;
-- ============================================================
