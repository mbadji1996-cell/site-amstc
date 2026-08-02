-- ============================================================
-- PHASE 37 — Liaison des comptes vers la plateforme de consultations
--
-- Un membre soignant validé sur amstc.org peut recevoir, en un clic
-- depuis membres/validation.html, un compte sur la plateforme
-- consultations-amstc.org (instance Supabase distincte) : voir la
-- fonction Edge supabase/functions/provision-consultation-user.
--
-- Ces deux colonnes tracent la liaison côté espace membres :
--   - consultation_user_id : identifiant du compte créé sur l'instance
--     consultations (null = pas encore d'accès créé)
--   - consultation_linked_at : date de création de cet accès
--
-- Aucune règle RLS supplémentaire : ces colonnes suivent celles de
-- profiles (le membre peut les lire sur sa propre ligne, les admins
-- sur toutes). Seule la fonction Edge (service role) les écrit.
--
-- À exécuter une seule fois : Studio > SQL Editor > New query > Run.
-- Idempotent, sans danger.
-- ============================================================

alter table public.profiles
  add column if not exists consultation_user_id uuid;

alter table public.profiles
  add column if not exists consultation_linked_at timestamptz;
