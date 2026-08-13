-- ============================================================
-- PHASE 73 - Dossiers de la bibliothèque, créés par l'administration
--
-- CE QUI EXISTAIT. Les documents étaient rangés dans huit sections
-- ÉCRITES EN DUR : dans une contrainte CHECK en base, dans la liste
-- déroulante de l'écran d'administration, et dans le rendu de l'écran
-- membre. Ajouter « Droit » ou « Santé publique » demandait de modifier
-- trois fichiers et d'exécuter un script - l'association ne pouvait rien
-- ranger sans passer par un développeur.
--
-- CE QUE FAIT CE SCRIPT. Une table de dossiers, que l'administration
-- crée, renomme et réordonne depuis l'écran. Chaque document pointe vers
-- un dossier.
--
-- LES HUIT SECTIONS EXISTANTES DEVIENNENT DES DOSSIERS, et les documents
-- déjà rangés y sont replacés : rien n'est perdu, rien n'est à reclasser
-- à la main. Seules les sections RÉELLEMENT UTILISÉES sont converties -
-- créer huit dossiers dont six vides donnerait un écran encombré dès le
-- premier jour.
--
-- La colonne bib_section est CONSERVÉE, sans plus être écrite : elle
-- garde la trace du rangement d'origine si la reprise devait être
-- rejouée ou vérifiée. Sa contrainte accepte déjà NULL, les nouveaux
-- documents ne la renseignent donc plus.
--
-- SUPPRIMER UN DOSSIER NE SUPPRIME AUCUN DOCUMENT : ceux qu'il contenait
-- se retrouvent « sans dossier » et restent consultables. Perdre un
-- classement est réparable, perdre un livre ne l'est pas.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. La table des dossiers =====
create table if not exists public.bibliotheque_dossiers (
  id         uuid primary key default gen_random_uuid(),
  nom        text not null,
  ordre      int  not null default 0,
  created_at timestamptz not null default now()
);

alter table public.bibliotheque_dossiers enable row level security;

-- Lecture : les mêmes membres que la bibliothèque elle-même. Un dossier
-- ne porte qu'un nom, mais afficher la liste à qui n'a pas accès aux
-- documents n'aurait aucun sens.
drop policy if exists "Membres voient les dossiers" on public.bibliotheque_dossiers;
create policy "Membres voient les dossiers"
  on public.bibliotheque_dossiers for select
  using (public.is_approved_member());

drop policy if exists "Admins creent les dossiers" on public.bibliotheque_dossiers;
create policy "Admins creent les dossiers"
  on public.bibliotheque_dossiers for insert
  with check (public.is_admin());

drop policy if exists "Admins modifient les dossiers" on public.bibliotheque_dossiers;
create policy "Admins modifient les dossiers"
  on public.bibliotheque_dossiers for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins suppriment les dossiers" on public.bibliotheque_dossiers;
create policy "Admins suppriment les dossiers"
  on public.bibliotheque_dossiers for delete
  using (public.is_admin());

grant select on public.bibliotheque_dossiers to authenticated;
grant insert, update, delete on public.bibliotheque_dossiers to authenticated;

-- Deux dossiers du même nom rendraient l'écran incompréhensible : on ne
-- saurait pas dans lequel on range. La casse et les espaces sont ignorés
-- pour que « Droit » et « droit  » ne coexistent pas.
create unique index if not exists bibliotheque_dossiers_nom_unique
  on public.bibliotheque_dossiers (lower(btrim(nom)));

-- ===== 2. Le lien depuis les documents =====
-- « on delete set null » : supprimer un dossier ne supprime aucun
-- document, il les remet simplement sans classement.
alter table public.restricted_articles
  add column if not exists dossier_id uuid
  references public.bibliotheque_dossiers(id) on delete set null;

create index if not exists restricted_articles_dossier_idx
  on public.restricted_articles (dossier_id);

-- ===== 3. Reprise : les sections utilisées deviennent des dossiers =====
do $$
declare
  v_libelles constant jsonb := jsonb_build_object(
    'islam', 'Islam',
    'medecine', 'Médecine',
    'pharmacie', 'Pharmacie',
    'odontologie', 'Odontologie',
    'soins-infirmiers-obstetricaux', 'Soins infirmiers et obstétricaux',
    'entrepreneuriat', 'Entrepreneuriat',
    'developpement-personnel', 'Développement personnel',
    'autres', 'Autres'
  );
  v_slug text;
  v_nom  text;
  v_id   uuid;
  v_rang int := 0;
begin
  -- L'ordre suit celui qu'affichait l'écran membre, pour que les membres
  -- retrouvent la bibliothèque telle qu'ils la connaissent.
  for v_slug in select unnest(array[
      'islam', 'medecine', 'pharmacie', 'odontologie',
      'soins-infirmiers-obstetricaux', 'entrepreneuriat',
      'developpement-personnel', 'autres'])
  loop
    -- Section jamais utilisée : on ne crée pas un dossier vide.
    if not exists (
      select 1 from public.restricted_articles
       where category = 'bibliotheque' and bib_section = v_slug
    ) then
      continue;
    end if;

    v_rang := v_rang + 10;
    v_nom := v_libelles ->> v_slug;

    select id into v_id
      from public.bibliotheque_dossiers
     where lower(btrim(nom)) = lower(btrim(v_nom));

    if v_id is null then
      insert into public.bibliotheque_dossiers (nom, ordre)
      values (v_nom, v_rang)
      returning id into v_id;
    end if;

    -- Seuls les documents ENCORE SANS DOSSIER sont replacés : rejouer le
    -- script ne défait pas un rangement fait entre-temps à la main.
    update public.restricted_articles
       set dossier_id = v_id
     where category = 'bibliotheque'
       and bib_section = v_slug
       and dossier_id is null;
  end loop;
end $$;

-- ===== 4. La liste des documents renvoie le dossier =====
-- Copie de la version de phase27, à la colonne dossier_id près. Le type
-- de retour change : DROP obligatoire.
--
-- Le limiteur de débit et la clause d'ordre sont repris tels quels : les
-- réécrire de mémoire aurait fait perdre l'un ou l'autre.
drop function if exists public.bibliotheque_documents(int);

create or replace function public.bibliotheque_documents(p_limit int default 100)
returns table (
  id           uuid,
  title        text,
  excerpt      text,
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
    select ra.id, ra.title, ra.excerpt, ra.cover_image, ra.file_path,
           ra.bib_section, ra.dossier_id, ra.created_at
    from public.restricted_articles ra
    where ra.category = 'bibliotheque'
    order by ra.created_at desc
    limit least(coalesce(p_limit, 100), 200);
end;
$$;

grant execute on function public.bibliotheque_documents(int) to authenticated;

notify pgrst, 'reload schema';

-- ===== 5. Contrôle : les dossiers et ce qu'ils contiennent =====
select d.ordre,
       d.nom,
       count(a.id) as documents
  from public.bibliotheque_dossiers d
  left join public.restricted_articles a
         on a.dossier_id = d.id and a.category = 'bibliotheque'
 group by d.id, d.ordre, d.nom
 union all
select 999,
       '(sans dossier)',
       count(*)
  from public.restricted_articles
 where category = 'bibliotheque' and dossier_id is null
 order by 1;
