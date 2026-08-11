-- ============================================================
-- CONTRÔLE - Quels scripts SQL restent à exécuter ?
--
-- À coller dans Studio (instance amstc) > SQL Editor > Run. Ce script ne
-- MODIFIE rien : il interroge le catalogue de Postgres et répond, pour
-- chaque phase récente, « fait » ou « À EXÉCUTER ».
--
-- Ré-exécutable à volonté, y compris après chaque script passé, pour voir
-- la liste se vider.
-- ============================================================

with attendu(phase, fichier, ce_qui_est_verifie, present) as (
  values
    ('phase58', 'phase58-etat-cotisations-admin.sql',
     'fonction cotisations_membres',
     exists (select 1 from pg_proc where proname = 'cotisations_membres')),

    ('phase59', 'phase59-invitation-carte.sql',
     'fonction lire_invitation',
     exists (select 1 from pg_proc where proname = 'lire_invitation')),

    ('phase60', 'phase60-rappels-avec-chemin.sql',
     'texte_rappel_membre renvoie 3 colonnes (titre, corps, lien)',
     exists (select 1 from pg_proc
              where proname = 'texte_rappel_membre'
                and pronargs = 3
                and array_length(proallargtypes, 1) = 6)),

    ('phase61', 'phase61-acces-consultations-automatique.sql',
     'fonction provisionner_consultations',
     exists (select 1 from pg_proc where proname = 'provisionner_consultations')),

    ('phase62', 'phase62-telephone-membre.sql',
     'fonction set_member_phone',
     exists (select 1 from pg_proc where proname = 'set_member_phone')),

    ('phase63', 'phase63-annee-adhesion-libre.sql',
     'fonction set_own_member_since',
     exists (select 1 from pg_proc where proname = 'set_own_member_since')),

    -- 7 paramètres : le p_effacer_date ajouté par phase64. La version de
    -- phase55 n'en avait que 6.
    ('phase64', 'phase64-collecte-modification-partielle.sql',
     'modifier_collecte accepte p_effacer_date (7 paramètres)',
     exists (select 1 from pg_proc where proname = 'modifier_collecte' and pronargs = 7)),

    ('phase65', 'phase65-rappel-compte-active.sql',
     'texte_rappel_membre connaît le type compte_active et signe ©AMSTC',
     exists (select 1 from pg_proc
              where proname = 'texte_rappel_membre'
                and prosrc like '%compte_active%'
                and prosrc like '%©AMSTC%')),

    ('cours',   'cours-daara-tawadu.sql',
     'cours Al-Tawadu'' présent dans daara_courses',
     exists (select 1 from public.daara_courses where title like 'Al-Tawadu%'))
)
select phase,
       case when present then 'fait' else '>>> À EXÉCUTER <<<' end as etat,
       fichier,
       ce_qui_est_verifie
  from attendu
 order by present, phase;
