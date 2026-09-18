-- ============================================================
-- PHASE 115 - Collectes : catégorie, visuel, objectif et avancement
--
-- POURQUOI. La page des collectes listait des titres et des montants.
-- Un membre qui arrive ne voit ni ce qui est recherché (alimentation,
-- vêtements, santé…), ni où en est la collecte. Deux informations qui
-- décident de la participation.
--
-- CE QUE FAIT CE SCRIPT.
--   1. Quatre colonnes sur collectes : catégorie, visuel, objectif
--      chiffré et objectif en toutes lettres (« 4 000 kg de riz »).
--   2. Une fonction d'AVANCEMENT. Les participations des autres membres
--      sont invisibles pour chacun - c'est voulu -, donc une page ne peut
--      pas calculer un total. La fonction renvoie UNIQUEMENT des sommes
--      par collecte : montant réuni, nombre de participants, dons en
--      nature promis. Aucun nom, aucun montant individuel.
--
-- APRÈS : la page des membres affiche les pastilles de catégorie, les
-- vignettes et une barre d'avancement. Tant que le script n'est pas
-- passé, elle fonctionne comme avant, sans barre ni pastille.
-- ============================================================

-- ===== 1. Les colonnes =====
alter table public.collectes
  add column if not exists categorie        text,
  add column if not exists image_url        text,
  add column if not exists objectif_fcfa    int,
  add column if not exists objectif_libelle text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'collectes_categorie_check') then
    alter table public.collectes
      add constraint collectes_categorie_check
      check (categorie is null or categorie in
        ('alimentation', 'vetements', 'sante', 'education', 'hygiene', 'materiel', 'autres'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'collectes_objectif_check') then
    alter table public.collectes
      add constraint collectes_objectif_check
      check (objectif_fcfa is null or objectif_fcfa > 0);
  end if;
end $$;

comment on column public.collectes.categorie is
  'alimentation, vetements, sante, education, hygiene, materiel ou autres. Sert aux pastilles de la page.';
comment on column public.collectes.image_url is
  'Vignette de la carte. Une adresse d''image déjà en ligne (assets/uploads…).';
comment on column public.collectes.objectif_fcfa is
  'Objectif chiffré, en FCFA. Renseigné, il affiche la barre d''avancement.';
comment on column public.collectes.objectif_libelle is
  'Objectif en toutes lettres, affiché sous la barre (ex. « 4 000 kg de riz »).';

-- ===== 2. L'avancement, en sommes seulement =====
-- SECURITY DEFINER : la fonction lit les participations de tous, mais ne
-- renvoie que des totaux. Rien ne permet d'y reconnaître quelqu'un.
create or replace function public.collectes_avancement()
returns table (
  collecte_id   uuid,
  montant_fcfa  bigint,
  participants  bigint,
  dons_nature   bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_approved_member() then
    raise exception 'Accès réservé aux membres approuvés.';
  end if;
  return query
    select p.collecte_id,
           coalesce(sum(p.montant_fcfa) filter (where p.status in ('confirmed', 'remis')), 0)::bigint,
           count(distinct p.user_id) filter (where p.status in ('confirmed', 'remis'))::bigint,
           count(*) filter (where p.mode = 'nature' and p.status in ('confirmed', 'remis'))::bigint
      from public.collecte_participations p
     group by p.collecte_id;
end;
$$;

grant execute on function public.collectes_avancement() to authenticated;

-- ===== 3. Renseigner ces champs depuis l'administration =====
-- Les collectes ne s'écrivent que par fonction (aucune politique UPDATE
-- directe) : il en faut donc une pour la vitrine.
create or replace function public.collecte_vitrine(
  p_id uuid, p_categorie text, p_image_url text,
  p_objectif_fcfa int, p_objectif_libelle text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  update public.collectes
     set categorie        = nullif(btrim(coalesce(p_categorie, '')), ''),
         image_url        = nullif(btrim(coalesce(p_image_url, '')), ''),
         objectif_fcfa    = p_objectif_fcfa,
         objectif_libelle = nullif(btrim(coalesce(p_objectif_libelle, '')), '')
   where id = p_id;
end;
$$;

grant execute on function public.collecte_vitrine(uuid, text, text, int, text) to authenticated;

notify pgrst, 'reload schema';

-- ===== 4. Contrôle =====
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'collectes'
   and column_name in ('categorie', 'image_url', 'objectif_fcfa', 'objectif_libelle')
 order by column_name;

-- Les deux fonctions sont bien en place.
-- On ne les APPELLE pas ici : dans l'éditeur SQL personne n'est connecté,
-- le contrôle d'accès refuserait, et l'échec annulerait tout le script.
select proname, pg_get_function_identity_arguments(oid) as arguments
  from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('collectes_avancement', 'collecte_vitrine')
 order by proname;

select c.titre, c.categorie, c.objectif_fcfa, c.objectif_libelle
  from public.collectes c
 order by c.created_at desc
 limit 10;
