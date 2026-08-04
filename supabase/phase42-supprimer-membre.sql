-- ============================================================
-- PHASE 42 — Suppression d'un compte membre, réservée au Super
-- Administrateur.
--
-- Jusqu'ici, un compte pouvait seulement être désactivé. Cette phase
-- ajoute la suppression définitive, et prépare le schéma pour qu'elle se
-- déroule proprement :
--
--   1. Trois clés étrangères sans clause de suppression AURAIENT FAIT
--      ÉCHOUER l'opération (erreur de clé étrangère) dès que le membre
--      avait créé un album de médiathèque, une formation réservée, ou
--      modifié le réglage global des cartes. Elles passent en SET NULL :
--      le contenu de l'association survit à son auteur.
--
--   2. Cinq colonnes étaient en CASCADE : supprimer un membre aurait
--      effacé ses cotisations, ses paiements et ses messages du forum.
--      Choix retenu par le bureau : conserver cet historique (traçabilité
--      comptable), donc SET NULL + suppression du NOT NULL, comme cela
--      avait déjà été fait pour orders en phase35.
--
-- Ce qui est conservé après suppression : cotisations, paiements,
-- commandes boutique, messages du forum (sans auteur), albums et contenus
-- créés. Ce qui change : la carte de membre redevient « non attribuée »
-- et peut être réattribuée.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

-- ===== 1. Débloquer les contraintes qui empêchaient la suppression =====

alter table public.app_settings
  drop constraint if exists app_settings_updated_by_fkey;
alter table public.app_settings
  add constraint app_settings_updated_by_fkey
  foreign key (updated_by) references public.profiles(id) on delete set null;

alter table public.media_folders
  drop constraint if exists media_folders_created_by_fkey;
alter table public.media_folders
  add constraint media_folders_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete set null;

-- Table renommée en restricted_articles (phase3b) : la contrainte a gardé
-- son nom d'origine, issu de restricted_formations.
alter table public.restricted_articles
  drop constraint if exists restricted_formations_created_by_fkey;
alter table public.restricted_articles
  drop constraint if exists restricted_articles_created_by_fkey;
alter table public.restricted_articles
  add constraint restricted_articles_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete set null;

-- ===== 2. Conserver l'historique plutôt que de le supprimer en cascade =====

alter table public.cotisations alter column user_id drop not null;
alter table public.cotisations drop constraint if exists cotisations_user_id_fkey;
alter table public.cotisations
  add constraint cotisations_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;

alter table public.cotisation_payments alter column user_id drop not null;
alter table public.cotisation_payments drop constraint if exists cotisation_payments_user_id_fkey;
alter table public.cotisation_payments
  add constraint cotisation_payments_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;

alter table public.card_validity_payments alter column user_id drop not null;
alter table public.card_validity_payments drop constraint if exists card_validity_payments_user_id_fkey;
alter table public.card_validity_payments
  add constraint card_validity_payments_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;

alter table public.forum_topics alter column author_id drop not null;
alter table public.forum_topics drop constraint if exists forum_topics_author_id_fkey;
alter table public.forum_topics
  add constraint forum_topics_author_id_fkey
  foreign key (author_id) references public.profiles(id) on delete set null;

alter table public.forum_replies alter column author_id drop not null;
alter table public.forum_replies drop constraint if exists forum_replies_author_id_fkey;
alter table public.forum_replies
  add constraint forum_replies_author_id_fkey
  foreign key (author_id) references public.profiles(id) on delete set null;

-- ===== 3. La suppression elle-même =====
-- Supprime la ligne auth.users : profiles est effacée en cascade, et tout
-- ce qui précède bascule en SET NULL. SECURITY DEFINER car auth.users
-- n'est pas accessible au rôle authenticated.
create or replace function public.delete_member(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_is_active boolean;
begin
  if not public.is_super_admin() then
    raise exception 'Réservé au Super Administrateur.';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'Vous ne pouvez pas supprimer votre propre compte.';
  end if;

  select role, is_active into v_role, v_is_active
  from public.profiles
  where id = target_user_id;

  if v_role is null then
    raise exception 'Compte introuvable.';
  end if;

  -- Un Super Administrateur ne peut pas en supprimer un autre : la
  -- rétrogradation reste un préalable explicite.
  if v_role = 'super_admin' then
    raise exception 'Un compte Super Administrateur ne peut pas être supprimé. Rétrogradez-le d''abord.';
  end if;

  -- Garde-fou : on ne supprime qu'un compte déjà désactivé, pour qu'une
  -- suppression soit toujours un second geste, jamais un clic isolé.
  if v_is_active is not false then
    raise exception 'Désactivez d''abord ce compte, puis supprimez-le.';
  end if;

  delete from auth.users where id = target_user_id;
end;
$$;

revoke all on function public.delete_member(uuid) from public;
revoke all on function public.delete_member(uuid) from anon;
grant execute on function public.delete_member(uuid) to authenticated;
