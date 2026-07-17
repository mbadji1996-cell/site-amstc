-- Phase 16 : Bibliothèque (livres et documents PDF visibles, non téléchargeables)
--
-- Réutilise le système généraliste "contenu réservé" (restricted_articles +
-- bucket Storage documents-reserves, cf. phase3b/phase3c) avec une nouvelle
-- valeur de catégorie. Aucun changement de RLS n'est nécessaire : la policy
-- de lecture existante sur restricted_articles et sur le bucket
-- documents-reserves (phase10, is_active_member()) s'applique déjà de façon
-- uniforme à toute valeur de category.

alter table public.restricted_articles
  drop constraint if exists restricted_articles_category_check;

alter table public.restricted_articles
  add constraint restricted_articles_category_check
  check (category in ('formation', 'actualite', 'document', 'bibliotheque'));
