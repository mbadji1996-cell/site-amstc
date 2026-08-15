-- ============================================================
-- NETTOYAGE - Supprimer les demandes de campagne de test
--
-- Constat du 15/08/2026 : les deux demandes enregistrées sont des essais.
--
--   1. « Test » à Kakene, 78888888888, test@test.com, description
--      « Dbdndndnnwnwsnwbwnxnwn », non retenue, reçue le 27/07/2026.
--   2. « Mouhamed BADJI » à Thies, description « Test », validée,
--      reçue le 24/07/2026 - un essai de l'administration elle-même.
--
-- CIBLAGE. La table campaign_requests n'a AUCUNE référence vers d'autres
-- lignes en dehors de handled_by (l'administrateur qui a traité la
-- demande, en « on delete set null ») : supprimer une demande n'entraîne
-- rien d'autre, et ne laisse aucun orphelin.
--
-- On cible par le TÉLÉPHONE de la demande - une donnée saisie par le
-- demandeur, visible à l'écran, et qui distingue sans ambiguïté ces deux
-- lignes. Volontairement PAS par le statut : la seconde est « validée »,
-- et il ne faut pas laisser croire que seules les demandes rejetées
-- partent.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger : la seconde exécution ne trouve plus rien.
-- ============================================================

-- ===== 1. TOUTES les demandes, avant d'y toucher =====
-- À LIRE AVANT DE CONTINUER : si une demande réelle apparaît ici,
-- retirez son téléphone de la liste de l'étape 2.
select id, full_name, locality, phone, email, status,
       left(description, 60) as description, created_at
  from public.campaign_requests
 order by created_at desc;

-- ===== 2. Suppression des deux essais =====
delete from public.campaign_requests
 where phone in ('78888888888', '+221778890459');

-- ===== 3. Contrôle =====
select count(*) as demandes_restantes from public.campaign_requests;

select full_name, locality, phone, status, created_at
  from public.campaign_requests
 order by created_at desc;

-- ============================================================
-- VARIANTE (COMMENTÉE) - vider complètement la table
--
-- Si l'étape 1 confirme qu'aucune demande réelle n'existe, cette ligne
-- repart d'une table vide :
--
--   delete from public.campaign_requests;
--
-- ============================================================
-- ATTENTION AU NUMÉRO DE LA SECONDE DEMANDE.
--
-- « +221778890459 » est le numéro de l'administration, qui a servi à
-- faire cet essai. La suppression ne touche QUE cette table : le compte
-- membre, sa carte et ses cotisations sont dans d'autres tables et ne
-- sont pas concernés. Mais si vous refaites un essai depuis ce même
-- numéro plus tard, pensez à retirer cette ligne du script avant de le
-- rejouer - sinon il emporterait aussi la nouvelle demande.
-- ============================================================
