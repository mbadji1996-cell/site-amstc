-- ============================================================
-- PHASE 14 — Médiathèque : galerie photo Année > Dossier d'activité > Photos.
--
-- Accès comme la Boutique/le Forum : tout membre approuvé
-- (is_approved_member()), sans lien avec la validité de la carte. Gestion
-- (créer un dossier, importer des photos, publier, supprimer) réservée aux
-- admins.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après schema.sql et phase2-roles.sql).
-- ============================================================

create table if not exists public.media_folders (
  id           uuid primary key default gen_random_uuid(),
  year         int not null,
  title        text not null,
  cover_path   text,
  is_published boolean not null default false,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);

create table if not exists public.media_photos (
  id           uuid primary key default gen_random_uuid(),
  folder_id    uuid not null references public.media_folders(id) on delete cascade,
  storage_path text not null,
  order_index  int not null default 0,
  created_at   timestamptz not null default now()
);

alter table public.media_folders enable row level security;
alter table public.media_photos enable row level security;

-- ===== Lecture : dossier publié -> tout membre approuvé ; admin voit tout =====

drop policy if exists "Members can read published folders" on public.media_folders;
create policy "Members can read published folders"
  on public.media_folders for select
  using (public.is_admin() or (is_published and public.is_approved_member()));

drop policy if exists "Members can read photos of visible folders" on public.media_photos;
create policy "Members can read photos of visible folders"
  on public.media_photos for select
  using (
    exists (
      select 1 from public.media_folders f
      where f.id = folder_id
        and (public.is_admin() or (f.is_published and public.is_approved_member()))
    )
  );

-- ===== Écriture : admin uniquement =====

drop policy if exists "Admins can manage folders" on public.media_folders;
create policy "Admins can manage folders"
  on public.media_folders for all
  using (public.is_admin());

drop policy if exists "Admins can manage photos" on public.media_photos;
create policy "Admins can manage photos"
  on public.media_photos for all
  using (public.is_admin());

-- ===== Bucket privé (même schéma que documents-reserves, phase3c) =====
-- L'accès réel aux fichiers est gardé par la lecture RLS des tables
-- ci-dessus : le chemin d'une photo d'un dossier non publié n'est jamais
-- renvoyé à un membre non-admin, donc jamais transformé en URL signée.

insert into storage.buckets (id, name, public)
values ('mediatheque-photos', 'mediatheque-photos', false)
on conflict (id) do nothing;

drop policy if exists "Members can read mediatheque photos" on storage.objects;
create policy "Members can read mediatheque photos"
  on storage.objects for select
  using (bucket_id = 'mediatheque-photos' and public.is_approved_member());

drop policy if exists "Admins can upload mediatheque photos" on storage.objects;
create policy "Admins can upload mediatheque photos"
  on storage.objects for insert
  with check (bucket_id = 'mediatheque-photos' and public.is_admin());

drop policy if exists "Admins can update mediatheque photos" on storage.objects;
create policy "Admins can update mediatheque photos"
  on storage.objects for update
  using (bucket_id = 'mediatheque-photos' and public.is_admin());

drop policy if exists "Admins can delete mediatheque photos" on storage.objects;
create policy "Admins can delete mediatheque photos"
  on storage.objects for delete
  using (bucket_id = 'mediatheque-photos' and public.is_admin());
