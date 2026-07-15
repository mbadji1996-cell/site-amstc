-- Espace Membres — Phase 3b : généraliser le contenu réservé
-- (Formation ET Réalisations, pas seulement Formation)
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- (à appliquer après supabase/phase3-restricted-formations.sql)

-- ===== Renomme la table et ajoute la catégorie =====
-- Les policies RLS existantes (liées à la table par identifiant interne,
-- pas par son nom) continuent de s'appliquer sans rien avoir à refaire.
alter table public.restricted_formations rename to restricted_articles;

alter table public.restricted_articles add column if not exists category text;
update public.restricted_articles set category = 'formation' where category is null;
alter table public.restricted_articles alter column category set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'restricted_articles_category_check'
  ) then
    alter table public.restricted_articles
      add constraint restricted_articles_category_check check (category in ('formation', 'actualite'));
  end if;
end $$;

-- ===== Aperçu public (teaser), avec la catégorie en plus =====
drop view if exists public.restricted_formations_teasers;
create or replace view public.restricted_articles_teasers as
  select id, category, title, excerpt, cover_image, created_at
  from public.restricted_articles;

grant select on public.restricted_articles_teasers to anon, authenticated;
