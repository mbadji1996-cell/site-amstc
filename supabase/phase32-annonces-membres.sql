-- ============================================================
-- PHASE 32 — Annonces de l'espace membres (créées par l'admin, épinglées
-- pour être vues à chaque connexion).
--
-- Table simple gérée entièrement par l'admin (membres/annonces-admin.html).
-- Jusqu'à 3 annonces peuvent être épinglées (is_pinned) en même temps ; le
-- tableau de bord membre (membres/index.html) affiche une fenêtre modale
-- listant les annonces épinglées actives à chaque chargement de la page,
-- pour qu'un membre ne puisse pas les manquer.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après schema.sql, phase2-roles.sql).
-- ============================================================

create table if not exists public.member_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  is_pinned boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.member_announcements enable row level security;

-- ===== Lecture : tout membre approuvé voit les annonces actives =====
drop policy if exists "Members can view active announcements" on public.member_announcements;
create policy "Members can view active announcements"
  on public.member_announcements for select
  using (is_active = true and public.is_approved_member());

-- ===== Gestion (création / modification / suppression) : admins =====
drop policy if exists "Admins can view all announcements" on public.member_announcements;
create policy "Admins can view all announcements"
  on public.member_announcements for select
  using (public.is_admin());

drop policy if exists "Admins can insert announcements" on public.member_announcements;
create policy "Admins can insert announcements"
  on public.member_announcements for insert
  with check (public.is_admin());

drop policy if exists "Admins can update announcements" on public.member_announcements;
create policy "Admins can update announcements"
  on public.member_announcements for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins can delete announcements" on public.member_announcements;
create policy "Admins can delete announcements"
  on public.member_announcements for delete
  using (public.is_admin());

-- ===== Limite technique : 3 annonces épinglées maximum =====
-- Empêche d'épingler une 4e annonce (l'admin doit d'abord en désépingler
-- une) plutôt que de la refuser silencieusement côté interface seulement.
create or replace function public.check_max_pinned_announcements()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pinned_count int;
begin
  if new.is_pinned then
    select count(*) into v_pinned_count
    from public.member_announcements
    where is_pinned = true and id is distinct from new.id;
    if v_pinned_count >= 3 then
      raise exception 'Impossible d''épingler plus de 3 annonces à la fois. Désépinglez-en une d''abord.';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists on_announcement_pin_check on public.member_announcements;
create trigger on_announcement_pin_check
  before insert or update on public.member_announcements
  for each row execute function public.check_max_pinned_announcements();
