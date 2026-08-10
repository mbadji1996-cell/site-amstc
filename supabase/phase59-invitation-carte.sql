-- ============================================================
-- PHASE 59 - Inviter un porteur de carte à créer son compte
--
-- Les cartes importées (member_cards) portent nom, téléphone, numéro et
-- année d'adhésion, mais AUCUNE adresse e-mail : impossible d'y créer un
-- compte d'autorité, Supabase en exigeant une. On inverse donc le sens :
-- l'administration engendre un lien d'invitation, l'envoie par WhatsApp
-- (le téléphone, lui, est connu), et le membre choisit lui-même son
-- adresse et son mot de passe.
--
-- Le compte créé par ce chemin est approuvé d'emblée : la carte prouve
-- déjà la qualité de membre, et le faire valider une seconde fois par
-- l'administration serait redondant.
--
-- Aucun compte fantôme : tant que le lien n'est pas utilisé, rien
-- n'existe. Passé son échéance, il ne vaut plus rien.
--
-- PRÉREQUIS : phase5/phase9 (member_cards) et phase51 (journal).
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create table if not exists public.invitations_carte (
  id          uuid primary key default gen_random_uuid(),
  card_id     uuid not null references public.member_cards(id) on delete cascade,
  jeton       text not null unique,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  expire_le   timestamptz not null default now() + interval '30 days',
  used_at     timestamptz,
  used_by     uuid references public.profiles(id) on delete set null
);

create index if not exists invitations_carte_card_idx on public.invitations_carte (card_id, created_at desc);

alter table public.invitations_carte enable row level security;
grant select on public.invitations_carte to authenticated;

-- L'administration suit l'état des invitations ; personne d'autre ne lit
-- cette table, la consultation par le futur membre passant par la
-- fonction lire_invitation ci-dessous, qui ne renvoie pas le jeton.
drop policy if exists "Admins voient les invitations" on public.invitations_carte;
create policy "Admins voient les invitations"
  on public.invitations_carte for select
  using (public.is_admin());

-- ===== Créer une invitation (administration) =====
create or replace function public.creer_invitation_carte(p_card_id uuid)
returns table (jeton text, full_name text, card_number text, expire_le timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_carte public.member_cards%rowtype;
  v_jeton text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select * into v_carte from public.member_cards where id = p_card_id;
  if v_carte.id is null then
    raise exception 'Carte introuvable.';
  end if;
  if v_carte.claim_status = 'confirmed' then
    raise exception 'Cette carte est déjà rattachée à un compte.';
  end if;

  -- 24 octets : un lien qui circule sur WhatsApp doit être impossible à
  -- deviner, puisqu'il vaut à lui seul autorisation.
  v_jeton := encode(gen_random_bytes(24), 'hex');

  -- Une nouvelle invitation annule les précédentes encore ouvertes : sans
  -- cela, un ancien lien partagé par erreur resterait valable.
  delete from public.invitations_carte
   where card_id = p_card_id and used_at is null;

  insert into public.invitations_carte (card_id, jeton, created_by)
  values (p_card_id, v_jeton, auth.uid());

  perform public.journaliser('invitation_creee', null, v_carte.full_name,
    jsonb_build_object('carte', v_carte.card_number, 'depuis', v_carte.member_since));

  return query
    select v_jeton, v_carte.full_name, v_carte.card_number,
           (now() + interval '30 days')::timestamptz;
end;
$$;

-- ===== Lire une invitation (le futur membre, non connecté) =====
-- Ouverte à anon : la personne invitée n'a pas encore de compte. Elle ne
-- renvoie que ce qui figure déjà sur la carte papier - jamais le
-- téléphone, ni le jeton d'une autre invitation.
create or replace function public.lire_invitation(p_jeton text)
returns table (full_name text, card_number text, member_since int, city text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.invitations_carte%rowtype;
begin
  select * into v_inv from public.invitations_carte where jeton = p_jeton;

  if v_inv.id is null then
    raise exception 'Ce lien d''invitation est inconnu.';
  end if;
  if v_inv.used_at is not null then
    raise exception 'Ce lien a déjà été utilisé pour créer un compte.';
  end if;
  if now() > v_inv.expire_le then
    raise exception 'Ce lien a expiré. Demandez-en un nouveau à l''administration.';
  end if;

  return query
    select c.full_name, c.card_number, c.member_since, c.city
      from public.member_cards c
     where c.id = v_inv.card_id;
end;
$$;

-- ===== Consommer l'invitation (juste après la création du compte) =====
create or replace function public.utiliser_invitation(p_jeton text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.invitations_carte%rowtype;
  v_carte public.member_cards%rowtype;
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

  -- Le compte est approuvé d'emblée, et hérite de l'ancienneté portée par
  -- la carte : c'est tout l'intérêt d'inviter plutôt que de faire
  -- réclamer la carte après coup.
  update public.profiles
     set status             = 'approved',
         legacy_card_number = coalesce(v_carte.card_number, legacy_card_number),
         member_since       = coalesce(v_carte.member_since, member_since),
         city               = coalesce(nullif(btrim(coalesce(city, '')), ''), v_carte.city),
         applicant_type     = coalesce(applicant_type, 'membre_existant')
   where id = auth.uid();

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

revoke all on function public.creer_invitation_carte(uuid) from public, anon;
revoke all on function public.lire_invitation(text) from public;
revoke all on function public.utiliser_invitation(text) from public, anon;

grant execute on function public.creer_invitation_carte(uuid) to authenticated;
grant execute on function public.lire_invitation(text) to anon, authenticated;
grant execute on function public.utiliser_invitation(text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle.
select proname from pg_proc
 where proname in ('creer_invitation_carte','lire_invitation','utiliser_invitation')
 order by proname;
