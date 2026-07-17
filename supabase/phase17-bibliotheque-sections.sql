-- Phase 17 : sections thématiques de la Bibliothèque
--
-- Ajoute une colonne de classement (bib_section) sur restricted_articles,
-- utilisée uniquement pour les entrées de catégorie 'bibliotheque'. Simple
-- colonne de classement d'affichage (pas un nouveau périmètre d'accès) :
-- aucun changement RLS, la lecture reste gouvernée par is_active_member()
-- comme le reste du contenu réservé (phase10).

alter table public.restricted_articles
  add column if not exists bib_section text;

alter table public.restricted_articles
  drop constraint if exists restricted_articles_bib_section_check;

alter table public.restricted_articles
  add constraint restricted_articles_bib_section_check
  check (
    bib_section is null
    or bib_section in (
      'islam', 'medecine', 'pharmacie', 'odontologie',
      'soins-infirmiers-obstetricaux', 'entrepreneuriat',
      'developpement-personnel', 'autres'
    )
  );
