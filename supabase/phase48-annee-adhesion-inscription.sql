-- ============================================================
-- PHASE 48 - L'année d'adhésion se choisit à l'inscription.
--
-- Le formulaire d'inscription demande désormais l'année d'adhésion
-- (verrouillée à l'année en cours pour un nouvel adhérent, au choix
-- depuis 2014 pour un membre existant). Elle est transmise dans les
-- métadonnées du compte, et ce déclencheur la reporte sur le profil -
-- c'est elle qui détermine l'année du numéro de carte
-- (AMSTC-<année>-<n°>, voir phase47).
--
-- Jusqu'ici, handle_new_user (phase24) inscrivait d'office l'année en
-- cours pour tout le monde : un membre de 2016 recevait une carte
-- numérotée 2026 tant qu'un admin ne corrigeait pas son année.
--
-- Validation défensive : seule une année plausible (2014 à l'année en
-- cours) est acceptée ; toute autre valeur - absente, mal formée, hors
-- bornes, inscription via Google sans formulaire - retombe sur l'année
-- en cours, ajustable ensuite par l'admin ou via la demande de
-- changement validée (phase43).
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_annee_brute text := new.raw_user_meta_data ->> 'member_since';
  v_annee       int  := extract(year from now())::int;
begin
  if v_annee_brute ~ '^[0-9]{4}$'
     and v_annee_brute::int between 2014 and extract(year from now())::int then
    v_annee := v_annee_brute::int;
  end if;

  insert into public.profiles (
    id, email, full_name, phone,
    title, first_name, last_name, domain, domain_autre, specialty, city, member_since,
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
    v_annee,
    coalesce(new.raw_user_meta_data ->> 'applicant_type', 'membre_existant')
  );
  return new;
end;
$$;
