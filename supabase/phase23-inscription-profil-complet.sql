-- Phase 23 : le formulaire d'inscription (membres/inscription.html) collecte
-- désormais tout le profil dès la création du compte (titre, prénom, nom,
-- domaine, spécialité, localité) au lieu de forcer chaque membre à repasser
-- par "Mon Profil & Adhésion" pour les renseigner après coup. Le trigger de
-- création automatique du profil (schema.sql, complété en Phase 22 pour le
-- téléphone) doit donc recopier ces nouveaux champs depuis raw_user_meta_data.
--
-- member_since n'est pas demandé au formulaire (un nouveau membre adhère
-- forcément l'année de son inscription) : on le fixe directement à l'année
-- en cours, comme le fait déjà l'affichage de secours de profil.html.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, phone,
    title, first_name, last_name, domain, domain_autre, specialty, city, member_since
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
    extract(year from now())::int
  );
  return new;
end;
$$;
