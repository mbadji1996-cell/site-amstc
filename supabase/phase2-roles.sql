-- Espace Membres — Phase 2 : rôles Administrateur / Super Administrateur
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- (à appliquer après supabase/schema.sql, qui doit déjà être en place)

-- ===== Colonne d'activation =====
-- Distincte du statut d'approbation : permet de désactiver un compte déjà
-- approuvé (ex. un membre qui quitte l'association) sans toucher à son
-- historique d'inscription.
alter table public.profiles add column if not exists is_active boolean not null default true;

-- ===== Le compte connecté est-il Super Administrateur ? =====
create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin'
  );
$$;

-- ===== Mutations privilégiées (approbation, activation, rôles) =====
-- Ce sont désormais les SEULES façons de changer status / is_active / role :
-- la policy "Admins can update profiles" est supprimée plus bas, donc plus
-- aucune ligne de profiles ne peut être modifiée par une requête UPDATE
-- directe depuis le site. Chaque fonction vérifie elle-même les droits de
-- l'appelant, ce qui empêche par exemple un simple Administrateur de
-- s'auto-promouvoir Super Administrateur.

create or replace function public.approve_or_reject_user(target_user_id uuid, new_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if new_status not in ('pending', 'approved', 'rejected') then
    raise exception 'Statut invalide.';
  end if;
  update public.profiles set status = new_status where id = target_user_id;
end;
$$;

create or replace function public.set_user_active(target_user_id uuid, active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  update public.profiles set is_active = active where id = target_user_id;
end;
$$;

create or replace function public.set_user_role(target_user_id uuid, new_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Seul un Super Administrateur peut modifier les droits d''administration.';
  end if;
  if new_role not in ('user', 'admin', 'super_admin') then
    raise exception 'Rôle invalide.';
  end if;
  update public.profiles set role = new_role where id = target_user_id;
end;
$$;

-- ===== Retire la policy de modification directe =====
-- Toute modification de profiles passe maintenant par les fonctions
-- ci-dessus (exécutées en SECURITY DEFINER, donc toujours autorisées
-- malgré l'absence de policy UPDATE).
drop policy if exists "Admins can update profiles" on public.profiles;

-- ===== Étape manuelle : désigner le premier Super Administrateur =====
-- Le compte déjà promu "admin" en Phase 1 devient Super Administrateur
-- (remplacez l'e-mail) :
--
-- update public.profiles
--    set role = 'super_admin'
--  where email = 'votre-email@exemple.com';
