-- ============================================================
-- PHASE 53 - Auteur d'un cours
--
-- Les cours du Daara et les enseignements médicaux sont rédigés par des
-- personnes identifiées : leur nom doit apparaître, à la fois par respect
-- du travail fourni et parce qu'il fait partie de la valeur du contenu
-- pour le membre qui le lit.
--
-- Champ libre plutôt que lien vers un compte : la plupart des auteurs
-- (enseignants, conférenciers invités) n'ont pas de compte sur l'espace
-- membres, et on veut pouvoir écrire « Demba Tahirou DIOP » ou
-- « Dr Codou NDIAYE, pharmacienne » sans contrainte.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

alter table public.daara_courses   add column if not exists author text;
alter table public.medical_lessons add column if not exists author text;

-- Les deux cours du Gamou 1448H déjà importés (voir
-- supabase/cours-daara-gamou-1448h.sql), dont l'auteur figurait jusqu'ici
-- dans le seul PDF d'origine.
update public.daara_courses
   set author = 'Demba Tahirou DIOP'
 where title like 'Al-Amîn%' or title like 'Al-Haya%';

-- published_medical_lessons renvoie « setof public.medical_lessons » : la
-- nouvelle colonne y passe d'elle-même, aucune fonction à recréer. En
-- revanche PostgREST garde son schéma en mémoire, et servirait l'ancienne
-- définition jusqu'à son prochain redémarrage - d'où ce rechargement.
notify pgrst, 'reload schema';

-- Contrôle.
select title, author, category, is_published
  from public.daara_courses
 order by order_index;
