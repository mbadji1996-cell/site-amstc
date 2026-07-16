-- ============================================================
-- PHASE 8 — Un membre peut enfin modifier SA PROPRE ligne profiles
--
-- Bug corrigé : aucune policy RLS n'a jamais autorisé un membre approuvé à
-- modifier sa propre ligne dans `profiles` (la seule policy UPDATE de
-- schema.sql était réservée aux admins, et a été supprimée en Phase 2 au
-- profit des fonctions RPC dédiées : approve_or_reject_user, set_user_active,
-- set_user_role). Résultat : membres/profil.html appelait bien
-- `supabase.from('profiles').update(...)`, Supabase ne renvoyait AUCUNE
-- erreur (RLS filtre silencieusement les lignes non autorisées), mais rien
-- n'était réellement écrit en base — d'où la perte de la photo, du
-- téléphone, du domaine, de la spécialité, etc. au rechargement.
--
-- Correction : autoriser un membre à modifier SA PROPRE ligne, mais
-- UNIQUEMENT les colonnes d'auto-édition (jamais role/status/is_active/
-- card_valid_until/legacy_card_number, qui restent exclusivement gérées par
-- les fonctions RPC "security definer" déjà en place).
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- ============================================================

-- Retire tout octroi UPDATE large hérité par défaut sur ce rôle, pour ne
-- garder que les colonnes explicitement listées ci-dessous.
revoke update on public.profiles from authenticated;

grant update (
  title, first_name, last_name, full_name, phone,
  domain, domain_autre, specialty, member_since, city, photo_url
) on public.profiles to authenticated;

drop policy if exists "Members can update own profile" on public.profiles;
create policy "Members can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);
