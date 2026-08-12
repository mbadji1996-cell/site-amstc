-- ============================================================
-- PHASE 66 - La région rejoint la localité sur le profil.
--
-- La localité était un champ libre qui mélangeait tout : régions
-- (« Thiès »), communes (« Darou Salam »), quartiers (« Gueule Tapée »).
-- Les statistiques par ville en devenaient fausses, et la carte de membre
-- n'indiquait rien de localisable.
--
-- Désormais deux champs : la RÉGION, choisie parmi les quatorze régions
-- administratives du Sénégal (liste fermée), et la LOCALITÉ, saisie libre
-- (commune, quartier). La carte de membre affiche « Localité, Région » -
-- par exemple « Darou Salam, Thiès ».
--
-- La colonne est facultative : l'exiger enfermerait les 100+ profils
-- existants, tous sans région, sur l'écran de complétion. Elle est en
-- revanche demandée par les formulaires au moment où le membre enregistre.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. La colonne et sa liste fermée =====
alter table public.profiles add column if not exists region text;

alter table public.profiles drop constraint if exists profiles_region_check;
alter table public.profiles add constraint profiles_region_check
  check (region is null or region in (
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
    'Thiès', 'Ziguinchor'
  ));

-- Le membre modifie sa propre région comme sa localité (les grants de
-- colonnes sont cumulatifs : ceux de phase8 restent en place).
grant update (region) on public.profiles to authenticated;

-- ===== 2. L'inscription recopie la région =====
-- Reprend la version de phase48 (année d'adhésion bornée) en ajoutant la
-- région. Elle est validée ICI et non laissée à la contrainte : une valeur
-- inattendue dans les métadonnées ferait sinon échouer l'insertion, donc
-- l'inscription elle-même - une région douteuse doit devenir NULL, pas
-- bloquer la création du compte.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_annee_brute text := new.raw_user_meta_data ->> 'member_since';
  v_annee       int  := extract(year from now())::int;
  v_region      text := new.raw_user_meta_data ->> 'region';
begin
  if v_annee_brute ~ '^[0-9]{4}$'
     and v_annee_brute::int between 2014 and extract(year from now())::int then
    v_annee := v_annee_brute::int;
  end if;

  if v_region is not null and v_region not in (
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
    'Thiès', 'Ziguinchor'
  ) then
    v_region := null;
  end if;

  insert into public.profiles (
    id, email, full_name, phone,
    title, first_name, last_name, domain, domain_autre, specialty, city, region, member_since,
    applicant_type
  )
  values (
    new.id, new.email, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'title',
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    new.raw_user_meta_data ->> 'domain',
    new.raw_user_meta_data ->> 'domain_autre',
    new.raw_user_meta_data ->> 'specialty',
    new.raw_user_meta_data ->> 'city',
    v_region,
    v_annee,
    coalesce(new.raw_user_meta_data ->> 'applicant_type', 'membre_existant')
  );
  return new;
end;
$$;

-- ===== 3. L'écran de complétion transmet la région =====
-- Le type de retour et les paramètres changent : DROP obligatoire, un
-- CREATE OR REPLACE avec un paramètre de plus créerait une seconde
-- fonction et rendrait l'appel ambigu.
drop function if exists public.completer_mon_profil(text, text, text, text, text, text, text, text, int, text);

create or replace function public.completer_mon_profil(
  p_title         text,
  p_first_name    text,
  p_last_name     text,
  p_phone         text,
  p_domain        text,
  p_domain_autre  text,
  p_specialty     text,
  p_city          text,
  p_member_since  int,
  p_applicant_type text,
  p_region        text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_statut text;
begin
  select status into v_statut from public.profiles where id = auth.uid();
  if v_statut is null then
    raise exception 'Profil introuvable.';
  end if;

  if btrim(coalesce(p_first_name, '')) = '' or btrim(coalesce(p_last_name, '')) = '' then
    raise exception 'Le prénom et le nom sont obligatoires.';
  end if;
  if btrim(coalesce(p_phone, '')) = '' then
    raise exception 'Le téléphone est obligatoire.';
  end if;
  if btrim(coalesce(p_city, '')) = '' then
    raise exception 'La localité est obligatoire.';
  end if;
  if p_domain is null or p_domain not in
     ('medecine', 'pharmacie', 'odontologie', 'soins_infirmiers', 'soins_obstetricaux', 'autre') then
    raise exception 'Domaine invalide.';
  end if;
  if p_title is not null and p_title not in ('Dr', 'Pr', 'M.', 'Mme', 'Me') then
    raise exception 'Titre invalide.';
  end if;
  if p_applicant_type is not null and p_applicant_type not in ('membre_existant', 'nouvel_adherent') then
    raise exception 'Type d''inscription invalide.';
  end if;
  if p_region is not null and p_region not in (
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
    'Thiès', 'Ziguinchor'
  ) then
    raise exception 'Région invalide.';
  end if;

  update public.profiles
     set title          = p_title,
         first_name     = btrim(p_first_name),
         last_name      = btrim(p_last_name),
         full_name      = btrim(p_first_name) || ' ' || btrim(p_last_name),
         phone          = btrim(p_phone),
         domain         = p_domain,
         domain_autre   = case when p_domain = 'autre' then nullif(btrim(coalesce(p_domain_autre, '')), '') else null end,
         specialty      = nullif(btrim(coalesce(p_specialty, '')), ''),
         city           = btrim(p_city),
         region         = p_region,
         applicant_type = coalesce(p_applicant_type, applicant_type),
         member_since   = case
           when v_statut = 'pending'
                and p_member_since between 2014 and extract(year from now())::int
             then p_member_since
           else member_since
         end
   where id = auth.uid();
end;
$$;

revoke all on function public.completer_mon_profil(text, text, text, text, text, text, text, text, int, text, text) from public, anon;
grant execute on function public.completer_mon_profil(text, text, text, text, text, text, text, text, int, text, text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : la colonne, sa contrainte et les deux fonctions.
select column_name from information_schema.columns
 where table_name = 'profiles' and column_name = 'region'
union all
select proname from pg_proc
 where proname in ('handle_new_user', 'completer_mon_profil')
 order by 1;
