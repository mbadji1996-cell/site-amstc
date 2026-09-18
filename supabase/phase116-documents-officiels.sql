-- ============================================================
-- PHASE 116 - Documents officiels : classement et nombre de vues
--
-- POURQUOI. La page des documents officiels listait tout à la suite :
-- statuts, procès-verbaux, rapports, notes, dans un seul tas. Passé une
-- vingtaine de fiches, un membre ne retrouve plus ce qu'il cherche.
--
-- CE QUE FAIT CE SCRIPT.
--   1. Une colonne « sous_categorie » sur restricted_articles : rapports,
--      statuts, pv ou autres. Elle ne sert qu'aux documents ; les autres
--      contenus réservés la laissent vide.
--   2. Une colonne « vues » et une fonction pour l'incrémenter, comme au
--      forum : le compteur monte quand un membre ouvre le document, et
--      personne n'écrit ce nombre à la main.
--
-- APRÈS : la page affiche les tuiles de catégorie avec leur décompte et
-- le nombre de consultations. Tant que le script n'est pas passé, elle
-- fonctionne comme avant, sans tuiles ni vues.
-- ============================================================

-- ===== 1. Les colonnes =====
alter table public.restricted_articles
  add column if not exists sous_categorie text,
  add column if not exists vues           int not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'restricted_articles_sous_categorie_check') then
    alter table public.restricted_articles
      add constraint restricted_articles_sous_categorie_check
      check (sous_categorie is null or sous_categorie in ('rapports', 'statuts', 'pv', 'autres'));
  end if;
end $$;

comment on column public.restricted_articles.sous_categorie is
  'Documents officiels seulement : rapports, statuts, pv ou autres. Sert aux tuiles de classement.';
comment on column public.restricted_articles.vues is
  'Nombre d''ouvertures, incrémenté par document_compter_vue(). Jamais saisi à la main.';

-- ===== 2. Compter une consultation =====
-- SECURITY DEFINER : un membre approuvé n'a pas le droit d'écrire dans
-- restricted_articles, et ne doit pas l'avoir. La fonction n'augmente
-- qu'un compteur, d'une unité, sur une fiche existante.
create or replace function public.document_compter_vue(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_approved_member() then
    raise exception 'Accès réservé aux membres approuvés.';
  end if;
  update public.restricted_articles
     set vues = coalesce(vues, 0) + 1
   where id = p_id;
end;
$$;

revoke all on function public.document_compter_vue(uuid) from public, anon;
grant execute on function public.document_compter_vue(uuid) to authenticated;

notify pgrst, 'reload schema';

-- ===== 3. Contrôle =====
-- On n'APPELLE pas document_compter_vue ici : dans l'éditeur SQL personne
-- n'est connecté, le contrôle d'accès refuserait, et l'échec annulerait
-- tout le script.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'restricted_articles'
   and column_name in ('sous_categorie', 'vues')
 order by column_name;

select proname, pg_get_function_identity_arguments(oid) as arguments
  from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname = 'document_compter_vue';

select coalesce(sous_categorie, '(à classer)') as categorie, count(*) as documents
  from public.restricted_articles
 where category = 'document'
 group by 1
 order by documents desc;
