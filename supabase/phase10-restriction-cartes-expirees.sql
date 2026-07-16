-- ============================================================
-- PHASE 10 — Restriction d'accès aux contenus réservés pour les cartes
-- expirées depuis plus de 2 mois.
--
-- Convention : `profiles.card_valid_until` est une année (int). Une carte
-- valable jusqu'en année N est considérée expirée à partir du 1er janvier
-- N+1. Le délai de grâce de 2 mois se termine le 1er mars N+1 : c'est à
-- partir de cette date que l'accès aux contenus réservés est coupé.
--
-- Portée volontairement limitée au système "contenu réservé" généraliste
-- (restricted_articles + bucket documents-reserves) : Daara, Médical/Quiz,
-- Boutique et cotisations restent gérés par is_approved_member(), inchangée.
--
-- Interrupteur global : la règle ne s'applique que si
-- app_settings.restriction_cartes_active vaut true. Tant qu'il est à
-- false (valeur par défaut), le contenu réservé reste accessible à tout
-- membre approuvé quelle que soit la validité de sa carte — le temps de
-- mener une campagne de renouvellement — mais le rappel visuel (bandeau
-- "carte expirée") continue de s'afficher dès que la carte est expirée,
-- pour préparer les membres avant l'activation de la coupure.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase3, phase3b, phase3c, phase7).
-- ============================================================

create table if not exists public.app_settings (
  id boolean primary key default true,
  restriction_cartes_active boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  constraint app_settings_singleton check (id)
);

insert into public.app_settings (id) values (true) on conflict (id) do nothing;

alter table public.app_settings enable row level security;

-- Tout compte connecté peut lire l'état de l'interrupteur (nécessaire pour
-- afficher le bon bandeau côté membre) ; seuls les admins peuvent le changer.
drop policy if exists "Authenticated can read app settings" on public.app_settings;
create policy "Authenticated can read app settings"
  on public.app_settings for select
  using (auth.uid() is not null);

drop policy if exists "Admins can update app settings" on public.app_settings;
create policy "Admins can update app settings"
  on public.app_settings for update
  using (public.is_admin())
  with check (public.is_admin());

create or replace function public.is_active_member()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved' and is_active
      and (
        not coalesce((select restriction_cartes_active from public.app_settings limit 1), false)
        or card_valid_until is null
        or now() < make_date(card_valid_until + 1, 3, 1)
      )
  );
$$;

-- Remplace la policy SELECT sur restricted_articles. Créée à l'origine sous
-- l'ancien nom de table restricted_formations (phase3) ; toujours active
-- après le rename en restricted_articles (phase3b), les policies RLS
-- suivant l'OID de la table et non son nom.
drop policy if exists "Members can view restricted formations" on public.restricted_articles;
create policy "Members can view restricted formations"
  on public.restricted_articles for select
  using (public.is_active_member());

-- Remplace la policy de lecture du bucket documents-reserves (phase3c).
drop policy if exists "Members can read reserved documents" on storage.objects;
create policy "Members can read reserved documents"
  on storage.objects for select
  using (bucket_id = 'documents-reserves' and public.is_active_member());
