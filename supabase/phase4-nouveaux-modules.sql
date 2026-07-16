-- ============================================================
-- Phase 4 — Nouveaux modules de l'espace membre
-- Daara · Profil/Adhésion · Enseignements Médicaux + Quiz · Boutique
-- À exécuter dans Supabase : Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ============================================================
-- PHASE 4A — ESPACE DAARA
-- ============================================================

create table if not exists public.daara_courses (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  category      text not null check (category in ('islam', 'tarikha')),
  content       text,
  cover_image   text,
  duration_min  int default 0,
  order_index   int default 0,
  is_published  boolean default false,
  created_at    timestamptz default now()
);

create table if not exists public.daara_progress (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  course_id     uuid not null references public.daara_courses(id) on delete cascade,
  progress_pct  int default 0 check (progress_pct between 0 and 100),
  completed_at  timestamptz,
  updated_at    timestamptz default now(),
  unique(user_id, course_id)
);

alter table public.daara_courses enable row level security;
alter table public.daara_progress enable row level security;

drop policy if exists "Members can read published daara courses" on public.daara_courses;
create policy "Members can read published daara courses"
  on public.daara_courses for select
  using (is_published = true and public.is_approved_member());

drop policy if exists "Admins can manage daara courses" on public.daara_courses;
create policy "Admins can manage daara courses"
  on public.daara_courses for all
  using (public.is_admin());

drop policy if exists "Members can manage own daara progress" on public.daara_progress;
create policy "Members can manage own daara progress"
  on public.daara_progress for all
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can read daara progress" on public.daara_progress;
create policy "Admins can read daara progress"
  on public.daara_progress for select
  using (public.is_admin());


-- ============================================================
-- PHASE 4B — PROFIL ÉTENDU & ADHÉSION
-- ============================================================

alter table public.profiles add column if not exists specialty   text;
alter table public.profiles add column if not exists city        text;
alter table public.profiles add column if not exists phone       text;
alter table public.profiles add column if not exists member_since int;

create table if not exists public.membership_payments (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  year              int not null,
  amount_fcfa       int not null default 10000,
  payment_method    text check (payment_method in ('wave', 'orange_money', 'especes')),
  payment_reference text,
  status            text not null default 'pending'
                    check (status in ('pending', 'confirmed', 'rejected')),
  confirmed_by      uuid references auth.users(id),
  paid_at           timestamptz,
  created_at        timestamptz default now(),
  unique(user_id, year)
);

alter table public.membership_payments enable row level security;

drop policy if exists "Members can read own payments" on public.membership_payments;
create policy "Members can read own payments"
  on public.membership_payments for select
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Members can insert own payments" on public.membership_payments;
create policy "Members can insert own payments"
  on public.membership_payments for insert
  with check (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can manage all payments" on public.membership_payments;
create policy "Admins can manage all payments"
  on public.membership_payments for all
  using (public.is_admin());


-- ============================================================
-- PHASE 4C — ENSEIGNEMENTS MÉDICAUX + QUIZ
-- ============================================================

create table if not exists public.medical_lessons (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  category      text not null check (category in ('medecine', 'pharmacie', 'odonto', 'soins_infirmiers')),
  content       text,
  cover_image   text,
  order_index   int default 0,
  is_published  boolean default false,
  created_at    timestamptz default now()
);

create table if not exists public.quizzes (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  lesson_id     uuid references public.medical_lessons(id) on delete set null,
  category      text check (category in ('medecine', 'pharmacie', 'odonto', 'soins_infirmiers')),
  duration_min  int default 15,
  is_published  boolean default false,
  created_at    timestamptz default now()
);

create table if not exists public.quiz_questions (
  id              uuid primary key default gen_random_uuid(),
  quiz_id         uuid not null references public.quizzes(id) on delete cascade,
  question        text not null,
  options         jsonb not null,
  correct_index   int not null check (correct_index between 0 and 3),
  explanation     text,
  order_index     int default 0
);

create table if not exists public.quiz_attempts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  quiz_id     uuid not null references public.quizzes(id) on delete cascade,
  score       int not null,
  total       int not null,
  answers     jsonb,
  taken_at    timestamptz default now()
);

alter table public.medical_lessons enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_attempts enable row level security;

drop policy if exists "Members can read published lessons" on public.medical_lessons;
create policy "Members can read published lessons"
  on public.medical_lessons for select
  using (is_published = true and public.is_approved_member());

drop policy if exists "Admins can manage lessons" on public.medical_lessons;
create policy "Admins can manage lessons"
  on public.medical_lessons for all using (public.is_admin());

drop policy if exists "Members can read published quizzes" on public.quizzes;
create policy "Members can read published quizzes"
  on public.quizzes for select
  using (is_published = true and public.is_approved_member());

drop policy if exists "Admins can manage quizzes" on public.quizzes;
create policy "Admins can manage quizzes"
  on public.quizzes for all using (public.is_admin());

drop policy if exists "Members can read quiz questions" on public.quiz_questions;
create policy "Members can read quiz questions"
  on public.quiz_questions for select
  using (
    public.is_approved_member() and
    exists (select 1 from public.quizzes q where q.id = quiz_id and q.is_published = true)
  );

drop policy if exists "Admins can manage quiz questions" on public.quiz_questions;
create policy "Admins can manage quiz questions"
  on public.quiz_questions for all using (public.is_admin());

drop policy if exists "Members can manage own attempts" on public.quiz_attempts;
create policy "Members can manage own attempts"
  on public.quiz_attempts for all
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can read all attempts" on public.quiz_attempts;
create policy "Admins can read all attempts"
  on public.quiz_attempts for select using (public.is_admin());


-- ============================================================
-- PHASE 4D — BOUTIQUE
-- ============================================================

create table if not exists public.products (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  description   text,
  price_fcfa    int not null check (price_fcfa >= 0),
  image_url     text,
  category      text check (category in ('vetements', 'papeterie', 'materiel', 'accessoires')),
  stock         int not null default 0 check (stock >= 0),
  is_published  boolean default true,
  created_at    timestamptz default now()
);

create table if not exists public.orders (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete set null,
  status             text not null default 'pending'
                     check (status in ('pending', 'paid', 'processing', 'shipped', 'cancelled')),
  payment_method     text check (payment_method in ('wave', 'orange_money')),
  payment_reference  text,
  total_fcfa         int not null,
  items              jsonb not null,
  shipping_address   text,
  notes              text,
  created_at         timestamptz default now()
);

alter table public.products enable row level security;
alter table public.orders enable row level security;

drop policy if exists "Members can read published products" on public.products;
create policy "Members can read published products"
  on public.products for select
  using (is_published = true and public.is_approved_member());

drop policy if exists "Admins can manage products" on public.products;
create policy "Admins can manage products"
  on public.products for all using (public.is_admin());

drop policy if exists "Members can read own orders" on public.orders;
create policy "Members can read own orders"
  on public.orders for select
  using (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Members can create orders" on public.orders;
create policy "Members can create orders"
  on public.orders for insert
  with check (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can manage all orders" on public.orders;
create policy "Admins can manage all orders"
  on public.orders for all using (public.is_admin());
