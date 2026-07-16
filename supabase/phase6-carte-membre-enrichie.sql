-- ============================================================
-- PHASE 6 — Carte de membre enrichie (photo, titre, prénom/nom, domaine)
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- ============================================================

-- ===== Nouveaux champs de profil pour la carte =====
alter table public.profiles add column if not exists photo_url text;

alter table public.profiles add column if not exists title text;
alter table public.profiles drop constraint if exists profiles_title_check;
alter table public.profiles add constraint profiles_title_check check (title is null or title in ('Dr', 'Pr'));

alter table public.profiles add column if not exists first_name text;
alter table public.profiles add column if not exists last_name text;

alter table public.profiles add column if not exists domain text;
alter table public.profiles drop constraint if exists profiles_domain_check;
alter table public.profiles add constraint profiles_domain_check
  check (domain is null or domain in ('medecine', 'pharmacie', 'odontologie', 'soins_infirmiers', 'soins_obstetricaux', 'autre'));

alter table public.profiles add column if not exists domain_autre text;

-- ===== Stockage des photos de profil (bucket public) =====
-- Public en lecture : la photo doit s'afficher sur la carte (et un futur QR
-- de vérification) sans authentification supplémentaire. Chaque membre ne
-- peut écrire que dans son propre dossier ({user_id}/...).
insert into storage.buckets (id, name, public)
values ('member-photos', 'member-photos', true)
on conflict (id) do nothing;

drop policy if exists "Public read member photos" on storage.objects;
create policy "Public read member photos"
  on storage.objects for select
  using (bucket_id = 'member-photos');

drop policy if exists "Members can upload own photo" on storage.objects;
create policy "Members can upload own photo"
  on storage.objects for insert
  with check (bucket_id = 'member-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Members can update own photo" on storage.objects;
create policy "Members can update own photo"
  on storage.objects for update
  using (bucket_id = 'member-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Members can delete own photo" on storage.objects;
create policy "Members can delete own photo"
  on storage.objects for delete
  using (bucket_id = 'member-photos' and (storage.foldername(name))[1] = auth.uid()::text);
