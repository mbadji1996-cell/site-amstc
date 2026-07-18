-- Phase 24 : le formulaire d'inscription (membres/inscription.html) demande
-- désormais, avant le formulaire classique, si la personne est déjà membre
-- ("membre_existant") ou souhaite adhérer pour la première fois
-- ("nouvel_adherent"). Ce marquage permet à l'admin de repérer les nouveaux
-- adhérents dans validation.html et adhesion-admin.html, pour suivre leur
-- paiement des frais d'adhésion via le circuit déjà existant (Phase 7 :
-- card_validity_payments / confirm_card_validity_payment).
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run

alter table public.profiles add column if not exists applicant_type text default 'membre_existant';
alter table public.profiles drop constraint if exists profiles_applicant_type_check;
alter table public.profiles add constraint profiles_applicant_type_check
  check (applicant_type in ('membre_existant', 'nouvel_adherent'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
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
    extract(year from now())::int,
    coalesce(new.raw_user_meta_data ->> 'applicant_type', 'membre_existant')
  );
  return new;
end;
$$;
