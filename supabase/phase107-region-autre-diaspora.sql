-- ============================================================
-- PHASE 107 - « Autre » dans les régions : les membres de la diaspora
--
-- LE BESOIN. La région est une liste fermée aux quatorze régions du
-- Sénégal (phase 66). Un membre installé à Lyon ne pouvait donc rien
-- choisir, et se retrouvait sans région - donc « sans région
-- identifiable » dans les statistiques, et avec une carte muette sur
-- l'endroit où il vit.
--
-- LA VALEUR AJOUTÉE EST « Autre », EN DERNIÈRE POSITION. Le membre la
-- choisit et écrit sa ville ET son pays dans la localité, restée libre :
-- « Lyon, France ». La carte imprimée n'affiche alors QUE la localité -
-- « Lyon, France » et non « Lyon, France, Autre » - ce qui se règle
-- côté page (assets/js/carte-membre.js), pas ici.
--
-- POURQUOI PAS UNE LISTE DE PAYS. Elle aurait fallu la deviner, la tenir
-- à jour, et elle aurait manqué le premier membre installé dans un pays
-- non prévu. « Autre » ne manque personne. Le prix est que les
-- statistiques regroupent toute la diaspora sous une seule ligne : si un
-- jour le détail par pays devient utile, il se fera en ouvrant la liste,
-- sans rien casser de ce qui est écrit ici.
--
-- LA LISTE ÉTAIT ÉCRITE TROIS FOIS - dans la contrainte, dans le
-- déclencheur d'inscription et dans la complétion de profil. Trois
-- copies veut dire trois occasions d'en oublier une : c'est exactement
-- ce qui serait arrivé ici, où ajouter « Autre » à la seule contrainte
-- aurait laissé l'inscription l'effacer en silence. Cette phase les
-- remplace par une fonction unique, region_valide().
--
-- PRÉREQUIS : phase 66.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. La liste, à un seul endroit désormais =====
-- IMMUTABLE : la contrainte CHECK ci-dessous l'exige, et la liste ne
-- dépend en effet que de son argument.
create or replace function public.region_valide(p_region text)
returns boolean
language sql
immutable
as $$
  select p_region is null or p_region in (
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
    'Thiès', 'Ziguinchor',
    -- Hors Sénégal. La localité porte alors la ville et le pays.
    'Autre'
  );
$$;

alter table public.profiles drop constraint if exists profiles_region_check;
alter table public.profiles add constraint profiles_region_check
  check (public.region_valide(region));

-- ===== 2. L'inscription =====
-- Reprend la version de la phase 66 sans y toucher, SAUF la liste, qui
-- passe par region_valide. Une région inattendue devient NULL plutôt que
-- de faire échouer l'insertion : une inscription vaut mieux qu'une
-- région, et le membre corrigera depuis son profil.
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

  if not public.region_valide(v_region) then
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

-- ===== 3. La complétion de profil =====
-- Même corps qu'en phase 66, à la seule exception de la validation de la
-- région. Ici l'erreur est LEVÉE et non silencieuse : l'usager est devant
-- son écran, il peut corriger.
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
  if not public.region_valide(p_region) then
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

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - rien n'est modifié
-- ============================================================
-- a) La fonction accepte les quatorze régions, « Autre » et NULL, et
--    refuse le reste. Les cinq lignes doivent être vraies.
select
  public.region_valide('Dakar')       as dakar_accepte,
  public.region_valide('Autre')       as autre_accepte,
  public.region_valide(null)          as null_accepte,
  not public.region_valide('Lyon')    as lyon_refuse,
  not public.region_valide('France')  as france_refuse;

-- b) La contrainte s'appuie bien sur la fonction.
select pg_get_constraintdef(oid) as contrainte
  from pg_constraint
 where conname = 'profiles_region_check';

-- c) Combien de membres sont aujourd'hui sans région : ce sont eux que
--    « Autre » va pouvoir servir, en plus des futurs inscrits.
select count(*) filter (where region is null) as sans_region,
       count(*) as total
  from public.profiles;
