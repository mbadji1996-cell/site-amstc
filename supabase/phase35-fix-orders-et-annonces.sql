-- Corrige deux bugs relevés lors d'un audit du code (voir commit
-- "Corriger les bugs relevés par un audit complet du code") :
--
-- 1. orders.user_id était déclaré "not null" tout en ayant
--    "on delete set null" sur sa clé étrangère vers profiles(id).
--    Supprimer un membre ayant déjà passé une commande dans la Boutique
--    fait donc échouer la suppression : Postgres tente de mettre
--    user_id à NULL, ce qui viole la contrainte not null. La commande
--    n'est jamais supprimée (bonne chose), mais la suppression du
--    membre échoue avec une erreur générique côté admin.
--
-- 2. Le déclencheur qui limite à 3 le nombre d'annonces épinglées
--    comptait aussi les annonces désactivées (is_active = false), qui
--    ne sont pourtant plus visibles des membres. Résultat : un admin
--    pouvait se retrouver bloqué ("limite atteinte") alors que moins de
--    3 annonces étaient réellement affichées.

-- 1. orders.user_id : autorise NULL, pour que la commande survive à la
--    suppression du compte (l'historique de vente est conservé).
alter table public.orders alter column user_id drop not null;

-- 2. Le décompte des annonces épinglées ignore désormais celles qui
--    sont désactivées.
create or replace function public.check_max_pinned_announcements()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pinned_count int;
begin
  if new.is_pinned then
    select count(*) into v_pinned_count
    from public.member_announcements
    where is_pinned = true and is_active = true and id is distinct from new.id;
    if v_pinned_count >= 3 then
      raise exception 'Impossible d''épingler plus de 3 annonces à la fois. Désépinglez-en une d''abord.';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
