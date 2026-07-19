-- ============================================================
-- PHASE 26 — Fonctions RPC avec LIMIT pour les listes à fort volume
-- (protection contre l'aspiration en masse via l'API Supabase).
--
-- Contexte : le Forum, les Enseignements Médicaux, la Bibliothèque et la
-- Boutique chargent leur liste complète en une seule requête, sans limite
-- côté client. Un compte membre (même tout juste créé) peut donc appeler
-- l'API Supabase directement et récupérer tout le contenu en un clic. Ces
-- fonctions RPC plafonnent le nombre de lignes renvoyées côté serveur,
-- indépendamment de ce que demande le client.
--
-- Toutes en SECURITY INVOKER (par défaut) : les policies RLS existantes sur
-- les tables sous-jacentes continuent de s'appliquer normalement, seule une
-- limite de lignes est ajoutée.
--
-- Portée volontairement limitée aux 4 pages de liste "grand public"
-- (forum.html, medical.html, bibliotheque.html, boutique.html). Les pages
-- de détail (un sujet, une leçon, un quiz) et les panneaux d'admin
-- continuent d'interroger les tables directement : ils ne présentent pas le
-- même risque d'aspiration en masse et ont besoin d'un accès complet.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase12-forum.sql, phase4-nouveaux-modules.sql,
-- phase16-bibliotheque.sql).
-- ============================================================

-- ===== Forum : liste des sujets =====
create or replace function public.forum_topics_list(p_limit int default 50)
returns table (
  id                uuid,
  title             text,
  body              text,
  last_activity_at  timestamptz,
  reply_count       int,
  author_name       text
)
language sql
stable
as $$
  select t.id, t.title, t.body, t.last_activity_at, t.reply_count, p.full_name
  from public.forum_topics t
  left join public.profiles p on p.id = t.author_id
  order by t.last_activity_at desc
  limit least(coalesce(p_limit, 50), 100);
$$;

grant execute on function public.forum_topics_list(int) to authenticated;

-- ===== Enseignements Médicaux : leçons et quiz publiés =====
create or replace function public.published_medical_lessons(p_limit int default 100)
returns setof public.medical_lessons
language sql
stable
as $$
  select * from public.medical_lessons
  where is_published = true
  order by category, order_index
  limit least(coalesce(p_limit, 100), 200);
$$;

grant execute on function public.published_medical_lessons(int) to authenticated;

create or replace function public.published_quizzes(p_limit int default 100)
returns setof public.quizzes
language sql
stable
as $$
  select * from public.quizzes
  where is_published = true
  order by category
  limit least(coalesce(p_limit, 100), 200);
$$;

grant execute on function public.published_quizzes(int) to authenticated;

-- ===== Bibliothèque : documents publiés =====
create or replace function public.bibliotheque_documents(p_limit int default 100)
returns table (
  id           uuid,
  title        text,
  excerpt      text,
  cover_image  text,
  file_path    text,
  bib_section  text,
  created_at   timestamptz
)
language sql
stable
as $$
  select id, title, excerpt, cover_image, file_path, bib_section, created_at
  from public.restricted_articles
  where category = 'bibliotheque'
  order by created_at desc
  limit least(coalesce(p_limit, 100), 200);
$$;

grant execute on function public.bibliotheque_documents(int) to authenticated;

-- ===== Boutique : produits publiés + leurs photos =====
create or replace function public.published_products(p_limit int default 100)
returns setof public.products
language sql
stable
as $$
  select * from public.products
  where is_published = true
  order by category, created_at
  limit least(coalesce(p_limit, 100), 200);
$$;

grant execute on function public.published_products(int) to authenticated;

create or replace function public.published_product_photos(p_limit int default 500)
returns table (
  product_id    uuid,
  storage_path  text,
  order_index   int
)
language sql
stable
as $$
  select pp.product_id, pp.storage_path, pp.order_index
  from public.product_photos pp
  join public.products p on p.id = pp.product_id
  where p.is_published = true
  order by pp.order_index
  limit least(coalesce(p_limit, 500), 1000);
$$;

grant execute on function public.published_product_photos(int) to authenticated;
