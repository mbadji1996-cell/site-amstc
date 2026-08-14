-- ============================================================
-- PHASE 77 - La carte porte aussi la validité et les cotisations,
-- et reste synchrone avec la fiche du membre.
--
-- CE QUI CHANGE.
--
-- 1. member_cards gagne cotisations_hint (jsonb, { "2026": [1,2,3] }) :
--    pour une carte NON attribuée, la carte est le seul endroit où
--    noter les mois déjà réglés - la table cotisations exige un compte.
--    La validité utilisait déjà expiry_hint (phase9).
--
-- 2. update_member_card accepte la région, l'année de fin de validité
--    et les mois de cotisation d'une année. Carte attribuée : tout est
--    REPORTÉ sur la fiche (profiles.card_valid_until, table
--    cotisations), qui reste la référence - l'écran des cartes lit ces
--    valeurs-là pour les cartes attribuées, aucune divergence possible.
--
-- 3. utiliser_invitation accepte p_member_since : le membre qui active
--    son compte peut corriger son année d'adhésion (choix validé le
--    14/08/2026). La carte est renumérotée selon la règle de phase44
--    (numéro au format maison uniquement), et la fiche hérite de tout :
--    année, numéro, validité (expiry_hint), mois de cotisation.
--
-- 4. assign_member_card (attribution directe, sans invitation) reporte
--    désormais aussi les mois de cotisation notés sur la carte, et
--    inscrit l'année de validité sur la carte elle-même (expiry_hint) -
--    les deux faces disent la même chose.
--
-- RÈGLE DE COHÉRENCE d'ensemble : carte NON attribuée, les valeurs
-- vivent sur la carte (expiry_hint, cotisations_hint) ; carte
-- attribuée, la FICHE fait foi et l'écran des cartes lit la fiche.
-- Les reports ci-dessus font le pont au moment de l'attribution et à
-- chaque modification depuis l'écran des cartes.
--
-- À exécuter une seule fois, APRÈS phase43/44 (next_card_number) et
-- phase68 : Studio (instance amstc) > SQL Editor > coller > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Les mois de cotisation notés sur la carte =====
alter table public.member_cards
  add column if not exists cotisations_hint jsonb not null default '{}'::jsonb;

-- ===== 2. update_member_card : région, validité, cotisations =====
-- DROP obligatoire : la signature change (phase44 avait 6 paramètres).
drop function if exists public.update_member_card(uuid, text, text, text, int, text);

