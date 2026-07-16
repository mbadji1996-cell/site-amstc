-- ============================================================
-- PHASE 5 — Cartes de membres historiques (import + réclamation)
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New query > coller > Run
-- (à appliquer après schema.sql, phase2-roles.sql et phase4-nouveaux-modules.sql)
-- ============================================================

-- ===== Table d'import : la liste papier des membres existants =====
-- Une ligne par membre connu avant la mise en ligne de l'espace membres.
-- Rempli en une fois par un admin (voir membres/cartes-admin.html), puis
-- chaque membre peut "réclamer" la ligne qui correspond à son nom.
create table if not exists public.member_cards (
  id            uuid primary key default gen_random_uuid(),
  full_name     text not null,
  phone         text not null,
  card_number   text,
  member_since  int,
  city          text,
  claim_status  text not null default 'unclaimed' check (claim_status in ('unclaimed', 'pending', 'confirmed')),
  claimed_by    uuid references public.profiles(id) on delete set null,
  claimed_at    timestamptz,
  confirmed_at  timestamptz,
  created_at    timestamptz not null default now()
);

alter table public.member_cards enable row level security;

-- Un admin peut tout faire (import, revue des réclamations)
drop policy if exists "Admins can manage member cards" on public.member_cards;
create policy "Admins can manage member cards"
  on public.member_cards for all
  using (public.is_admin());

-- Un membre peut voir la carte qu'il a réclamée (pour suivre son statut)
drop policy if exists "Members can view own claimed card" on public.member_cards;
create policy "Members can view own claimed card"
  on public.member_cards for select
  using (auth.uid() = claimed_by);

-- ===== Vue publique : cartes non réclamées, sans le téléphone =====
-- Le téléphone ne doit jamais être exposé côté client : la vérification se
-- fait uniquement côté serveur, dans la fonction claim_member_card ci-dessous.
drop view if exists public.member_cards_unclaimed;
create or replace view public.member_cards_unclaimed as
  select id, full_name, member_since, city
  from public.member_cards
  where claim_status = 'unclaimed' and public.is_approved_member();

grant select on public.member_cards_unclaimed to authenticated;

-- ===== Numéro de carte historique sur le profil =====
-- Une fois la réclamation confirmée, ce numéro remplace le numéro généré
-- automatiquement dans la carte virtuelle (membres/profil.html).
alter table public.profiles add column if not exists legacy_card_number text;

-- ===== Réclamer une carte =====
-- Compare le téléphone saisi (jamais transmis en clair au client avant ça)
-- aux 8 derniers chiffres du téléphone enregistré, pour tolérer les
-- variations d'écriture (espaces, indicatif +221, etc.).
create or replace function public.claim_member_card(card_id uuid, phone_guess text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone  text;
  v_status text;
begin
  if not public.is_approved_member() then
    raise exception 'Accès réservé aux membres approuvés.';
  end if;

  select phone, claim_status into v_phone, v_status
  from public.member_cards
  where id = card_id
  for update;

  if v_phone is null then
    raise exception 'Carte introuvable.';
  end if;

  if v_status <> 'unclaimed' then
    raise exception 'Cette carte a déjà été réclamée par quelqu''un d''autre.';
  end if;

  if right(regexp_replace(v_phone, '\D', '', 'g'), 8) <> right(regexp_replace(phone_guess, '\D', '', 'g'), 8) then
    raise exception 'Le numéro saisi ne correspond pas à cette carte.';
  end if;

  update public.member_cards
     set claimed_by = auth.uid(), claim_status = 'pending', claimed_at = now()
   where id = card_id;
end;
$$;

-- ===== Confirmer une réclamation (admin) =====
-- Recopie le numéro de carte et l'année d'adhésion réels sur le profil.
create or replace function public.confirm_member_card_claim(card_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed_by   uuid;
  v_card_number  text;
  v_member_since int;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select claimed_by, card_number, member_since
    into v_claimed_by, v_card_number, v_member_since
  from public.member_cards
  where id = card_id and claim_status = 'pending';

  if v_claimed_by is null then
    raise exception 'Aucune réclamation en attente pour cette carte.';
  end if;

  update public.member_cards
     set claim_status = 'confirmed', confirmed_at = now()
   where id = card_id;

  update public.profiles
     set legacy_card_number = coalesce(v_card_number, legacy_card_number),
         member_since = coalesce(v_member_since, member_since)
   where id = v_claimed_by;
end;
$$;

-- ===== Refuser une réclamation (admin) =====
-- Remet la carte dans le pool des cartes non réclamées.
create or replace function public.reject_member_card_claim(card_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  update public.member_cards
     set claim_status = 'unclaimed', claimed_by = null, claimed_at = null
   where id = card_id and claim_status = 'pending';
end;
$$;
