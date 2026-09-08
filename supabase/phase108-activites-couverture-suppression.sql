-- ============================================================
-- PHASE 108 - Activités : image de couverture, et suppression
--
-- DEUX AJOUTS À LA PHASE 106.
--
-- 1. UNE IMAGE DE COUVERTURE, comme en tête d'un Google Form. Elle
--    s'affiche sur la page PUBLIQUE, devant des visiteurs qui n'ont pas
--    de compte : le bucket est donc PUBLIC, à la différence de tous les
--    autres buckets du site. C'est assumé - une affiche d'activité est
--    faite pour être vue et partagée. L'écriture, elle, reste réservée
--    aux administrateurs.
--
-- 2. LA SUPPRESSION d'une activité. Les inscriptions tombent avec elle
--    (ON DELETE CASCADE, phase 106), et c'est voulu : garder des
--    inscriptions orphelines rattachées à une activité disparue ne
--    servirait personne. La fonction rend le nombre d'inscriptions
--    supprimées, pour que la page puisse le dire APRÈS coup - la
--    confirmation, elle, se fait avant, côté page, avec ce nombre.
--
-- L'IMAGE N'EST PAS SUPPRIMÉE ICI. Le fichier vit dans le Storage, que
-- SQL ne touche pas : c'est la page qui l'efface avant d'appeler cette
-- fonction, comme le fait déjà l'écran des annonces (phase 34).
--
-- PRÉREQUIS : phase 106.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

alter table public.activites add column if not exists image_path text;

-- Bucket PUBLIC : la couverture s'affiche pour des visiteurs sans
-- compte, et une URL signée ne tiendrait pas dans une page publique.
insert into storage.buckets (id, name, public)
values ('activite-couvertures', 'activite-couvertures', true)
on conflict (id) do update set public = true;

drop policy if exists "Admins can upload activite couvertures" on storage.objects;
create policy "Admins can upload activite couvertures"
  on storage.objects for insert
  with check (bucket_id = 'activite-couvertures' and public.is_admin());

drop policy if exists "Admins can update activite couvertures" on storage.objects;
create policy "Admins can update activite couvertures"
  on storage.objects for update
  using (bucket_id = 'activite-couvertures' and public.is_admin());

drop policy if exists "Admins can delete activite couvertures" on storage.objects;
create policy "Admins can delete activite couvertures"
  on storage.objects for delete
  using (bucket_id = 'activite-couvertures' and public.is_admin());

-- ===== L'enregistrement gagne un paramètre =====
-- Un paramètre de plus ne peut PAS passer par create or replace : il
-- créerait une seconde fonction et rendrait l'appel ambigu. On supprime
-- l'ancienne signature d'abord (même raison qu'en phase 66).
drop function if exists public.activite_enregistrer(
  uuid, text, text, text, date, int, int, date, jsonb, boolean);

create or replace function public.activite_enregistrer(
  p_id uuid,
  p_titre text,
  p_description text,
  p_lieu text,
  p_date_activite date,
  p_places int,
  p_places_non_membres int,
  p_date_limite date,
  p_questions jsonb,
  p_is_open boolean,
  p_image_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;
  if trim(coalesce(p_titre, '')) = '' then
    raise exception 'Le titre est obligatoire';
  end if;
  if p_places is not null and coalesce(p_places_non_membres, 0) > p_places then
    raise exception 'Les places réservées aux non-membres dépassent le total des places';
  end if;

  if p_id is null then
    insert into public.activites
      (titre, description, lieu, date_activite, places, places_non_membres,
       date_limite, questions, is_open, image_path, created_by)
    values
      (trim(p_titre), nullif(trim(coalesce(p_description, '')), ''),
       nullif(trim(coalesce(p_lieu, '')), ''), p_date_activite, p_places,
       coalesce(p_places_non_membres, 0), p_date_limite,
       coalesce(p_questions, '[]'::jsonb), coalesce(p_is_open, true),
       nullif(trim(coalesce(p_image_path, '')), ''), auth.uid())
    returning id into v_id;
  else
    update public.activites set
      titre = trim(p_titre),
      description = nullif(trim(coalesce(p_description, '')), ''),
      lieu = nullif(trim(coalesce(p_lieu, '')), ''),
      date_activite = p_date_activite,
      places = p_places,
      places_non_membres = coalesce(p_places_non_membres, 0),
      date_limite = p_date_limite,
      questions = coalesce(p_questions, '[]'::jsonb),
      is_open = coalesce(p_is_open, true),
      image_path = nullif(trim(coalesce(p_image_path, '')), '')
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Activité introuvable';
    end if;
  end if;

  return v_id;
end;
$$;

-- ===== La suppression =====
create or replace function public.activite_supprimer(p_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inscrits int;
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;

  select count(*)::int into v_inscrits
    from public.activite_inscriptions where activite_id = p_id;

  delete from public.activites where id = p_id;
  if not found then
    raise exception 'Activité introuvable';
  end if;

  return v_inscrits;
end;
$$;

revoke all on function public.activite_enregistrer(
  uuid, text, text, text, date, int, int, date, jsonb, boolean, text) from public, anon;
revoke all on function public.activite_supprimer(uuid) from public, anon;

grant execute on function public.activite_enregistrer(
  uuid, text, text, text, date, int, int, date, jsonb, boolean, text) to authenticated;
grant execute on function public.activite_supprimer(uuid) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - rien n'est supprimé, rien n'est créé
-- ============================================================
-- a) La colonne existe.
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'activites' and column_name = 'image_path';

-- b) Le bucket existe ET il est public - c'est ce « true » qui permet à
--    la page publique d'afficher la couverture sans compte.
select id, public from storage.buckets where id = 'activite-couvertures';

-- c) L'enregistrement a bien ONZE paramètres, et la suppression existe.
select p.proname, pg_get_function_identity_arguments(p.oid) as parametres
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('activite_enregistrer', 'activite_supprimer')
 order by p.proname;
