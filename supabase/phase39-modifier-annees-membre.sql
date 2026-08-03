-- ============================================================
-- PHASE 39 — Corriger « permission denied for table profiles » sur
-- l'enregistrement de l'année d'adhésion / fin de validité de carte.
--
-- Cause : membres/validation.html (saveMemberYears) modifiait la table
-- profiles directement (supabaseClient.from('profiles').update(...)),
-- au lieu de passer par une fonction RPC comme tous les autres écrans
-- d'administration (assign_member_card, set_user_active, set_user_role,
-- approve_or_reject_user...). Sur cette instance, le rôle authenticated
-- n'a jamais reçu de droit UPDATE explicite sur profiles - seule la
-- policy RLS existe (phase1). Une fonction SECURITY DEFINER contourne
-- ce problème, comme partout ailleurs dans ce projet.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run.
-- ============================================================

create or replace function public.set_member_years(
  member_id uuid,
  new_member_since int,
  new_card_valid_until int
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

  update public.profiles
     set member_since = new_member_since,
         card_valid_until = new_card_valid_until
   where id = member_id;
end;
$$;
