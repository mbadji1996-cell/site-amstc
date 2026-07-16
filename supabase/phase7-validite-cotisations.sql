-- ============================================================
-- PHASE 7 — Validité de carte (1000 F/an) + Cotisations mensuelles (1000 F/mois)
-- Remplace l'ancien système d'adhésion annuelle unique (10 000 F/an).
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- (à appliquer après phase5-cartes-membres.sql)
-- ============================================================

-- ===== Validité de la carte =====
alter table public.profiles add column if not exists card_valid_until int;

create table if not exists public.card_validity_payments (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  years_requested   int not null check (years_requested >= 1),
  amount_fcfa       int not null,
  payment_method    text not null check (payment_method in ('wave', 'orange_money')),
  payment_reference text not null,
  status            text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  created_at        timestamptz not null default now(),
  confirmed_at      timestamptz
);

alter table public.card_validity_payments enable row level security;

drop policy if exists "Members can read own validity payments" on public.card_validity_payments;
create policy "Members can read own validity payments"
  on public.card_validity_payments for select
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Members can insert own validity payments" on public.card_validity_payments;
create policy "Members can insert own validity payments"
  on public.card_validity_payments for insert
  with check (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can manage validity payments" on public.card_validity_payments;
create policy "Admins can manage validity payments"
  on public.card_validity_payments for all
  using (public.is_admin());

-- Confirme un paiement de validité : étend card_valid_until de N années
-- (cumulatif depuis la validité actuelle, ou depuis l'an dernier si jamais fixée).
create or replace function public.confirm_card_validity_payment(payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_years   int;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select user_id, years_requested into v_user_id, v_years
  from public.card_validity_payments
  where id = payment_id and status = 'pending';

  if v_user_id is null then
    raise exception 'Paiement introuvable ou déjà traité.';
  end if;

  update public.card_validity_payments
     set status = 'confirmed', confirmed_at = now()
   where id = payment_id;

  update public.profiles
     set card_valid_until = coalesce(card_valid_until, extract(year from now())::int - 1) + v_years
   where id = v_user_id;
end;
$$;

-- Remplace confirm_member_card_claim (phase5) : l'admin doit désormais
-- indiquer l'année de fin de validité au moment de confirmer une carte.
create or replace function public.confirm_member_card_claim(card_id uuid, expiry_year int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed_by   uuid;
  v_card_number  text;
  v_member_since int;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if expiry_year is null then
    raise exception 'Année de fin de validité obligatoire.';
  end if;

  select claimed_by, card_number, member_since
    into v_claimed_by, v_card_number, v_member_since
  from public.member_cards
  where id = card_id and claim_status = 'pending';

  if v_claimed_by is null then
    raise exception 'Aucune réclamation en attente pour cette carte.';
  end if;

  update public.member_cards
     set claim_status = 'confirmed', confirmed_at = now()
   where id = card_id;

  update public.profiles
     set legacy_card_number = coalesce(v_card_number, legacy_card_number),
         member_since = coalesce(v_member_since, member_since),
         card_valid_until = expiry_year
   where id = v_claimed_by;
end;
$$;

-- ===== Cotisations mensuelles =====
create table if not exists public.cotisations (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  year        int not null,
  months_paid int[] not null default '{}',
  primary key (user_id, year)
);

alter table public.cotisations enable row level security;

drop policy if exists "Members can read own cotisations" on public.cotisations;
create policy "Members can read own cotisations"
  on public.cotisations for select
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can manage cotisations" on public.cotisations;
create policy "Admins can manage cotisations"
  on public.cotisations for all
  using (public.is_admin());

create table if not exists public.cotisation_payments (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  year              int not null,
  months_requested  int not null check (months_requested between 1 and 12),
  amount_fcfa       int not null,
  payment_method    text not null check (payment_method in ('wave', 'orange_money')),
  payment_reference text not null,
  status            text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  created_at        timestamptz not null default now(),
  confirmed_at      timestamptz
);

alter table public.cotisation_payments enable row level security;

drop policy if exists "Members can read own cotisation payments" on public.cotisation_payments;
create policy "Members can read own cotisation payments"
  on public.cotisation_payments for select
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Members can insert own cotisation payments" on public.cotisation_payments;
create policy "Members can insert own cotisation payments"
  on public.cotisation_payments for insert
  with check (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can manage cotisation payments" on public.cotisation_payments;
create policy "Admins can manage cotisation payments"
  on public.cotisation_payments for all
  using (public.is_admin());

-- Confirme un paiement de cotisations : remplit les N prochains mois non
-- payés de l'année concernée (dans l'ordre chronologique).
create or replace function public.confirm_cotisation_payment(payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_year    int;
  v_months  int;
  v_current int[];
  m         int;
  added     int := 0;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select user_id, year, months_requested into v_user_id, v_year, v_months
  from public.cotisation_payments
  where id = payment_id and status = 'pending';

  if v_user_id is null then
    raise exception 'Paiement introuvable ou déjà traité.';
  end if;

  select months_paid into v_current from public.cotisations where user_id = v_user_id and year = v_year;
  v_current := coalesce(v_current, '{}');

  m := 1;
  while added < v_months and m <= 12 loop
    if not (m = any(v_current)) then
      v_current := array_append(v_current, m);
      added := added + 1;
    end if;
    m := m + 1;
  end loop;

  insert into public.cotisations (user_id, year, months_paid)
  values (v_user_id, v_year, v_current)
  on conflict (user_id, year) do update set months_paid = excluded.months_paid;

  update public.cotisation_payments
     set status = 'confirmed', confirmed_at = now()
   where id = payment_id;
end;
$$;
