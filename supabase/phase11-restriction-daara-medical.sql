-- ============================================================
-- PHASE 11 — Étend la restriction "carte expirée depuis 2 mois" (Phase 10)
-- à l'Espace Daara et aux Enseignements Médicaux + Quiz.
--
-- La page "Formations" (membres/formations.html) regroupe désormais trois
-- modules : Espace Daara, Enseignements Médicaux, et les formations/
-- réalisations "Autres" (restricted_articles, déjà couvertes en Phase 10).
-- Ce script couvre les deux modules restants avec la même règle
-- (is_active_member() au lieu de is_approved_member()), pilotée par le
-- même interrupteur global app_settings.restriction_cartes_active.
--
-- La Boutique et les paiements (adhésion/cotisations) restent inchangés,
-- gérés par is_approved_member() : la demande ne portait que sur les
-- formations.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase4-nouveaux-modules.sql et phase10).
-- ============================================================

-- ===== Espace Daara =====

drop policy if exists "Members can read published daara courses" on public.daara_courses;
create policy "Members can read published daara courses"
  on public.daara_courses for select
  using (is_published = true and public.is_active_member());

drop policy if exists "Members can manage own daara progress" on public.daara_progress;
create policy "Members can manage own daara progress"
  on public.daara_progress for all
  using (auth.uid() = user_id and public.is_active_member());

-- ===== Enseignements Médicaux + Quiz =====

drop policy if exists "Members can read published lessons" on public.medical_lessons;
create policy "Members can read published lessons"
  on public.medical_lessons for select
  using (is_published = true and public.is_active_member());

drop policy if exists "Members can read published quizzes" on public.quizzes;
create policy "Members can read published quizzes"
  on public.quizzes for select
  using (is_published = true and public.is_active_member());

drop policy if exists "Members can read quiz questions" on public.quiz_questions;
create policy "Members can read quiz questions"
  on public.quiz_questions for select
  using (
    public.is_active_member() and
    exists (select 1 from public.quizzes q where q.id = quiz_id and q.is_published = true)
  );

drop policy if exists "Members can manage own attempts" on public.quiz_attempts;
create policy "Members can manage own attempts"
  on public.quiz_attempts for all
  using (auth.uid() = user_id and public.is_active_member());
