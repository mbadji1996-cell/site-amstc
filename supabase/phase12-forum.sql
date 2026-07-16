-- ============================================================
-- PHASE 12 — Forum de discussion entre membres.
--
-- Espace d'échange général (questions, discussions) accessible à tout
-- membre approuvé, comme la Boutique : gouverné par is_approved_member(),
-- pas is_active_member() (pas de lien avec la validité de la carte).
-- Liste unique de sujets sans catégorie, triée par activité récente.
--
-- Un membre peut modifier/supprimer ses propres sujets et réponses ; un
-- admin peut supprimer n'importe quoi (modération), directement depuis
-- les pages Forum (pas de panneau d'admin séparé).
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après schema.sql et phase2-roles.sql).
-- ============================================================

create table if not exists public.forum_topics (
  id                uuid primary key default gen_random_uuid(),
  author_id         uuid not null references public.profiles(id) on delete cascade,
  title             text not null,
  body              text not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  last_activity_at  timestamptz not null default now(),
  reply_count       int not null default 0
);

create table if not exists public.forum_replies (
  id          uuid primary key default gen_random_uuid(),
  topic_id    uuid not null references public.forum_topics(id) on delete cascade,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.forum_topics enable row level security;
alter table public.forum_replies enable row level security;

-- ===== Lecture : tout membre approuvé =====

drop policy if exists "Members can read forum topics" on public.forum_topics;
create policy "Members can read forum topics"
  on public.forum_topics for select
  using (public.is_approved_member());

drop policy if exists "Members can read forum replies" on public.forum_replies;
create policy "Members can read forum replies"
  on public.forum_replies for select
  using (public.is_approved_member());

-- ===== Création : son propre sujet/réponse =====

drop policy if exists "Members can create forum topics" on public.forum_topics;
create policy "Members can create forum topics"
  on public.forum_topics for insert
  with check (auth.uid() = author_id and public.is_approved_member());

drop policy if exists "Members can create forum replies" on public.forum_replies;
create policy "Members can create forum replies"
  on public.forum_replies for insert
  with check (auth.uid() = author_id and public.is_approved_member());

-- ===== Modification/suppression : l'auteur ou un admin (modération) =====

drop policy if exists "Authors and admins can update topics" on public.forum_topics;
create policy "Authors and admins can update topics"
  on public.forum_topics for update
  using (public.is_admin() or (auth.uid() = author_id and public.is_approved_member()));

drop policy if exists "Authors and admins can delete topics" on public.forum_topics;
create policy "Authors and admins can delete topics"
  on public.forum_topics for delete
  using (public.is_admin() or auth.uid() = author_id);

drop policy if exists "Authors and admins can update replies" on public.forum_replies;
create policy "Authors and admins can update replies"
  on public.forum_replies for update
  using (public.is_admin() or (auth.uid() = author_id and public.is_approved_member()));

drop policy if exists "Authors and admins can delete replies" on public.forum_replies;
create policy "Authors and admins can delete replies"
  on public.forum_replies for delete
  using (public.is_admin() or auth.uid() = author_id);

-- ===== Maintient reply_count / last_activity_at automatiquement =====
-- Permet de trier la liste des sujets par activité récente sans requête
-- d'agrégation côté client.

create or replace function public.forum_touch_topic()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.forum_topics
       set reply_count = reply_count + 1, last_activity_at = now()
     where id = new.topic_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.forum_topics
       set reply_count = greatest(reply_count - 1, 0)
     where id = old.topic_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists forum_replies_touch_topic on public.forum_replies;
create trigger forum_replies_touch_topic
  after insert or delete on public.forum_replies
  for each row execute function public.forum_touch_topic();
