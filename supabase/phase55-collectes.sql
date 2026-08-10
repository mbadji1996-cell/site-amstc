-- ============================================================
-- PHASE 55 - Collectes : activités à cotisation et sasso (dons)
--
-- Deux besoins portés par le même socle :
--   - « cotisation » : l'administration crée une activité avec un montant
--     fixé ; les membres volontaires paient ce montant (Wave / Orange
--     Money, déclaration de référence, validation admin - le circuit des
--     cotisations existantes).
--   - « sasso » : demande de don. En espèces (montant libre) ou en nature :
--     l'administration fournit une liste d'items valorisés, le membre en
--     choisit un et décide de PAYER le montant correspondant ou de DONNER
--     l'objet lui-même.
--
-- Toutes les écritures passent par des fonctions SECURITY DEFINER, comme
-- partout ailleurs sur cette instance : authenticated n'a aucun droit
-- d'écriture direct sur les tables.
--
-- PRÉREQUIS : phase51 (journal) - les validations y sont tracées.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

-- ===== Tables =====

create table if not exists public.collectes (
  id           uuid primary key default gen_random_uuid(),
  titre        text not null,
  description  text,
  type         text not null check (type in ('cotisation', 'sasso')),
  -- Montant fixé d'une activité à cotisation ; null pour un sasso.
  montant_fcfa int check (montant_fcfa is null or montant_fcfa > 0),
  date_limite  date,
  is_open      boolean not null default true,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

create table if not exists public.collecte_items (
  id           uuid primary key default gen_random_uuid(),
  collecte_id  uuid not null references public.collectes(id) on delete cascade,
  libelle      text not null,
  montant_fcfa int not null check (montant_fcfa > 0),
  quantite     int not null default 1 check (quantite > 0),
  ordre        int not null default 0
);

create table if not exists public.collecte_participations (
  id                uuid primary key default gen_random_uuid(),
  collecte_id       uuid not null references public.collectes(id) on delete cascade,
  user_id           uuid not null references public.profiles(id) on delete cascade,
  item_id           uuid references public.collecte_items(id) on delete cascade,
  -- 'espece' : paiement declare (cotisation, don libre, ou item paye)
  -- 'nature' : promesse de remise de l'objet lui-meme
  mode              text not null check (mode in ('espece', 'nature')),
  montant_fcfa      int not null check (montant_fcfa > 0),
  payment_method    text check (payment_method in ('wave', 'orange_money')),
  payment_reference text,
  -- pending -> confirmed / rejected (espece)
  -- pending -> remis / rejected (nature)
  status            text not null default 'pending'
                    check (status in ('pending', 'confirmed', 'remis', 'rejected')),
  created_at        timestamptz not null default now(),
  confirmed_at      timestamptz,
  -- Un paiement declare porte forcement sa methode et sa reference.
  constraint espece_avec_reference check (
    mode <> 'espece' or (payment_method is not null and payment_reference is not null)
  )
);

create index if not exists collecte_participations_collecte_idx
  on public.collecte_participations (collecte_id, status);
create index if not exists collecte_participations_user_idx
  on public.collecte_participations (user_id, created_at desc);

-- ===== Lecture (RLS) =====

alter table public.collectes              enable row level security;
alter table public.collecte_items         enable row level security;
alter table public.collecte_participations enable row level security;

grant select on public.collectes, public.collecte_items, public.collecte_participations to authenticated;

drop policy if exists "Membres : collectes visibles" on public.collectes;
create policy "Membres : collectes visibles"
  on public.collectes for select
  using (public.is_approved_member());

drop policy if exists "Membres : items visibles" on public.collecte_items;
create policy "Membres : items visibles"
  on public.collecte_items for select
  using (public.is_approved_member());

-- Chacun voit ses participations ; l'administration voit tout.
drop policy if exists "Participations : soi-même ou admin" on public.collecte_participations;
create policy "Participations : soi-même ou admin"
  on public.collecte_participations for select
  using (auth.uid() = user_id or public.is_admin());

-- ===== Création et gestion (administration) =====

-- p_items : jsonb [{libelle, montant_fcfa, quantite}] - la liste collée est
-- analysée côté client, qui montre un aperçu avant l'envoi.
create or replace function public.creer_collecte(
  p_titre text, p_description text, p_type text,
  p_montant_fcfa int, p_date_limite date, p_items jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_item jsonb;
  v_ordre int := 0;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if btrim(coalesce(p_titre, '')) = '' then
    raise exception 'Le titre est obligatoire.';
  end if;
  if p_type not in ('cotisation', 'sasso') then
    raise exception 'Type invalide.';
  end if;
  if p_type = 'cotisation' and (p_montant_fcfa is null or p_montant_fcfa <= 0) then
    raise exception 'Une activité à cotisation doit fixer un montant.';
  end if;

  insert into public.collectes (titre, description, type, montant_fcfa, date_limite, created_by)
  values (btrim(p_titre), nullif(btrim(coalesce(p_description, '')), ''),
          p_type, case when p_type = 'cotisation' then p_montant_fcfa else null end,
          p_date_limite, auth.uid())
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into public.collecte_items (collecte_id, libelle, montant_fcfa, quantite, ordre)
    values (v_id,
            btrim(v_item->>'libelle'),
            (v_item->>'montant_fcfa')::int,
            greatest(1, coalesce((v_item->>'quantite')::int, 1)),
            v_ordre);
    v_ordre := v_ordre + 1;
  end loop;

  return v_id;
end;
$$;

create or replace function public.modifier_collecte(
  p_id uuid, p_titre text, p_description text,
  p_montant_fcfa int, p_date_limite date, p_is_open boolean
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
  update public.collectes
     set titre        = coalesce(nullif(btrim(coalesce(p_titre, '')), ''), titre),
         description  = nullif(btrim(coalesce(p_description, '')), ''),
         montant_fcfa = case when type = 'cotisation' then coalesce(p_montant_fcfa, montant_fcfa) else null end,
         date_limite  = p_date_limite,
         is_open      = coalesce(p_is_open, is_open)
   where id = p_id;
end;
$$;

-- La liste d'items n'est remplaçable que tant que personne n'a participé :
-- après, supprimer un item détruirait des participations (cascade).
create or replace function public.remplacer_items_collecte(p_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_ordre int := 0;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if exists (select 1 from public.collecte_participations where collecte_id = p_id) then
    raise exception 'Des membres ont déjà participé : la liste ne peut plus être remplacée.';
  end if;

  delete from public.collecte_items where collecte_id = p_id;
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into public.collecte_items (collecte_id, libelle, montant_fcfa, quantite, ordre)
    values (p_id, btrim(v_item->>'libelle'), (v_item->>'montant_fcfa')::int,
            greatest(1, coalesce((v_item->>'quantite')::int, 1)), v_ordre);
    v_ordre := v_ordre + 1;
  end loop;
end;
$$;

create or replace function public.supprimer_collecte(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Suppression définitive (participations comprises) : réservée au Super
  -- Administrateur, comme les autres suppressions destructrices.
  if not public.is_super_admin() then
    raise exception 'Réservé au Super Administrateur.';
  end if;
  delete from public.collectes where id = p_id;
end;
$$;

-- ===== Participation (membre) =====

create or replace function public.participer_collecte(
  p_collecte_id uuid, p_item_id uuid, p_mode text,
  p_montant_fcfa int, p_payment_method text, p_payment_reference text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_collecte public.collectes%rowtype;
  v_item public.collecte_items%rowtype;
  v_pris int;
  v_id uuid;
begin
  if not public.is_approved_member() then
    raise exception 'Réservé aux membres approuvés.';
  end if;
  if p_mode not in ('espece', 'nature') then
    raise exception 'Mode invalide.';
  end if;

  select * into v_collecte from public.collectes where id = p_collecte_id;
  if v_collecte.id is null then
    raise exception 'Collecte introuvable.';
  end if;
  if not v_collecte.is_open then
    raise exception 'Cette collecte est clôturée.';
  end if;
  if v_collecte.date_limite is not null and now()::date > v_collecte.date_limite then
    raise exception 'La date limite de cette collecte est dépassée.';
  end if;

  if v_collecte.type = 'cotisation' then
    -- Cotisation : pas d'item, montant imposé, une seule participation
    -- vivante par membre (une rejetée peut être refaite).
    if p_item_id is not null or p_mode <> 'espece' then
      raise exception 'Cette activité se règle par paiement du montant fixé.';
    end if;
    if p_montant_fcfa is distinct from v_collecte.montant_fcfa then
      raise exception 'Le montant attendu est de % F.', v_collecte.montant_fcfa;
    end if;
    if exists (select 1 from public.collecte_participations
                where collecte_id = p_collecte_id and user_id = auth.uid()
                  and status <> 'rejected') then
      raise exception 'Vous avez déjà participé à cette activité.';
    end if;
  else
    -- Sasso : espèces libres (sans item), ou item payé / donné en nature.
    if p_item_id is null then
      if p_mode <> 'espece' then
        raise exception 'Un don en nature se rattache à un item de la liste.';
      end if;
      if coalesce(p_montant_fcfa, 0) <= 0 then
        raise exception 'Indiquez le montant de votre don.';
      end if;
    else
      -- Verrou : deux membres qui choisissent le dernier exemplaire au même
      -- instant ne doivent pas passer tous les deux.
      select * into v_item from public.collecte_items
       where id = p_item_id and collecte_id = p_collecte_id
       for update;
      if v_item.id is null then
        raise exception 'Item introuvable dans cette collecte.';
      end if;
      select count(*) into v_pris from public.collecte_participations
       where item_id = p_item_id and status <> 'rejected';
      if v_pris >= v_item.quantite then
        raise exception 'Cet item a déjà été entièrement pris - merci !';
      end if;
      -- Le montant porté est la valeur de l'item, payé ou promis en nature.
      p_montant_fcfa := v_item.montant_fcfa;
    end if;
  end if;

  if p_mode = 'espece' then
    if p_payment_method not in ('wave', 'orange_money') then
      raise exception 'Choisissez un moyen de paiement.';
    end if;
    if btrim(coalesce(p_payment_reference, '')) = '' then
      raise exception 'Saisissez la référence de la transaction.';
    end if;
  else
    p_payment_method := null;
    p_payment_reference := null;
  end if;

  insert into public.collecte_participations
    (collecte_id, user_id, item_id, mode, montant_fcfa, payment_method, payment_reference)
  values (p_collecte_id, auth.uid(), p_item_id, p_mode, p_montant_fcfa,
          p_payment_method, nullif(btrim(coalesce(p_payment_reference, '')), ''))
  returning id into v_id;

  return v_id;
end;
$$;

-- ===== Validation (administration) =====

create or replace function public.valider_participation_collecte(p_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_part public.collecte_participations%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select * into v_part from public.collecte_participations where id = p_id;
  if v_part.id is null then
    raise exception 'Participation introuvable.';
  end if;

  -- 'confirmed' valide un paiement ; 'remis' acte la réception d'un don en
  -- nature ; 'pending' annule une validation faite par erreur.
  if p_status not in ('confirmed', 'remis', 'rejected', 'pending') then
    raise exception 'Statut invalide.';
  end if;
  if p_status = 'confirmed' and v_part.mode <> 'espece' then
    raise exception 'Un don en nature se marque « remis », pas « confirmé ».';
  end if;
  if p_status = 'remis' and v_part.mode <> 'nature' then
    raise exception 'Un paiement se marque « confirmé », pas « remis ».';
  end if;

  update public.collecte_participations
     set status = p_status,
         confirmed_at = case when p_status in ('confirmed', 'remis') then now() else null end
   where id = p_id;
end;
$$;

-- ===== Journal (phase51) =====

create or replace function public.trg_journal_collecte()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text;
  v_titre text;
begin
  if new.status is distinct from old.status then
    select full_name into v_nom from public.profiles where id = new.user_id;
    select titre into v_titre from public.collectes where id = new.collecte_id;
    perform public.journaliser('collecte_' || new.status, new.user_id,
      coalesce(v_nom, '(membre inconnu)'),
      jsonb_build_object('collecte', v_titre, 'mode', new.mode,
                         'montant', new.montant_fcfa, 'avant', old.status));
  end if;
  return new;
end;
$$;

drop trigger if exists journal_collecte on public.collecte_participations;
create trigger journal_collecte
  after update on public.collecte_participations
  for each row
  execute function public.trg_journal_collecte();

-- ===== Droits d'exécution =====

revoke all on function public.creer_collecte(text, text, text, int, date, jsonb) from public, anon;
revoke all on function public.modifier_collecte(uuid, text, text, int, date, boolean) from public, anon;
revoke all on function public.remplacer_items_collecte(uuid, jsonb) from public, anon;
revoke all on function public.supprimer_collecte(uuid) from public, anon;
revoke all on function public.participer_collecte(uuid, uuid, text, int, text, text) from public, anon;
revoke all on function public.valider_participation_collecte(uuid, text) from public, anon;

grant execute on function public.creer_collecte(text, text, text, int, date, jsonb) to authenticated;
grant execute on function public.modifier_collecte(uuid, text, text, int, date, boolean) to authenticated;
grant execute on function public.remplacer_items_collecte(uuid, jsonb) to authenticated;
grant execute on function public.supprimer_collecte(uuid) to authenticated;
grant execute on function public.participer_collecte(uuid, uuid, text, int, text, text) to authenticated;
grant execute on function public.valider_participation_collecte(uuid, text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : les six fonctions doivent apparaître.
select proname from pg_proc
 where proname in ('creer_collecte','modifier_collecte','remplacer_items_collecte',
                   'supprimer_collecte','participer_collecte','valider_participation_collecte')
 order by proname;
