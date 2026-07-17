-- Phase 21 : corrige "Could not find the 'duration_min' column of
-- 'medical_lessons' in the schema cache" dans medical-admin.html.
--
-- medical_lessons n'a jamais eu de colonne duration_min, contrairement à
-- ses tables soeurs daara_courses et quizzes (phase4-nouveaux-modules.sql)
-- qui l'ont dès leur création — un oubli lors de la création de la table,
-- alors que le formulaire "Durée de lecture (min)" l'a toujours utilisée.

alter table public.medical_lessons add column if not exists duration_min int default 0;
