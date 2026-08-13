-- ============================================================
-- PHASE 72 - Relever le plafond de taille des documents.
--
-- POURQUOI. La limite de 50 Mo posée en phase19 datait du Supabase cloud
-- gratuit, où l'espace total était compté. Le site est depuis
-- auto-hébergé sur le VPS : l'espace est celui du disque, et un guide ou
-- un livre numérisé dépasse facilement 50 Mo. L'avertissement à 15 Mo
-- des écrans d'administration, qui invoquait « l'espace de stockage
-- gratuit », est retiré du site pour la même raison.
--
-- LE PLAFOND NE DISPARAÎT PAS, IL MONTE À 200 Mo. Deux raisons de garder
-- une borne : chaque fichier du Storage part dans la sauvegarde
-- QUOTIDIENNE, conservée 14 jours - un fichier de 1 Go pèserait 14 Go
-- sur la Storage Box - et les membres consultent depuis des téléphones,
-- où un document démesuré ne se laisse tout simplement pas ouvrir.
-- 200 Mo couvre tout document raisonnable ; la valeur se change ici même
-- si un besoin réel se présente.
--
-- Les photos (médiathèque, boutique, profil) gardent leurs limites de
-- phase19 : elles sont redimensionnées côté client avant l'envoi, les
-- plafonds n'y gênent personne.
--
-- ⚠ CE SCRIPT PEUT NE PAS SUFFIRE. L'instance auto-hébergée porte
-- souvent sa propre limite globale (variable FILE_SIZE_LIMIT du service
-- storage, 50 Mo par défaut chez Coolify), qui s'applique AVANT celle du
-- bucket. Vérifiez sur le VPS :
--
--   docker exec supabase-storage-rffqs8ck1ckdixkuu2xjo5sc printenv FILE_SIZE_LIMIT
--
-- Si elle affiche 52428800 (ou rien), ajoutez ou modifiez dans Coolify,
-- service supabase (amstc) > Environment Variables :
--
--   FILE_SIZE_LIMIT=209715200
--
-- puis Restart, et re-vérifiez par le même printenv. Sans cela, l'envoi
-- d'un fichier de plus de 50 Mo échouera encore, quel que soit le bucket.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

update storage.buckets
   set file_size_limit = 209715200  -- 200 Mo
 where id = 'documents-reserves';

-- annonce-photos, créé en phase34 APRÈS le script des limites (phase19),
-- n'en avait jamais reçu : il était illimité, constaté au contrôle
-- ci-dessous. Une photo d'annonce se borne comme les autres photos.
update storage.buckets
   set file_size_limit = 10485760  -- 10 Mo
 where id = 'annonce-photos';

-- Contrôle : la limite de chaque bucket, en Mo.
select id,
       coalesce((file_size_limit / 1048576)::text, 'illimité') as limite_mo
  from storage.buckets
 order by id;
