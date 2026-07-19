-- ============================================================
-- PHASE 27 — Limite de fréquence (rate limiting) sur les fonctions RPC
-- de listing (Phase 26), contre un compte qui boucle les appels pour
-- reconstituer tout le contenu au fil du temps.
--
-- Complète phase26-rpc-listes-limitees.sql : celle-ci plafonne le volume
-- d'UN appel (LIMIT), celle-ci plafonne le nombre d'appels par membre sur
-- une fenêtre de temps glissante.
--
-- Fonctionnement : chaque appel autorisé est journalisé dans
-- rpc_rate_limit_log (une ligne par appel réussi). Au-delà du seuil dans la
-- fenêtre, l'appel suivant échoue avec un message explicite plutôt que de
-- renvoyer des données. Aucune policy RLS n'est créée sur cette table :
-- elle est donc totalement inaccessible en lecture/écriture directe pour
-- authenticated/anon, seule la fonction check_rate_limit (SECURITY
-- DEFINER, même schéma que is_admin()/claim_member_card ailleurs dans ce
-- projet) y touche.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase26-rpc-listes-limitees.sql).
-- ============================================================

create table if not exists public.rpc_rate_limit_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null,
  bucket     text not null,
  called_at  timestamptz not null default now()
);

create index if not exists rpc_rate_limit_log_lookup
  on public.rpc_rate_limit_log (user_id, bucket, called_at);

alter table public.rpc_rate_limit_log enable row level security;
-- Aucune policy créée volontairement : select/insert/update/delete refusés
-- par défaut pour authenticated et anon.

create or replace function public.check_rate_limit(p_bucket text, p_max_calls int, p_window interval)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if auth.uid() is null then
    raise exception 'Authentification requise.';
  end if;

  delete from public.rpc_rate_limit_log
   where user_id = auth.uid() and bucket = p_bucket and called_at < now() - p_window;

  select count(*) into v_count
    from public.rpc_rate_limit_log
   where user_id = auth.uid() and bucket = p_bucket;

  if v_count >= p_max_calls then
    raise exception 'Trop de requêtes. Réessayez dans quelques minutes.';
  end if;

  insert into public.rpc_rate_limit_log (user_id, bucket) values (auth.uid(), p_bucket);
end;
$$;

grant execute on function public.check_rate_limit(text, int, interval) to authenticated;

-- ===== Les 6 fonctions de Phase 26, avec limite de fréquence ajoutée =====
-- Même signature et même contenu qu'avant, seule la vérification de
-- fréquence est ajoutée en première ligne. 30 appels / 5 minutes est très
-- large pour un usage normal (une poignée de chargements de page) mais
-- bloque un script qui boucle.

create or replace function public.forum_topics_list(p_limit int default 50)
returns table (
  id                uuid,
  title             text,
  body              text,
  last_activity_at  timestamptz,
  reply_count       int,
  author_name       text
)
language plpgsql
as $$
begin
  perform public.check_rate_limit('forum_topics_list', 30, interval '5 minutes');
  return query
    select t.id, t.title, t.body, t.last_activity_at, t.reply_count, p.full_name
    from public.forum_topics t
    left join public.profiles p on p.id = t.author_id
    order by t.last_activity_at desc
    limit least(coalesce(p_limit, 50), 100);
end;
$$;

create or replace function public.published_medical_lessons(p_limit int default 100)
returns setof public.medical_lessons
language plpgsql
as $$
begin
  perform public.check_rate_limit('published_medical_lessons', 30, interval '5 minutes');
  return query
    select * from public.medical_lessons
    where is_published = true
    order by category, order_index
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

create or replace function public.published_quizzes(p_limit int default 100)
returns setof public.quizzes
language plpgsql
as $$
begin
  perform public.check_rate_limit('published_quizzes', 30, interval '5 minutes');
  return query
    select * from public.quizzes
    where is_published = true
    order by category
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

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
language plpgsql
as $$
begin
  perform public.check_rate_limit('bibliotheque_documents', 30, interval '5 minutes');
  return query
    select id, title, excerpt, cover_image, file_path, bib_section, created_at
    from public.restricted_articles
    where category = 'bibliotheque'
    order by created_at desc
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

create or replace function public.published_products(p_limit int default 100)
returns setof public.products
language plpgsql
as $$
begin
  perform public.check_rate_limit('published_products', 30, interval '5 minutes');
  return query
    select * from public.products
    where is_published = true
    order by category, created_at
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

create or replace function public.published_product_photos(p_limit int default 500)
returns table (
  product_id    uuid,
  storage_path  text,
  order_index   int
)
language plpgsql
as $$
begin
  perform public.check_rate_limit('published_product_photos', 30, interval '5 minutes');
  return query
    select pp.product_id, pp.storage_path, pp.order_index
    from public.product_photos pp
    join public.products p on p.id = pp.product_id
    where p.is_published = true
    order by pp.order_index
    limit least(coalesce(p_limit, 500), 1000);
end;
$$;

-- Les grants de la Phase 26 restent valables (signature inchangée), inclus
-- ici pour rester exécutable même seul.
grant execute on function public.forum_topics_list(int) to authenticated;
grant execute on function public.published_medical_lessons(int) to authenticated;
grant execute on function public.published_quizzes(int) to authenticated;
grant execute on function public.bibliotheque_documents(int) to authenticated;
grant execute on function public.published_products(int) to authenticated;
grant execute on function public.published_product_photos(int) to authenticated;
