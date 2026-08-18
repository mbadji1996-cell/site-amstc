-- ============================================================
-- PHASE 95 - « Réservé aux membres » depuis le CMS
--
-- LE BESOIN. Une réalisation ou une formation rédigée dans Decap peut
-- être marquée « réservée aux membres ». Sa VIGNETTE reste publique -
-- titre, résumé, image, et un cadenas qui donne envie de s'inscrire -
-- mais son CORPS n'est lisible que connecté, membre approuvé.
--
-- LE PROBLÈME QU'ON ÉVITE. Un fichier du dépôt est public : GitHub Pages
-- le sert à quiconque connaît l'adresse, quoi qu'en dise la page qui
-- l'affiche. Cacher le texte à l'écran ne suffirait pas ; il faut que le
-- texte réservé NE SOIT PAS dans le dépôt. Le workflow de construction
-- s'en charge : quand il rencontre un fichier « reserve: true » dont le
-- corps est encore là, il dépose ce corps ICI, en base, et réécrit le
-- fichier sans lui. La page publique lit alors la base, une fois le
-- membre connecté.
--
-- CE QUE CETTE PHASE APPORTE.
--   1. Une colonne « slug » sur restricted_articles : le lien entre la
--      ligne en base et le fichier du dépôt (« 2026-07-13-bienvenue… »).
--      Unique : un même fichier n'a qu'un corps.
--   2. deposer_contenu_reserve() : l'upsert appelé par le workflow, avec
--      la clé de service. Aucun membre ne peut l'appeler.
--   3. lire_contenu_reserve(slug) : ce que la page publique appelle une
--      fois le membre connecté ; renvoie le corps si le compte est
--      approuvé et actif, sinon null - la même barrière que le reste de
--      l'espace membres, is_approved_member().
--
-- Le champ « category » reprend les valeurs existantes : 'actualite'
-- pour une réalisation, 'formation' pour une formation.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

alter table public.restricted_articles
  add column if not exists slug text;

create unique index if not exists restricted_articles_slug_unique
  on public.restricted_articles (slug)
  where slug is not null;

-- ===== 1. Dépôt par le workflow (clé de service uniquement) =====
create or replace function public.deposer_contenu_reserve(
  p_slug      text,
  p_category  text,
  p_title     text,
  p_excerpt   text,
  p_image     text,
  p_content   text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_slug is null or btrim(p_slug) = '' then
    raise exception 'slug requis';
  end if;
  if p_category not in ('actualite', 'formation') then
    raise exception 'category doit être actualite ou formation (reçu : %)', p_category;
  end if;

  insert into public.restricted_articles (slug, category, title, excerpt, cover_image, content)
  values (btrim(p_slug), p_category, coalesce(nullif(btrim(p_title), ''), btrim(p_slug)),
          nullif(btrim(coalesce(p_excerpt, '')), ''), nullif(btrim(coalesce(p_image, '')), ''),
          coalesce(p_content, ''))
  on conflict (slug) where slug is not null do update
     set category    = excluded.category,
         title       = excluded.title,
         excerpt     = excluded.excerpt,
         cover_image = excluded.cover_image,
         content     = excluded.content
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.deposer_contenu_reserve(text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.deposer_contenu_reserve(text, text, text, text, text, text)
  to service_role;

-- ===== 2. Lecture par un membre connecté =====
-- Renvoie le corps, ou null si le compte n'est pas un membre approuvé et
-- actif. La page publique affiche alors l'invitation à se connecter ou à
-- attendre la validation, selon le cas.
create or replace function public.lire_contenu_reserve(p_slug text)
returns table (title text, content text, cover_image text)
language sql
stable
security definer
set search_path = public
as $$
  select r.title, r.content, r.cover_image
    from public.restricted_articles r
   where r.slug = btrim(p_slug)
     and public.is_approved_member()
   limit 1;
$$;

revoke all on function public.lire_contenu_reserve(text) from public, anon;
grant execute on function public.lire_contenu_reserve(text) to authenticated;

notify pgrst, 'reload schema';

-- ===== Contrôles =====
select column_name from information_schema.columns
 where table_name = 'restricted_articles' and column_name = 'slug';
select proname from pg_proc
 where proname in ('deposer_contenu_reserve', 'lire_contenu_reserve') order by proname;
select slug, category, title, length(content) as taille
  from public.restricted_articles where slug is not null order by created_at desc limit 10;

-- ===== 4. Pas de doublon dans les listes =====
-- Les pages publiques MÉLANGENT deux sources : l'index du dépôt (où une
-- fiche réservée du CMS figure déjà, avec son drapeau) et cette vue des
-- « aperçus réservés » créés en base. Un contenu venu du CMS a un slug ;
-- il ne doit pas être présenté une seconde fois par la vue. Constaté au
-- premier essai : l'article de test apparaissait deux fois.
create or replace view public.restricted_articles_teasers as
  select id, category, title, excerpt, cover_image, created_at
  from public.restricted_articles
  where slug is null;

grant select on public.restricted_articles_teasers to anon, authenticated;

-- Contrôle : la vue ne doit plus lister les fiches venues du CMS.
select count(*) as apercus_hors_cms from public.restricted_articles_teasers;

-- ===== 5. Nettoyer les lignes dont le fichier a disparu =====
-- Supprimer une fiche dans Decap ne supprime pas sa copie en base : elle
-- restait la, orpheline, et les listes qui lisent la table la montraient
-- encore. Le workflow appelle cette fonction avec la liste des slugs
-- ENCORE PRESENTS dans le depot ; tout slug de la base absent de la
-- liste est retire. Les lignes sans slug (documents officiels, anciens
-- contenus crees en base) ne sont jamais touchees.
create or replace function public.nettoyer_contenus_reserves(p_slugs_presents text[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  -- Garde-fou : une liste vide signifie presque toujours un depot mal lu,
  -- pas « il ne reste aucune fiche ». On refuse plutot que de tout effacer.
  if p_slugs_presents is null or array_length(p_slugs_presents, 1) is null then
    return 0;
  end if;
  delete from public.restricted_articles
   where slug is not null
     and not (slug = any(p_slugs_presents));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.nettoyer_contenus_reserves(text[]) from public, anon, authenticated;
grant execute on function public.nettoyer_contenus_reserves(text[]) to service_role;

notify pgrst, 'reload schema';
