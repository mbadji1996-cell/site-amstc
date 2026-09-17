-- ============================================================
-- PHASE 110 - Un auteur pour les documents de la bibliothèque
--
-- POURQUOI. La fiche d'un livre porte un titre, un résumé, un dossier et
-- une couverture, mais pas d'auteur. Les membres cherchent pourtant un
-- ouvrage par son auteur autant que par son titre, et la bibliothèque
-- compte plusieurs dizaines de documents.
--
-- CE QUE FAIT CE SCRIPT.
--   1. Ajoute la colonne « auteur » à restricted_articles. Elle sert à la
--      bibliothèque ; les autres catégories (actualités, formations
--      réservées) peuvent la laisser vide.
--   2. Redéfinit bibliotheque_documents pour la renvoyer : sans cela la
--      page des membres ne la verrait pas, la fonction énumérant ses
--      colonnes de sortie une par une.
--
-- AVANT DE L'EXÉCUTER : rien à préparer. La colonne est facultative, les
-- documents déjà publiés restent en place, auteur à NULL.
--
-- APRÈS : le champ « Auteur » apparaît dans la fiche d'un document
-- (Administration > Bibliothèque) et la liste « Auteur » filtre la page
-- des membres. Tant que ce script n'est pas passé, la page fonctionne
-- comme avant et l'administration prévient que le champ manque en base.
-- ============================================================

-- ===== 1. La colonne =====
alter table public.restricted_articles
  add column if not exists auteur text;

comment on column public.restricted_articles.auteur is
  'Auteur de l''ouvrage (bibliothèque). Facultatif.';

-- ===== 2. La fonction de lecture des membres =====
-- Le type de retour change : il faut retirer la fonction avant de la
-- recréer (Postgres refuse un simple CREATE OR REPLACE dans ce cas).
drop function if exists public.bibliotheque_documents(int);

create or replace function public.bibliotheque_documents(p_limit int default 100)
returns table (
  id           uuid,
  title        text,
  excerpt      text,
  auteur       text,
  cover_image  text,
  file_path    text,
  bib_section  text,
  dossier_id   uuid,
  created_at   timestamptz
)
language plpgsql
as $$
begin
  perform public.check_rate_limit('bibliotheque_documents', 30, interval '5 minutes');
  -- Colonnes préfixées par l'alias ra : sans cela, elles entrent en conflit
  -- avec les colonnes de sortie du RETURNS TABLE, qui portent les mêmes noms
  -- ("column reference id is ambiguous" en plpgsql).
  return query
    select ra.id, ra.title, ra.excerpt, ra.auteur, ra.cover_image, ra.file_path,
           ra.bib_section, ra.dossier_id, ra.created_at
    from public.restricted_articles ra
    where ra.category = 'bibliotheque'
    order by ra.created_at desc
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

grant execute on function public.bibliotheque_documents(int) to authenticated;

notify pgrst, 'reload schema';

-- ===== 3. Contrôle =====
-- La colonne est là, et la fonction la renvoie.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'restricted_articles'
   and column_name = 'auteur';

select id, title, auteur
  from public.restricted_articles
 where category = 'bibliotheque'
 order by created_at desc
 limit 5;
