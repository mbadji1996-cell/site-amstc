-- ============================================================
-- PHASE 34 — Image dans les annonces de l'espace membres
--
-- Permet à l'admin de publier une annonce avec une image seule, une image
-- accompagnée d'un titre/texte, ou juste du texte (comportement existant,
-- inchangé). Réutilise exactement le schéma de bucket privé de
-- boutique-photos (phase18) : bucket privé, lecture gardée par RLS aux
-- membres approuvés, écriture réservée aux admins.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase32-annonces-membres.sql).
-- ============================================================

alter table public.member_announcements
  alter column title drop not null,
  alter column body drop not null,
  add column if not exists image_path text;

-- Au moins une image, ou un titre + un texte : jamais une annonce totalement vide.
alter table public.member_announcements drop constraint if exists member_announcements_content_check;
alter table public.member_announcements
  add constraint member_announcements_content_check
  check (image_path is not null or (title is not null and body is not null));

insert into storage.buckets (id, name, public)
values ('annonce-photos', 'annonce-photos', false)
on conflict (id) do nothing;

drop policy if exists "Members can read annonce photos" on storage.objects;
create policy "Members can read annonce photos"
  on storage.objects for select
  using (bucket_id = 'annonce-photos' and public.is_approved_member());

drop policy if exists "Admins can upload annonce photos" on storage.objects;
create policy "Admins can upload annonce photos"
  on storage.objects for insert with check (bucket_id = 'annonce-photos' and public.is_admin());

drop policy if exists "Admins can update annonce photos" on storage.objects;
create policy "Admins can update annonce photos"
  on storage.objects for update using (bucket_id = 'annonce-photos' and public.is_admin());

drop policy if exists "Admins can delete annonce photos" on storage.objects;
create policy "Admins can delete annonce photos"
  on storage.objects for delete using (bucket_id = 'annonce-photos' and public.is_admin());
