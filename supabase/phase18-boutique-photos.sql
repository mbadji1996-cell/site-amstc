-- Phase 18 : photos multiples pour les produits Boutique (carousel)
--
-- Le formulaire admin utilisait des noms de colonnes qui n'ont jamais existé
-- sur products/orders (price/is_active/total/delivery_address/note au lieu
-- de price_fcfa/is_published/total_fcfa/shipping_address/notes) : ce bug est
-- corrigé côté HTML/JS uniquement, aucune migration nécessaire pour ça.
--
-- Ce fichier fait deux choses :
-- 1) Assouplit la contrainte sur products.category : le formulaire admin est
--    un champ texte libre depuis toujours, pas une liste déroulante, donc la
--    contrainte figée ('vetements','papeterie','materiel','accessoires')
--    rejetait déjà toute autre valeur saisie (ex. "Blouses").
-- 2) Ajoute une table product_photos (plusieurs photos par produit, comme
--    media_photos pour la Médiathèque) + un bucket Storage dédié, pour
--    afficher un carousel côté membre.

alter table public.products
  drop constraint if exists products_category_check;

-- Le formulaire admin et l'affichage membre traitent stock = NULL comme
-- "illimité" (champ laissé vide), mais la colonne était NOT NULL : tout
-- produit sans stock précisé échouait à l'enregistrement.
alter table public.products
  alter column stock drop not null;

create table if not exists public.product_photos (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id) on delete cascade,
  storage_path  text not null,
  order_index   int not null default 0,
  created_at    timestamptz not null default now()
);

alter table public.product_photos enable row level security;

-- Lecture : comme pour products (membre approuvé + produit publié, ou admin).
drop policy if exists "Members can read photos of visible products" on public.product_photos;
create policy "Members can read photos of visible products"
  on public.product_photos for select
  using (
    exists (
      select 1 from public.products p
      where p.id = product_id
        and (public.is_admin() or (p.is_published and public.is_approved_member()))
    )
  );

-- Écriture : admin uniquement.
drop policy if exists "Admins can manage product photos" on public.product_photos;
create policy "Admins can manage product photos"
  on public.product_photos for all using (public.is_admin());

-- Bucket privé, même schéma que mediatheque-photos (phase14) : accès fichier
-- réel gardé par la lecture RLS de product_photos ci-dessus.
insert into storage.buckets (id, name, public)
values ('boutique-photos', 'boutique-photos', false)
on conflict (id) do nothing;

drop policy if exists "Members can read boutique photos" on storage.objects;
create policy "Members can read boutique photos"
  on storage.objects for select
  using (bucket_id = 'boutique-photos' and public.is_approved_member());

drop policy if exists "Admins can upload boutique photos" on storage.objects;
create policy "Admins can upload boutique photos"
  on storage.objects for insert with check (bucket_id = 'boutique-photos' and public.is_admin());

drop policy if exists "Admins can update boutique photos" on storage.objects;
create policy "Admins can update boutique photos"
  on storage.objects for update using (bucket_id = 'boutique-photos' and public.is_admin());

drop policy if exists "Admins can delete boutique photos" on storage.objects;
create policy "Admins can delete boutique photos"
  on storage.objects for delete using (bucket_id = 'boutique-photos' and public.is_admin());
