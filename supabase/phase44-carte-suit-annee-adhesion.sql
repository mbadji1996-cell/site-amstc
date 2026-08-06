-- ============================================================
-- PHASE 44 - membres/cartes-admin.html : le numéro de carte suit lui
-- aussi l'année d'adhésion.
--
-- phase43 avait traité l'écran membres/validation.html (set_member_years)
-- mais pas celui-ci : update_member_card écrivait l'année « Depuis » et
-- le numéro comme deux champs indépendants. Corriger l'année d'une carte
-- « AMSTC-2023-052 » en 2014 laissait donc le numéro annoncer 2023.
--
-- Règle retenue : on ne renumérote que si l'admin a changé l'année SANS
-- toucher au numéro. S'il a saisi un numéro lui-même, c'est son choix qui
-- l'emporte - sinon on écraserait une correction volontaire.
--
-- L'année est également reportée sur le profil du membre à qui la carte
-- est attribuée : les deux affichaient sinon des anciennetés différentes
-- (assign_member_card fait déjà ce report au moment de l'attribution).
--
-- À exécuter une seule fois, APRÈS phase43 (dont il réutilise
-- next_card_number) : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

-- DROP obligatoire : phase41 la déclarait « returns void », et
-- « create or replace » refuse de changer le type de retour.
drop function if exists public.update_member_card(uuid, text, text, text, int, text);

create or replace function public.update_member_card(
  card_id uuid,
  new_full_name text,
  new_phone text,
  new_card_number text,
  new_member_since int,
  new_city text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed_by     uuid;
  v_claim_status   text;
  v_ancien_numero  text;
  v_ancienne_annee int;
  v_saisi          text;
  v_final          text;
  v_renumerote     boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if btrim(coalesce(new_full_name, '')) = '' then
    raise exception 'Le nom est obligatoire.';
  end if;

  if btrim(coalesce(new_phone, '')) = '' then
    raise exception 'Le téléphone est obligatoire.';
  end if;

  select claimed_by, claim_status, card_number, member_since
    into v_claimed_by, v_claim_status, v_ancien_numero, v_ancienne_annee
  from public.member_cards
  where id = card_id
  for update;

  if v_claim_status is null then
    raise exception 'Carte introuvable.';
  end if;

  v_saisi := nullif(btrim(coalesce(new_card_number, '')), '');
  v_final := v_saisi;

  -- Renumérotation automatique : année modifiée, numéro laissé tel quel,
  -- et numéro existant au format maison (un numéro d'une autre forme est
  -- une saisie manuelle qu'on ne sait pas reconstruire).
  if new_member_since is not null
     and new_member_since is distinct from v_ancienne_annee
     and v_saisi is not distinct from v_ancien_numero
     and coalesce(v_ancien_numero, '') ~ '^AMSTC-\d{4}-\d+$'
  then
    v_final := public.next_card_number(new_member_since);
    v_renumerote := true;
  end if;

  -- Deux cartes ne doivent pas porter le même numéro.
  if v_final is not null and exists (
    select 1 from public.member_cards
    where card_number = v_final and id <> card_id
  ) then
    raise exception 'Ce numéro de carte est déjà utilisé par une autre carte.';
  end if;

  update public.member_cards
     set full_name    = btrim(new_full_name),
         phone        = btrim(new_phone),
         card_number  = v_final,
         member_since = new_member_since,
         city         = nullif(btrim(coalesce(new_city, '')), '')
   where id = card_id;

  -- Carte déjà attribuée : le membre doit afficher le numéro corrigé, et
  -- la même ancienneté que sa carte.
  if v_claim_status = 'confirmed' and v_claimed_by is not null then
    update public.profiles
       set legacy_card_number = v_final,
           member_since = case
             when new_member_since is distinct from v_ancienne_annee
               then new_member_since
             else member_since
           end
     where id = v_claimed_by;
  end if;

  -- Renvoie le nouveau numéro seulement s'il a été calculé ici, pour que
  -- l'écran puisse l'annoncer sans confondre avec une saisie de l'admin.
  return case when v_renumerote then v_final else null end;
end;
$$;
