-- Espace Membres — Documents officiels réservés (Statuts, Règlement intérieur,
-- rapports, PV d'AG...)
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- (à appliquer après supabase/phase3b-generalize-restricted-content.sql)

-- ===== Nouvelle catégorie "document" =====
alter table public.restricted_articles drop constraint if exists restricted_articles_category_check;
alter table public.restricted_articles
  add constraint restricted_articles_category_check check (category in ('formation', 'actualite', 'document'));

-- Chemin du fichier dans le stockage Supabase (voir bucket ci-dessous)
alter table public.restricted_articles add column if not exists file_path text;

-- ===== Stockage des fichiers (bucket privé) =====
-- Bucket non public : personne ne peut deviner/partager une URL directe.
-- L'accès se fait uniquement via une URL signée générée à la demande, après
-- vérification que la personne connectée est un membre approuvé.
insert into storage.buckets (id, name, public)
values ('documents-reserves', 'documents-reserves', false)
on conflict (id) do nothing;

drop policy if exists "Members can read reserved documents" on storage.objects;
create policy "Members can read reserved documents"
  on storage.objects for select
  using (bucket_id = 'documents-reserves' and public.is_approved_member());

drop policy if exists "Admins can upload reserved documents" on storage.objects;
create policy "Admins can upload reserved documents"
  on storage.objects for insert
  with check (bucket_id = 'documents-reserves' and public.is_admin());

drop policy if exists "Admins can update reserved documents" on storage.objects;
create policy "Admins can update reserved documents"
  on storage.objects for update
  using (bucket_id = 'documents-reserves' and public.is_admin());

drop policy if exists "Admins can delete reserved documents" on storage.objects;
create policy "Admins can delete reserved documents"
  on storage.objects for delete
  using (bucket_id = 'documents-reserves' and public.is_admin());
