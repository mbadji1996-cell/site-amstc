-- Phase 22 : le formulaire d'inscription (membres/inscription.html) demande
-- désormais le numéro de téléphone (WhatsApp), mais le trigger de création
-- automatique du profil (schema.sql, Phase 1) ne recopiait que le nom
-- complet depuis raw_user_meta_data — le téléphone était donc perdu à la
-- création du compte (colonne profiles.phone déjà existante, cf.
-- phase4-nouveaux-modules.sql, éditable ensuite via profil.html).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'phone');
  return new;
end;
$$;
