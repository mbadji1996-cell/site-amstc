-- ============================================================
-- PHASE 63 - Le membre change son année d'adhésion sans passer par
-- l'administration.
--
-- La phase 43 avait retiré cette colonne de l'auto-édition et institué
-- une demande validée par un admin. Le contrôle humain n'est plus voulu :
-- le membre applique lui-même son année.
--
-- Ce qui NE change pas, et pourquoi : le droit d'écriture direct sur
-- profiles.member_since reste révoqué. L'année est inscrite dans le
-- numéro de carte (« AMSTC-2023-095 ») ; une écriture directe par
-- PostgREST changerait l'année en laissant le numéro la contredire -
-- exactement le désaccord réparé en phase40, phase41 puis phase43. Tout
-- passe donc par set_own_member_since ci-dessous, qui réutilise
-- apply_member_since et renumérote la carte dans le même mouvement.
--
-- Le journal d'administration (phase51) enregistre déjà le changement
-- sous « annees_modifiees », avec le membre comme acteur : rien à ajouter
-- pour garder une trace de qui a modifié quoi.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. Le membre applique son année d'adhésion
-- ============================================================
-- Renvoie le nouveau numéro de carte, ou NULL si le numéro n'a pas bougé
-- (année identique, membre sans carte, ou numéro hors format maison).
create or replace function public.set_own_member_since(new_year int)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_number text;
begin
  if not public.is_approved_member() then
    raise exception 'Réservé aux membres approuvés.';
  end if;

  -- Mêmes bornes que request_member_since (phase43) : l'association
  -- n'existe pas avant 2014, et on n'adhère pas dans le futur.
  if new_year is null or new_year < 2014 or new_year > extract(year from now())::int then
    raise exception 'Année d''adhésion invalide.';
  end if;

  -- auth.uid() et non un paramètre : un membre ne peut modifier que sa
  -- propre année, quoi qu'il envoie.
  v_new_number := public.apply_member_since(auth.uid(), new_year);

  -- Une demande encore en attente n'a plus d'objet : le membre vient
  -- d'appliquer son choix. La laisser ferait réapparaître l'ancienne
  -- valeur dans l'écran d'administration, sans rien à valider.
  delete from public.member_since_requests
   where user_id = auth.uid() and status = 'pending';

  return v_new_number;
end;
$$;

grant execute on function public.set_own_member_since(int) to authenticated;

-- ============================================================
-- 2. La demande de validation n'a plus de raison d'être
-- ============================================================
-- request_member_since reste en place mais n'est plus appelée par
-- membres/profil.html. On la neutralise pour de bon : une version du site
-- encore en cache chez un membre ne doit pas continuer à déposer des
-- demandes que plus personne n'ira valider. Elle applique désormais le
-- changement, comme le fait la nouvelle fonction.
create or replace function public.request_member_since(new_year int)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.set_own_member_since(new_year);
  return 'applied';
end;
$$;

-- La table member_since_requests et les écrans d'administration qui la
-- lisent (membres/validation.html, membres/cartes-admin.html) sont
-- conservés : ils permettent de solder les demandes déposées avant cette
-- phase, et se masquent d'eux-mêmes une fois la liste vide.
