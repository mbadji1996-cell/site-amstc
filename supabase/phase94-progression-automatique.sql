-- ============================================================
-- PHASE 94 - La progression des cours se mesure toute seule
--
-- LE CONSTAT. Sur les cours du Daara, la progression était un curseur
-- que le membre déplaçait lui-même puis « sauvegardait ». Personne ne
-- le faisait : les cours restaient à 0 %. Sur les enseignements
-- médicaux, rien n'était enregistré du tout ; la barre du haut suivait
-- le défilement et repartait de zéro à chaque visite.
--
-- CE QUI CHANGE. La page mesure elle-même ce qui a été LU : le cours est
-- découpé en sections (ses titres), une section compte comme lue quand
-- elle a été visible à l'écran quelques secondes, et l'on enregistre où
-- le lecteur en est. À la visite suivante, un bandeau propose de
-- reprendre à la dernière section lue. Sur les enseignements médicaux,
-- réussir le quiz de la leçon (60 %) la marque terminée : la lecture
-- vaut jusqu'à 80 %, le quiz les 20 derniers.
--
-- CÔTÉ BASE, deux choses :
--   1. la table de progression des LEÇONS MÉDICALES, qui n'existait pas,
--      calquée sur celle du Daara ;
--   2. sur les deux, une colonne « derniere_section » (le titre de la
--      dernière section lue, pour la reprise) et « sections_lues » (le
--      nombre, pour recalculer le pourcentage si le cours change).
--
-- Rien n'est retiré : progress_pct et completed_at gardent leur sens, et
-- le bouton « Marquer comme terminé » les remplit toujours.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Le Daara : les deux colonnes de plus =====
alter table public.daara_progress
  add column if not exists derniere_section text,
  add column if not exists sections_lues   int default 0;

-- ===== 2. Les leçons médicales : la table, sur le modèle du Daara =====
create table if not exists public.medical_progress (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  lesson_id        uuid not null references public.medical_lessons(id) on delete cascade,
  progress_pct     int default 0 check (progress_pct between 0 and 100),
  derniere_section text,
  sections_lues    int default 0,
  quiz_reussi      boolean default false,
  completed_at     timestamptz,
  updated_at       timestamptz default now(),
  unique(user_id, lesson_id)
);

alter table public.medical_progress enable row level security;

drop policy if exists "Members can manage own medical progress" on public.medical_progress;
create policy "Members can manage own medical progress"
  on public.medical_progress for all
  using (auth.uid() = user_id and public.is_approved_member())
  with check (auth.uid() = user_id and public.is_approved_member());

drop policy if exists "Admins can read medical progress" on public.medical_progress;
create policy "Admins can read medical progress"
  on public.medical_progress for select
  using (public.is_admin());

-- ===== 3. Le quiz réussi valide la leçon =====
-- Déclencheur sur les tentatives : une réussite (60 % ou plus) marque
-- quiz_reussi sur la progression de la leçon liée, et pousse le
-- pourcentage à 100 si la lecture était déjà à 80. Le membre n'a rien à
-- faire ; c'est le résultat qui compte.
create or replace function public.quiz_valide_lecon()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson uuid;
begin
  if new.total is null or new.total = 0 then return new; end if;
  if (new.score::numeric / new.total) < 0.6 then return new; end if;

  select lesson_id into v_lesson from public.quizzes where id = new.quiz_id;
  if v_lesson is null then return new; end if;

  insert into public.medical_progress (user_id, lesson_id, quiz_reussi, progress_pct, updated_at)
  values (new.user_id, v_lesson, true, 20, now())
  on conflict (user_id, lesson_id) do update
     set quiz_reussi  = true,
         -- La lecture donne jusqu'à 80 ; le quiz complète. Si le membre a
         -- tout lu, il passe à 100 ; sinon il garde ses 20 points d'avance.
         progress_pct = least(100, greatest(public.medical_progress.progress_pct, 0) + 20),
         completed_at = case when least(100, greatest(public.medical_progress.progress_pct, 0) + 20) >= 100
                             then coalesce(public.medical_progress.completed_at, now())
                             else public.medical_progress.completed_at end,
         updated_at   = now();
  return new;
end;
$$;

drop trigger if exists quiz_attempts_valide_lecon on public.quiz_attempts;
create trigger quiz_attempts_valide_lecon
  after insert on public.quiz_attempts
  for each row execute function public.quiz_valide_lecon();

notify pgrst, 'reload schema';

-- ===== 4. Contrôles =====
select column_name from information_schema.columns
 where table_name = 'daara_progress' and column_name in ('derniere_section', 'sections_lues');
select column_name from information_schema.columns
 where table_name = 'medical_progress' order by ordinal_position;
select tgname from pg_trigger where tgname = 'quiz_attempts_valide_lecon';
