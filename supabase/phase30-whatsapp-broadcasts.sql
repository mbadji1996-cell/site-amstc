-- ============================================================
-- PHASE 30 — Diffusion WhatsApp aux membres (déclenchement manuel admin)
--
-- Table de journal des diffusions envoyées via la fonction Edge
-- "notify-members-whatsapp" (Meta Cloud API). L'insertion se fait
-- UNIQUEMENT depuis la fonction Edge (clé service_role, qui contourne
-- RLS) - aucune policy INSERT n'est donc nécessaire ici. Seule la
-- lecture (historique, page membres/whatsapp-admin.html) passe par RLS.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après schema.sql, phase2-roles.sql).
-- ============================================================

create table if not exists public.whatsapp_broadcasts (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  sent_by uuid references public.profiles(id) on delete set null,
  sent_by_name text,
  recipients_count int not null default 0,
  success_count int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.whatsapp_broadcasts enable row level security;

drop policy if exists "Admins can view whatsapp broadcasts" on public.whatsapp_broadcasts;
create policy "Admins can view whatsapp broadcasts"
  on public.whatsapp_broadcasts for select
  using (public.is_admin());