create or replace function public.update_member_card(
  card_id uuid,
  new_full_name text,
  new_phone text,
  new_card_number text,
  new_member_since int,
  new_city text,
  new_region text default null,
  new_expiry int default null,
  new_cotis_annee int default null,
  new_cotis_mois int[] default null
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
  v_mois           int[];
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

  -- Renumérotation automatique (phase44) : année modifiée, numéro laissé
  -- tel quel, et numéro existant au format maison.
  if new_member_since is not null
     and new_member_since is distinct from v_ancienne_annee
     and v_saisi is not distinct from v_ancien_numero
     and coalesce(v_ancien_numero, '') ~ '^AMSTC-\d{4}-\d+$'
  then
    v_final := public.next_card_number(new_member_since);
    v_renumerote := true;
  end if;

  if v_final is not null and exists (
    select 1 from public.member_cards
    where card_number = v_final and id <> card_id
  ) then
    raise exception 'Ce numéro de carte est déjà utilisé par une autre carte.';
  end if;

  -- Mois normalisés : bornés à 1..12, dédoublonnés, triés. Un tableau
  -- vide est VALIDE - il efface les mois de l'année choisie.
  if new_cotis_annee is not null and new_cotis_mois is not null then
    select coalesce(array_agg(distinct m order by m), '{}')
      into v_mois
      from unnest(new_cotis_mois) m
     where m between 1 and 12;
  end if;

  update public.member_cards
     set full_name    = btrim(new_full_name),
         phone        = btrim(new_phone),
         card_number  = v_final,
         member_since = new_member_since,
         city         = nullif(btrim(coalesce(new_city, '')), ''),
         -- null = paramètre absent (ancien appel) : on ne touche pas.
         region       = case when new_region is null then region
                             else nullif(btrim(new_region), '') end,
         expiry_hint  = coalesce(new_expiry, expiry_hint),
         cotisations_hint = case
           when new_cotis_annee is null or v_mois is null then cotisations_hint
           else jsonb_set(coalesce(cotisations_hint, '{}'::jsonb),
                          array[new_cotis_annee::text], to_jsonb(v_mois), true)
         end
   where id = card_id;

  -- Carte attribuée : la fiche du membre est la référence, elle doit
  -- dire la même chose que la carte.
  if v_claim_status = 'confirmed' and v_claimed_by is not null then
    update public.profiles
       set legacy_card_number = v_final,
           member_since = case
             when new_member_since is distinct from v_ancienne_annee
               then new_member_since
             else member_since
           end,
           card_valid_until = coalesce(new_expiry, card_valid_until)
     where id = v_claimed_by;

    if new_cotis_annee is not null and v_mois is not null then
      insert into public.cotisations (user_id, year, months_paid)
      values (v_claimed_by, new_cotis_annee, v_mois)
      on conflict (user_id, year) do update
        set months_paid = excluded.months_paid;
    end if;
  end if;

  return case when v_renumerote then v_final else null end;
end;
$$;

revoke all on function public.update_member_card(uuid, text, text, text, int, text, text, int, int, int[]) from public, anon;
grant execute on function public.update_member_card(uuid, text, text, text, int, text, text, int, int, int[]) to authenticated;

-- ===== 3. utiliser_invitation : le membre peut corriger son année =====
-- DROP obligatoire : la signature change ; l'ancien appel à un seul
-- paramètre reste valable grâce à la valeur par défaut.
drop function if exists public.utiliser_invitation(text);

create or replace function public.utiliser_invitation(p_jeton text, p_member_since int default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.invitations_carte%rowtype;
  v_carte public.member_cards%rowtype;
  v_numero text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;

  -- Verrou : deux envois simultanés du formulaire ne doivent pas
  -- rattacher la même carte à deux comptes.
  select * into v_inv from public.invitations_carte where jeton = p_jeton for update;

  if v_inv.id is null then
    raise exception 'Ce lien d''invitation est inconnu.';
  end if;
  if v_inv.used_at is not null then
    raise exception 'Ce lien a déjà été utilisé.';
  end if;
  if now() > v_inv.expire_le then
    raise exception 'Ce lien a expiré.';
  end if;

  select * into v_carte from public.member_cards where id = v_inv.card_id;

  -- Année corrigée par le membre : la carte suit, et son numéro aussi
  -- quand il est au format maison (même règle que phase44) - un numéro
  -- d'une autre forme est une saisie manuelle qu'on ne sait pas
  -- reconstruire.
  v_numero := v_carte.card_number;
  if p_member_since is not null
     and p_member_since between 1900 and extract(year from now())::int
     and p_member_since is distinct from v_carte.member_since
  then
    if coalesce(v_carte.card_number, '') ~ '^AMSTC-\d{4}-\d+$' then
      v_numero := public.next_card_number(p_member_since);
    end if;
    update public.member_cards
       set member_since = p_member_since, card_number = v_numero
     where id = v_inv.card_id;
    v_carte.member_since := p_member_since;
    v_carte.card_number  := v_numero;
  end if;

  -- Le compte est approuvé d'emblée et hérite de la carte : ancienneté,
  -- numéro, ville, téléphone, région, et désormais la validité.
  update public.profiles
     set status             = 'approved',
         legacy_card_number = coalesce(v_carte.card_number, legacy_card_number),
         member_since       = coalesce(v_carte.member_since, member_since),
         city               = coalesce(nullif(btrim(coalesce(city, '')), ''), v_carte.city),
         region             = coalesce(region, v_carte.region),
         phone              = coalesce(nullif(btrim(coalesce(phone, '')), ''), v_carte.phone),
         card_valid_until   = coalesce(v_carte.expiry_hint, card_valid_until),
         applicant_type     = coalesce(applicant_type, 'membre_existant')
   where id = auth.uid();

  -- Les mois de cotisation notés sur la carte rejoignent la fiche. En
  -- cas de mois déjà présents (compte réutilisé), on fait l'UNION : un
  -- mois réglé ne doit jamais disparaître.
  insert into public.cotisations (user_id, year, months_paid)
  select auth.uid(), k.key::int,
         (select coalesce(array_agg(distinct e.value::int order by e.value::int), '{}')
            from jsonb_array_elements_text(k.value) e(value)
           where e.value ~ '^\d+$' and e.value::int between 1 and 12)
    from jsonb_each(coalesce(v_carte.cotisations_hint, '{}'::jsonb)) k
   where k.key ~ '^\d{4}$' and jsonb_typeof(k.value) = 'array'
  on conflict (user_id, year) do update
    set months_paid = (select array(select distinct m
                                      from unnest(cotisations.months_paid || excluded.months_paid) m
                                     order by m));

  update public.member_cards
     set claim_status = 'confirmed', claimed_by = auth.uid(),
         claimed_at = now(), confirmed_at = now()
   where id = v_inv.card_id;

  update public.invitations_carte
     set used_at = now(), used_by = auth.uid()
   where id = v_inv.id;

  perform public.journaliser('invitation_utilisee', auth.uid(),
    coalesce(v_carte.full_name, '(sans nom)'),
    jsonb_build_object('carte', v_carte.card_number));
end;
$$;

revoke all on function public.utiliser_invitation(text, int) from public, anon;
grant execute on function public.utiliser_invitation(text, int) to authenticated;

-- ===== 4. assign_member_card : reporte aussi les cotisations =====
create or replace function public.assign_member_card(card_id uuid, member_id uuid, expiry_year int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_carte public.member_cards%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if expiry_year is null then
    raise exception 'Année de fin de validité obligatoire.';
  end if;

  select * into v_carte
  from public.member_cards
  where id = card_id
  for update;

  if v_carte.claim_status is null then
    raise exception 'Carte introuvable.';
  end if;

  if v_carte.claim_status = 'confirmed' then
    raise exception 'Cette carte a déjà été attribuée à un membre.';
  end if;

  -- expiry_hint aussi sur la carte : les deux faces disent la même chose.
  update public.member_cards
     set claimed_by = member_id, claim_status = 'confirmed',
         claimed_at = now(), confirmed_at = now(),
         expiry_hint = expiry_year
   where id = card_id;

  update public.profiles
     set legacy_card_number = coalesce(v_carte.card_number, legacy_card_number),
         member_since = coalesce(v_carte.member_since, member_since),
         card_valid_until = expiry_year,
         title = coalesce(v_carte.title, title),
         domain = coalesce(v_carte.domain, domain),
         domain_autre = coalesce(v_carte.domain_autre, domain_autre),
         specialty = coalesce(v_carte.specialty, specialty)
   where id = member_id;

  insert into public.cotisations (user_id, year, months_paid)
  select member_id, k.key::int,
         (select coalesce(array_agg(distinct e.value::int order by e.value::int), '{}')
            from jsonb_array_elements_text(k.value) e(value)
           where e.value ~ '^\d+$' and e.value::int between 1 and 12)
    from jsonb_each(coalesce(v_carte.cotisations_hint, '{}'::jsonb)) k
   where k.key ~ '^\d{4}$' and jsonb_typeof(k.value) = 'array'
  on conflict (user_id, year) do update
    set months_paid = (select array(select distinct m
                                      from unnest(cotisations.months_paid || excluded.months_paid) m
                                     order by m));
end;
$$;

revoke all on function public.assign_member_card(uuid, uuid, int) from public, anon;
grant execute on function public.assign_member_card(uuid, uuid, int) to authenticated;

notify pgrst, 'reload schema';

-- Contrôles.
select column_name from information_schema.columns
 where table_name = 'member_cards' and column_name in ('expiry_hint', 'cotisations_hint');
select proname, pg_get_function_arguments(oid)
  from pg_proc
 where proname in ('update_member_card', 'utiliser_invitation', 'assign_member_card')
 order by proname;
