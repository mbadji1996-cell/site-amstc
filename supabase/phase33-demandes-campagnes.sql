-- ============================================================
-- PHASE 33 — Demandes de campagne / activité locale (site public)
--
-- Formulaire public (demande-campagne.html) permettant à toute personne
-- (membre ou non, sans compte requis) de solliciter l'association pour
-- organiser une campagne ou une activité dans sa localité ou son daara.
-- Chaque demande déclenche un e-mail à l'admin (réutilise la fonction
-- Edge "notify-admin" déjà en place depuis la Phase 25) et apparaît dans
-- le tableau de bord admin (membres/demandes-campagnes-admin.html), où
-- elle peut être validée ou marquée "non retenue".
--
-- PRÉREQUIS : phase25-notifications-admin.sql doit déjà être appliqué
-- (fonction public.notify_admin + extension pg_net).
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après schema.sql, phase2-roles.sql, phase25).
-- ============================================================

create table if not exists public.campaign_requests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  email text,
  locality text not null,
  description text not null,
  status text not null default 'en_attente' check (status in ('en_attente', 'validee', 'non_retenue')),
  admin_notes text,
  handled_by uuid references public.profiles(id) on delete set null,
  handled_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.campaign_requests enable row level security;

-- ===== Soumission : ouverte à tous, sans compte (site public) =====
drop policy if exists "Anyone can submit a campaign request" on public.campaign_requests;
create policy "Anyone can submit a campaign request"
  on public.campaign_requests for insert
  to anon, authenticated
  with check (true);

-- ===== Lecture / traitement : admins uniquement =====
drop policy if exists "Admins can view campaign requests" on public.campaign_requests;
create policy "Admins can view campaign requests"
  on public.campaign_requests for select
  using (public.is_admin());

drop policy if exists "Admins can update campaign requests" on public.campaign_requests;
create policy "Admins can update campaign requests"
  on public.campaign_requests for update
  using (public.is_admin())
  with check (public.is_admin());

-- ===== Notification e-mail à l'admin (réutilise notify_admin, Phase 25) =====
create or replace function public.notify_admin_on_campaign_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_admin('demande_campagne', jsonb_build_object(
    'full_name', new.full_name,
    'phone', new.phone,
    'email', new.email,
    'locality', new.locality,
    'description', new.description
  ));
  return new;
end;
$$;

drop trigger if exists on_campaign_request_created_notify_admin on public.campaign_requests;
create trigger on_campaign_request_created_notify_admin
  after insert on public.campaign_requests
  for each row execute function public.notify_admin_on_campaign_request();
