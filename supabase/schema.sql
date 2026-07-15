-- Espace Membres — schéma Phase 1
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run

-- ===== Table des profils =====
-- Complète auth.users (géré nativement par Supabase) avec le statut de
-- validation et le rôle. Le rôle n'a qu'une seule valeur utile en Phase 1
-- ('user') mais la colonne existe déjà pour la Phase 2 (admin/super_admin).
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role text not null default 'user',
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- ===== Création automatique du profil à l'inscription =====
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ===== Fonction utilitaire : le compte connecté est-il admin ? =====
-- SECURITY DEFINER pour éviter la récursion RLS (une policy sur profiles
-- qui interrogerait profiles directement se bloquerait elle-même).
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'super_admin')
  );
$$;

-- ===== Règles d'accès (RLS) =====
-- Un utilisateur voit uniquement sa propre ligne...
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- ...sauf un admin, qui voit tout le monde (pour la page de validation)
drop policy if exists "Admins can view all profiles" on public.profiles;
create policy "Admins can view all profiles"
  on public.profiles for select
  using (public.is_admin());

-- Seul un admin peut modifier une ligne (approuver / refuser un compte)
drop policy if exists "Admins can update profiles" on public.profiles;
create policy "Admins can update profiles"
  on public.profiles for update
  using (public.is_admin())
  with check (public.is_admin());

-- Aucune policy INSERT : la seule façon de créer une ligne est le trigger
-- ci-dessus (exécuté en SECURITY DEFINER), donc impossible de fabriquer un
-- profil directement depuis le site.

-- ===== Étape manuelle : désigner le premier administrateur =====
-- 1. Créez votre propre compte via membres/inscription.html
-- 2. Puis exécutez (en remplaçant l'e-mail) :
--
-- update public.profiles
--    set role = 'admin', status = 'approved'
--  where email = 'votre-email@exemple.com';
