-- ============================================================
-- Ajoute la catégorie "Soins infirmiers et obstétricales" aux
-- Enseignements Médicaux (leçons + quiz).
-- À exécuter dans l'éditeur SQL Supabase après phase4-nouveaux-modules.sql.
-- ============================================================

alter table public.medical_lessons drop constraint if exists medical_lessons_category_check;
alter table public.medical_lessons add constraint medical_lessons_category_check
  check (category in ('medecine', 'pharmacie', 'odonto', 'soins_infirmiers'));

alter table public.quizzes drop constraint if exists quizzes_category_check;
alter table public.quizzes add constraint quizzes_category_check
  check (category in ('medecine', 'pharmacie', 'odonto', 'soins_infirmiers'));
