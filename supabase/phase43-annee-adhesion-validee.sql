-- ============================================================
-- PHASE 43 - L'année d'adhésion pilote le numéro de carte, et sa
-- modification par le membre passe par une validation de l'admin.
--
-- Deux problèmes distincts, une même cause : l'année d'adhésion était
-- traitée comme un champ ordinaire.
--
-- 1. Le numéro de carte porte l'année d'adhésion (« AMSTC-2023-095 »).
--    Corriger l'année dans membres/validation.html laissait donc le
--    numéro en contradiction avec elle. set_member_years renumérote
--    désormais la carte du membre - dans member_cards ET dans
--    profiles.legacy_card_number, sans quoi les deux divergent (c'est le
--    désaccord déjà réparé en phase40 puis en phase41).
--
-- 2. Un membre pouvait changer son année d'adhésion depuis son profil,
--    donc son ancienneté et son numéro de carte, sans contrôle. Cette
--    colonne sort de l'auto-édition ouverte en phase8 : le membre dépose
--    une demande, l'admin l'applique ou la refuse.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. Numérotation : trouver le prochain numéro libre d'une année
-- ============================================================
-- Même règle que phase40 : « AMSTC-<année>-<n° sur 3 chiffres> », la
-- numérotation reprenant après le dernier numéro déjà pris pour l'année.
create or replace function public.next_card_number(p_year int)
returns text
language sql
security definer
set search_path = public
as $$
  select 'AMSTC-' || p_year::text || '-' || lpad((
    coalesce(
      max(((regexp_match(card_number, '^AMSTC-(\d{4})-(\d+)$'))[2])::int),
      0
    ) + 1
  )::text, 3, '0')
  from public.member_cards
  where card_number ~ ('^AMSTC-' || p_year::text || '-\d+$');
$$;

-- Fonction interne : appelée uniquement depuis les fonctions ci-dessous.
revoke execute on function public.next_card_number(int) from public, anon, authenticated;

