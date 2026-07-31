-- ============================================================
-- PHASE 36 — Médiathèque : index manquants et comptage des photos
--
-- Contexte : la médiathèque contient plus de 7000 photos, mais
-- media_photos n'avait aucun index sur folder_id, pourtant utilisé par
-- toutes les requêtes (liste d'un album, comptage, suppression en
-- cascade). Chaque lecture parcourait donc la table entière en évaluant
-- la règle RLS ligne par ligne.
--
-- Conséquence observée : la page d'administration affichait « 0 photo »
-- pour tous les albums. La requête de comptage rapatriait les 7000+
-- lignes, dépassait le délai maximal autorisé, et l'erreur était ignorée
-- côté navigateur - un échec indiscernable d'un album réellement vide.
--
-- À exécuter une seule fois : Studio > SQL Editor > New query > Run.
-- Sans danger et ré-exécutable (idempotent).
-- ============================================================

-- ===== 1. Index manquants =====
create index if not exists media_photos_folder_id_idx
  on public.media_photos (folder_id);

-- Tri des photos dans un album (order_index) et parcours de l'arborescence
create index if not exists media_photos_folder_order_idx
  on public.media_photos (folder_id, order_index);

create index if not exists media_folders_parent_id_idx
  on public.media_folders (parent_id);

-- ===== 2. Comptage des photos par album =====
-- Renvoie une ligne par album au lieu de rapatrier toutes les photos pour
-- les compter côté navigateur. Volontairement SANS security definer : les
-- règles RLS de media_photos s'appliquent donc normalement à l'appelant
-- (un admin voit tout, un membre uniquement les albums publiés).
create or replace function public.media_photo_counts()
returns table (
  folder_id   uuid,
  photo_count bigint
)
language sql
stable
as $$
  select p.folder_id, count(*)::bigint
  from public.media_photos p
  group by p.folder_id;
$$;

grant execute on function public.media_photo_counts() to authenticated;
