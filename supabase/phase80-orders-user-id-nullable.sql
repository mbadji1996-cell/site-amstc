-- ============================================================
-- PHASE 80 - orders.user_id : lever une contradiction du schéma
--
-- LE DÉFAUT. La table des commandes déclare :
--
--   user_id uuid not null references auth.users(id) on delete set null
--
-- « not null » et « on delete set null » se contredisent. Le jour où un
-- compte ayant passé commande est supprimé, Postgres tente de vider
-- user_id, ce que « not null » interdit : c'est la SUPPRESSION DU COMPTE
-- qui échoue, avec un message qui ne désigne pas la boutique. Le défaut
-- dort tant qu'aucun acheteur n'est supprimé - il ne s'est donc jamais
-- manifesté, la boutique n'ayant servi qu'à des essais.
--
-- LE CHOIX RETENU : rendre la colonne nullable, donc DÉTACHER la
-- commande du compte supprimé plutôt que de l'effacer. Une commande est
-- une pièce comptable : elle doit survivre au départ de son auteur, le
-- montant encaissé restant vrai. C'est déjà le traitement des paiements
-- de validité et de cotisation.
--
-- L'écran d'administration le supporte sans modification : il lit
-- « o.profiles || {} » puis « full_name || '-' », et affichait déjà « - »
-- pour les fiches sans nom.
--
-- LES POLITIQUES RLS N'ONT PAS BESOIN DE CHANGER, et c'est voulu :
--   - « Members can read own orders » compare auth.uid() = user_id. Avec
--     user_id à NULL la comparaison vaut NULL, donc faux : une commande
--     orpheline n'est visible d'AUCUN membre. C'est le comportement
--     souhaité.
--   - « Admins can manage all orders » ne regarde pas user_id :
--     l'administration continue de tout voir, y compris les orphelines.
--
-- Cette contradiction a été cherchée dans tout le schéma : orders est la
-- SEULE table concernée.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. État avant =====
select column_name, is_nullable
  from information_schema.columns
 where table_schema = 'public' and table_name = 'orders' and column_name = 'user_id';

-- ===== 2. Le correctif =====
alter table public.orders alter column user_id drop not null;

-- ===== 3. Contrôles =====
-- is_nullable doit être passé à YES.
select column_name, is_nullable
  from information_schema.columns
 where table_schema = 'public' and table_name = 'orders' and column_name = 'user_id';

-- La clé étrangère doit toujours être « SET NULL » - c'est elle qui
-- détache la commande, et elle n'est pas touchée par ce script.
select tc.constraint_name, rc.delete_rule
  from information_schema.table_constraints tc
  join information_schema.referential_constraints rc
    on rc.constraint_name = tc.constraint_name
 where tc.table_schema = 'public' and tc.table_name = 'orders'
   and tc.constraint_type = 'FOREIGN KEY';

-- Aucune commande n'est orpheline aujourd'hui : ce script ne change rien
-- aux données existantes, il n'ouvre que la possibilité.
select count(*) as commandes_orphelines
  from public.orders where user_id is null;
