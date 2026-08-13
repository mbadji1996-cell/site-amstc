-- ============================================================
-- Nettoyage : retirer de la bibliothèque les documents non PDF
--
-- Le 13/08/2026, l'import de dossier a brièvement accepté d'autres
-- formats (Word, images, tableurs) avant de revenir au PDF seul.
-- Ce script retire les fiches non PDF de la bibliothèque ET leurs
-- fichiers du stockage, pour ne pas laisser d'orphelins invisibles.
--
-- Il ne touche QUE la bibliothèque (category = 'bibliotheque') :
-- les documents officiels (category = 'document') sont hors champ.
--
-- À exécuter dans SQL Editor de l'instance api.amstc.org.
-- ============================================================

begin;

-- 0. Ce qui va partir - à lire AVANT de valider.
select id, title, file_path, created_at
from public.restricted_articles
where category = 'bibliotheque'
  and file_path is not null
  and lower(file_path) not like '%.pdf';

-- 1. Les fichiers du stockage correspondant à ces fiches.
delete from storage.objects o
using public.restricted_articles a
where o.bucket_id = 'documents-reserves'
  and o.name = a.file_path
  and a.category = 'bibliotheque'
  and a.file_path is not null
  and lower(a.file_path) not like '%.pdf';

-- 2. Les fiches elles-mêmes.
delete from public.restricted_articles
where category = 'bibliotheque'
  and file_path is not null
  and lower(file_path) not like '%.pdf';

commit;

-- Vérification : ne doit plus rien renvoyer.
select count(*) as fiches_non_pdf_restantes
from public.restricted_articles
where category = 'bibliotheque'
  and file_path is not null
  and lower(file_path) not like '%.pdf';
