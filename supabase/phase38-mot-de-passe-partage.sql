-- ============================================================
-- PHASE 38 — Liaison consultations : même mot de passe qu'amstc.org
--
-- Complète la phase 37. À la création de l'accès consultations d'un
-- membre, la fonction Edge provision-consultation-user recopie
-- l'EMPREINTE chiffrée (bcrypt) de son mot de passe amstc vers
-- l'instance consultations : le membre se connecte des deux côtés avec
-- le même e-mail et le même mot de passe, sans lien à transmettre.
-- (Le mot de passe en clair n'est jamais lu ni transmis - il n'existe
-- nulle part. Si le membre change ensuite son mot de passe d'un côté,
-- les deux divergent : la copie ne vaut qu'à la création.)
--
-- Cette fonction expose l'empreinte au SEUL service_role (celui de la
-- fonction Edge). Les révocations ci-dessous sont essentielles :
-- Postgres accorde par défaut EXECUTE à tout le monde sur une fonction.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create or replace function public.consultation_password_hash(target_user_id uuid)
returns text
language sql
security definer
set search_path = ''
as $$
  select u.encrypted_password
  from auth.users u
  where u.id = target_user_id;
$$;

revoke all on function public.consultation_password_hash(uuid) from public;
revoke all on function public.consultation_password_hash(uuid) from anon;
revoke all on function public.consultation_password_hash(uuid) from authenticated;
grant execute on function public.consultation_password_hash(uuid) to service_role;
