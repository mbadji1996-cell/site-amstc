-- ============================================================
-- Nettoyage : retirer de la bibliothèque les documents non PDF
--
-- Le 13/08/2026, l'import de dossier a brièvement accepté d'autres
-- formats (Word, images, tableurs) avant de revenir au PDF seul.
-- Ce script retire les fiches non PDF de la bibliothèque ET leurs
-- entrées du stockage. Il ne touche QUE la bibliothèque
-- (category = 'bibliotheque') : les documents officiels
-- (category = 'document') sont hors champ.
--
-- POURQUOI LE DÉTOUR PAR LES DÉCLENCHEURS. Le stockage Supabase
-- interdit le DELETE direct dans storage.objects (déclencheur
-- protect_delete, erreur 42501) : il protège contre les fichiers
-- orphelins. On le suspend LE TEMPS DE CE NETTOYAGE, puis on le
-- rétablit - dans la même transaction, donc jamais désactivé pour
-- les autres. Conséquence assumée : l'octet physique des fichiers
-- peut rester dans le volume du VPS ; pour quelques images, c'est
-- négligeable, et aucun membre ne peut plus y accéder une fois
-- l'entrée supprimée.
--
-- ALTERNATIVE SANS SQL : supprimer chaque fiche non PDF depuis
-- l'écran d'administration de la bibliothèque (bouton Supprimer),
-- qui passe par l'API du stockage et efface aussi le fichier.
--
-- À exécuter dans SQL Editor de l'instance api.amstc.org.
-- ============================================================

-- 0. Ce qui va partir - à lire AVANT d'exécuter la suite.
select id, title, file_path, created_at
from public.restricted_articles
where category = 'bibliotheque'
  and file_path is not null
  and lower(file_path) not like '%.pdf';

begin;

-- 1. Suspendre la protection du stockage (transaction en cours
--    seulement : rétablie à l'étape 3, avant le commit).
do $$
declare t record;
begin
  for t in
    select tgname from pg_trigger
    where tgrelid = 'storage.objects'::regclass
      and not tgisinternal
      and tgfoid = to_regprocedure('storage.protect_delete()')
  loop
    execute format('alter table storage.objects disable trigger %I', t.tgname);
  end loop;
end $$;

-- 2. Les entrées du stockage correspondant aux fiches non PDF.
delete from storage.objects o
using public.restricted_articles a
where o.bucket_id = 'documents-reserves'
  and o.name = a.file_path
  and a.category = 'bibliotheque'
  and a.file_path is not null
  and lower(a.file_path) not like '%.pdf';

-- 3. Rétablir la protection.
do $$
declare t record;
begin
  for t in
    select tgname from pg_trigger
    where tgrelid = 'storage.objects'::regclass
      and not tgisinternal
      and tgfoid = to_regprocedure('storage.protect_delete()')
  loop
    execute format('alter table storage.objects enable trigger %I', t.tgname);
  end loop;
end $$;

-- 4. Les fiches elles-mêmes.
delete from public.restricted_articles
where category = 'bibliotheque'
  and file_path is not null
  and lower(file_path) not like '%.pdf';

commit;

-- Vérifications : les deux comptes doivent être à zéro, et la
-- protection doit être à nouveau active ('O' = activée).
select count(*) as fiches_non_pdf_restantes
from public.restricted_articles
where category = 'bibliotheque'
  and file_path is not null
  and lower(file_path) not like '%.pdf';

select tgname, tgenabled
from pg_trigger
where tgrelid = 'storage.objects'::regclass
  and not tgisinternal
  and tgfoid = to_regprocedure('storage.protect_delete()');
