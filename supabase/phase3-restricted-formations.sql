-- Espace Membres — Phase 3 : Formations réservées aux membres
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- (à appliquer après supabase/schema.sql et supabase/phase2-roles.sql)

-- ===== Table du contenu réservé =====
-- Volontairement séparée du dépôt Git : contrairement aux articles publiés
-- via Decap CMS (qui finissent en clair dans le dépôt GitHub public), ce
-- contenu ne vit que dans la base Supabase, protégée par les règles RLS
-- ci-dessous. C'est la seule façon d'avoir un contenu réellement privé sur
-- ce site.
create table if not exists public.restricted_formations (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  excerpt text,
  content text not null,
  cover_image text,
  video_url text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.restricted_formations enable row level security;

-- ===== Le compte connecté est-il un membre approuvé et actif ? =====
create or replace function public.is_approved_member()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved' and is_active
  );
$$;

-- ===== Accès en lecture complète : membres approuvés uniquement =====
drop policy if exists "Members can view restricted formations" on public.restricted_formations;
create policy "Members can view restricted formations"
  on public.restricted_formations for select
  using (public.is_approved_member());

-- ===== Gestion (création / modification / suppression) : admins =====
drop policy if exists "Admins can insert restricted formations" on public.restricted_formations;
create policy "Admins can insert restricted formations"
  on public.restricted_formations for insert
  with check (public.is_admin());

drop policy if exists "Admins can update restricted formations" on public.restricted_formations;
create policy "Admins can update restricted formations"
  on public.restricted_formations for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins can delete restricted formations" on public.restricted_formations;
create policy "Admins can delete restricted formations"
  on public.restricted_formations for delete
  using (public.is_admin());

-- ===== Aperçu public (teaser) =====
-- Une vue ne renvoyant que les colonnes "vitrine" (titre, résumé, image),
-- jamais le contenu complet ni la vidéo. Une vue Postgres s'exécute avec
-- les droits de son propriétaire (ici un rôle qui contourne RLS), ce qui
-- permet d'exposer ce sous-ensemble de colonnes à tout le monde tout en
-- gardant la table de base entièrement verrouillée aux membres.
create or replace view public.restricted_formations_teasers as
  select id, title, excerpt, cover_image, created_at
  from public.restricted_formations;

grant select on public.restricted_formations_teasers to anon, authenticated;
