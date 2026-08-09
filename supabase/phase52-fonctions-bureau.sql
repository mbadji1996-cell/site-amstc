-- ============================================================
-- PHASE 52 - Fonctions au Bureau Exécutif dans l'espace membres
--
-- Le Bureau et ses huit commissions sont déjà publiés sur l'accueil
-- (content/home-gouvernance.json, géré par le CMS). Ce script relie ces
-- fonctions aux COMPTES de l'espace membres, pour que l'annuaire indique
-- à qui s'adresser - ce que la page publique ne permet pas, faute de
-- contacts affichés.
--
-- Volontairement séparé du CMS : la page publique reste la vitrine, y
-- compris pour les membres du Bureau qui n'ont pas de compte ; ceci n'est
-- qu'un repère dans l'annuaire, posé sur les comptes existants.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

alter table public.profiles add column if not exists fonction   text;
alter table public.profiles add column if not exists commission text;

-- Ces deux colonnes ne sont PAS ouvertes à l'auto-édition : un membre ne
-- se nomme pas lui-même au Bureau. Elles ne figurent donc pas dans le
-- grant de phase8 et passent par la fonction ci-dessous.

-- ===== Attribution (Super Administrateur uniquement) =====
create or replace function public.set_member_fonction(
  target_user_id uuid, new_fonction text, new_commission text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Même exigence que la nomination d'un administrateur : c'est une
  -- prérogative du Super Administrateur.
  if not public.is_super_admin() then
    raise exception 'Accès refusé.';
  end if;

  update public.profiles
     set fonction   = nullif(btrim(coalesce(new_fonction, '')), ''),
         commission = nullif(btrim(coalesce(new_commission, '')), '')
   where id = target_user_id;
end;
$$;

revoke all on function public.set_member_fonction(uuid, text, text) from public;
revoke all on function public.set_member_fonction(uuid, text, text) from anon;
grant execute on function public.set_member_fonction(uuid, text, text) to authenticated;

-- ===== L'annuaire renvoie la fonction =====
-- PostgreSQL n'autorise pas CREATE OR REPLACE à changer les colonnes d'une
-- fonction RETURNS TABLE : il faut la supprimer d'abord (comme en phase46).
drop function if exists public.member_directory(int);

create function public.member_directory(p_limit int default 300)
returns table (
  id            uuid,
  title         text,
  first_name    text,
  last_name     text,
  full_name     text,
  domain        text,
  domain_autre  text,
  specialty     text,
  city          text,
  photo_url     text,
  member_since  int,
  phone         text,
  role          text,
  fonction      text,
  commission    text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_approved_member() then
    raise exception 'Accès réservé aux membres approuvés.';
  end if;

  perform public.check_rate_limit('member_directory', 30, interval '5 minutes');
  return query
    select p.id, p.title, p.first_name, p.last_name, p.full_name,
           p.domain, p.domain_autre, p.specialty, p.city, p.photo_url, p.member_since,
           p.phone, p.role, p.fonction, p.commission
    from public.profiles p
    where p.status = 'approved' and p.is_active
    order by p.last_name nulls last, p.full_name
    limit least(coalesce(p_limit, 300), 500);
end;
$$;

grant execute on function public.member_directory(int) to authenticated;

-- ===== Trace dans le journal (phase51) =====
-- Le déclencheur de phase51 ne surveille pas ces colonnes : une nomination
-- au Bureau mérite pourtant d'être tracée au même titre qu'une promotion
-- au rôle d'administrateur.
create or replace function public.trg_journal_fonction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.fonction is distinct from old.fonction
     or new.commission is distinct from old.commission then
    perform public.journaliser('fonction_modifiee', new.id,
      coalesce(new.full_name, new.email, '(sans nom)'),
      jsonb_build_object(
        'avant', coalesce(old.fonction, '(aucune)') || case when old.commission is not null then ' - ' || old.commission else '' end,
        'apres', coalesce(new.fonction, '(aucune)') || case when new.commission is not null then ' - ' || new.commission else '' end));
  end if;
  return new;
end;
$$;

drop trigger if exists journal_fonction on public.profiles;
create trigger journal_fonction
  after update of fonction, commission on public.profiles
  for each row
  execute function public.trg_journal_fonction();