-- ============================================================
-- 2. Appliquer une année d'adhésion, numéro de carte compris
-- ============================================================
-- Renvoie le nouveau numéro de carte, ou NULL si aucun numéro n'a changé
-- (année identique, membre sans carte, ou numéro hors format maison).
create or replace function public.apply_member_since(
  p_member_id uuid,
  p_new_year  int
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_year    int;
  v_card_id     uuid;
  v_card_number text;
  v_prof_number text;
  v_new_number  text;
begin
  select member_since, legacy_card_number
    into v_old_year, v_prof_number
  from public.profiles
  where id = p_member_id
  for update;

  if not found then
    raise exception 'Membre introuvable.';
  end if;

  update public.profiles
     set member_since = p_new_year
   where id = p_member_id;

  -- Rien à renuméroter si l'année ne bouge pas.
  if p_new_year is null or p_new_year is not distinct from v_old_year then
    return null;
  end if;

  select id, card_number
    into v_card_id, v_card_number
  from public.member_cards
  where claimed_by = p_member_id
    and claim_status = 'confirmed'
  order by created_at
  limit 1
  for update;

  -- On ne renumérote que les numéros au format maison : un numéro d'une
  -- autre forme est une donnée saisie à la main qu'on ne sait pas
  -- reconstruire, et l'écraser perdrait de l'information.
  if coalesce(v_card_number, v_prof_number) ~ '^AMSTC-\d{4}-\d+$' then
    v_new_number := public.next_card_number(p_new_year);
  end if;

  if v_card_id is not null then
    update public.member_cards
       set member_since = p_new_year,
           card_number  = coalesce(v_new_number, card_number)
     where id = v_card_id;
  end if;

  if v_new_number is not null then
    update public.profiles
       set legacy_card_number = v_new_number
     where id = p_member_id;
  end if;

  return v_new_number;
end;
$$;

revoke execute on function public.apply_member_since(uuid, int) from public, anon, authenticated;

-- ============================================================
-- 3. set_member_years (remplace phase39) : renumérote la carte
-- ============================================================
-- Renvoie le nouveau numéro de carte pour que l'écran d'administration
-- puisse l'annoncer, ou NULL si le numéro n'a pas bougé.
--
-- DROP obligatoire : phase39 la déclarait « returns void », et
-- « create or replace » refuse de changer le type de retour.
drop function if exists public.set_member_years(uuid, int, int);

create or replace function public.set_member_years(
  member_id uuid,
  new_member_since int,
  new_card_valid_until int
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_number text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  v_new_number := public.apply_member_since(member_id, new_member_since);

  update public.profiles
     set card_valid_until = new_card_valid_until
   where id = member_id;

  return v_new_number;
end;
$$;

-- ============================================================
-- 4. L'année d'adhésion sort de l'auto-édition du membre
-- ============================================================
-- phase8 avait ouvert member_since à l'édition libre par le membre. Le
-- grant colonne est le seul verrou nécessaire : sans lui, PostgREST
-- refuse l'écriture (membres/profil.html n'envoie plus cette colonne et
-- passe par request_member_since).
revoke update (member_since) on public.profiles from authenticated;

-- ============================================================
-- 5. Demandes de modification de l'année d'adhésion
-- ============================================================
create table if not exists public.member_since_requests (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  previous_year  int,
  requested_year int not null,
  status         text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected')),
  created_at     timestamptz not null default now(),
  reviewed_by    uuid references public.profiles(id) on delete set null,
  reviewed_at    timestamptz
);

-- Une seule demande en attente par membre : la déposer à nouveau écrase
-- la précédente plutôt que d'empiler des demandes contradictoires.
create unique index if not exists member_since_requests_one_pending
  on public.member_since_requests (user_id)
  where status = 'pending';

create index if not exists member_since_requests_status_idx
  on public.member_since_requests (status, created_at desc);

alter table public.member_since_requests enable row level security;

-- Lecture seule pour les connectés : toutes les écritures passent par les
-- fonctions SECURITY DEFINER ci-dessous.
grant select on public.member_since_requests to authenticated;

-- Le membre consulte ses propres demandes (pour afficher « en attente »).
-- Les écritures passent exclusivement par les fonctions ci-dessous.
drop policy if exists "Members can view own member_since requests" on public.member_since_requests;
create policy "Members can view own member_since requests"
  on public.member_since_requests for select
  using (auth.uid() = user_id);

drop policy if exists "Admins can view member_since requests" on public.member_since_requests;
create policy "Admins can view member_since requests"
  on public.member_since_requests for select
  using (public.is_admin());

-- ============================================================
-- 6. Le membre dépose sa demande
-- ============================================================
create or replace function public.request_member_since(new_year int)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current int;
begin
  if not public.is_approved_member() then
    raise exception 'Réservé aux membres approuvés.';
  end if;

  if new_year is null or new_year < 2014 or new_year > extract(year from now())::int then
    raise exception 'Année d''adhésion invalide.';
  end if;

  select member_since into v_current from public.profiles where id = auth.uid();

  if new_year is not distinct from v_current then
    -- Rien à demander : on annule une éventuelle demande en attente.
    delete from public.member_since_requests
     where user_id = auth.uid() and status = 'pending';
    return 'unchanged';
  end if;

  delete from public.member_since_requests
   where user_id = auth.uid() and status = 'pending';

  insert into public.member_since_requests (user_id, previous_year, requested_year)
  values (auth.uid(), v_current, new_year);

  return 'pending';
end;
$$;

-- ============================================================
-- 7. L'admin consulte les demandes en attente
-- ============================================================
create or replace function public.member_since_requests_pending()
returns table (
  request_id     uuid,
  user_id        uuid,
  full_name      text,
  email          text,
  card_number    text,
  previous_year  int,
  requested_year int,
  created_at     timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  return query
    select r.id, r.user_id, p.full_name, p.email, p.legacy_card_number,
           r.previous_year, r.requested_year, r.created_at
      from public.member_since_requests r
      join public.profiles p on p.id = r.user_id
     where r.status = 'pending'
     order by r.created_at;
end;
$$;

-- ============================================================
-- 8. L'admin applique ou refuse la demande
-- ============================================================
-- Renvoie le nouveau numéro de carte en cas d'acceptation, ou NULL.
create or replace function public.review_member_since_request(
  request_id uuid,
  approve    boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid;
  v_year       int;
  v_status     text;
  v_new_number text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select user_id, requested_year, status
    into v_user_id, v_year, v_status
  from public.member_since_requests
  where id = request_id
  for update;

  if v_status is null then
    raise exception 'Demande introuvable.';
  end if;

  if v_status <> 'pending' then
    raise exception 'Cette demande a déjà été traitée.';
  end if;

  if approve then
    v_new_number := public.apply_member_since(v_user_id, v_year);
  end if;

  update public.member_since_requests
     set status      = case when approve then 'approved' else 'rejected' end,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = request_id;

  return v_new_number;
end;
$$;
