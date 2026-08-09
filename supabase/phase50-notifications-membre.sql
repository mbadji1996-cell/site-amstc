-- ============================================================
-- PHASE 50 - Notifications AU MEMBRE (approbation, refus, expiration)
--
-- Jusqu'ici, seule l'administration était prévenue (phase25). Le membre,
-- lui, ne savait pas quand son compte devenait actif : il devait réessayer
-- de se connecter au hasard. Ce script le prévient par e-mail.
--
-- Même mécanique que phase25 : pg_net appelle une fonction Edge, de façon
-- asynchrone et non bloquante - un échec d'envoi ne fait JAMAIS échouer la
-- validation faite par l'administrateur.
--
-- PRÉREQUIS :
--   1. La fonction Edge "notify-membre" doit être déployée AVANT
--      d'exécuter ce fichier (voir README-espace-membres.md).
--   2. Elle réutilise les secrets de notify-admin : rien de nouveau à
--      configurer.
--   3. Si vous utilisez NOTIFY_ADMIN_SECRET, remplacez ci-dessous
--      "REMPLACEZ_PAR_VOTRE_JETON" par EXACTEMENT le même jeton - le même
--      que dans phase25-notifications-admin.sql.
--
-- ATTENTION : Resend n'autorise l'envoi vers des adresses quelconques que
-- depuis un domaine vérifié. Tant qu'amstc.org n'est pas vérifié dans
-- Resend, ces e-mails seront refusés (l'application, elle, continuera de
-- fonctionner normalement : l'échec est silencieux et journalisé).
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create extension if not exists pg_net;

-- ===== Relais partagé =====
-- SECURITY DEFINER pour la même raison que public.notify_admin : le trigger
-- s'exécute avec le rôle de l'administrateur connecté (authenticated), qui
-- n'a pas accès à net.http_post.
create or replace function public.notify_membre(p_event_type text, p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://api.amstc.org/functions/v1/notify-membre',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer REMPLACEZ_PAR_VOTRE_JETON'
    ),
    body := jsonb_build_object('event_type', p_event_type) || p_payload,
    timeout_milliseconds := 5000
  );
exception when others then
  -- Un souci réseau ne doit jamais empêcher un administrateur de valider
  -- un compte : on journalise (Database > Logs) et on continue.
  raise warning 'notify_membre(%) a échoué : %', p_event_type, sqlerrm;
end;
$$;

-- ===== Trigger : changement de statut du compte =====
create or replace function public.trg_profil_statut_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Uniquement sur un VRAI changement de statut : un simple enregistrement
  -- du profil (photo, téléphone…) ne doit pas renvoyer l'e-mail de
  -- bienvenue à chaque fois.
  if new.status is distinct from old.status then
    if new.status = 'approved' then
      perform public.notify_membre('compte_approuve', jsonb_build_object(
        'email', new.email,
        'full_name', new.full_name,
        'first_name', new.first_name
      ));
    elsif new.status = 'rejected' then
      perform public.notify_membre('compte_refuse', jsonb_build_object(
        'email', new.email,
        'full_name', new.full_name,
        'first_name', new.first_name
      ));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profil_statut_change on public.profiles;
create trigger profil_statut_change
  after update of status on public.profiles
  for each row
  execute function public.trg_profil_statut_change();

-- ============================================================
-- Rappels d'expiration de carte (phase 21 de la feuille de route)
--
-- Fonction à appeler une fois par jour (voir README-espace-membres.md,
-- section Rappels). Elle prévient chaque membre approuvé dont la carte
-- expire à la fin de l'année en cours, et n'écrit qu'UNE FOIS par année
-- de validité grâce à la table de traçage ci-dessous.
-- ============================================================

create table if not exists public.rappels_carte_envoyes (
  user_id           uuid not null references public.profiles(id) on delete cascade,
  card_valid_until  int  not null,
  envoye_le         timestamptz not null default now(),
  primary key (user_id, card_valid_until)
);

alter table public.rappels_carte_envoyes enable row level security;
-- Aucune policy : table de service, lue et écrite uniquement par la
-- fonction SECURITY DEFINER ci-dessous. Personne n'y accède depuis le site.

create or replace function public.envoyer_rappels_cartes(p_jours_avant int default 45)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membre record;
  v_envoyes int := 0;
  v_annee int := extract(year from now())::int;
begin
  -- Réservé à un appel de service (tâche planifiée) ou à un admin : cette
  -- fonction déclenche des envois en masse.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  for v_membre in
    select p.id, p.email, p.full_name, p.first_name, p.card_valid_until
      from public.profiles p
     where p.status = 'approved'
       and p.is_active is not false
       and p.card_valid_until = v_annee
       and p.email is not null
       -- L'échéance est le 31 décembre de card_valid_until : on prévient
       -- p_jours_avant en amont.
       and now() >= (make_date(v_annee, 12, 31) - (p_jours_avant || ' days')::interval)
       and not exists (
         select 1 from public.rappels_carte_envoyes r
          where r.user_id = p.id and r.card_valid_until = p.card_valid_until
       )
  loop
    perform public.notify_membre('carte_expire_bientot', jsonb_build_object(
      'email', v_membre.email,
      'full_name', v_membre.full_name,
      'first_name', v_membre.first_name,
      'card_valid_until', v_membre.card_valid_until
    ));
    insert into public.rappels_carte_envoyes (user_id, card_valid_until)
      values (v_membre.id, v_membre.card_valid_until)
      on conflict do nothing;
    v_envoyes := v_envoyes + 1;
  end loop;

  return v_envoyes;
end;
$$;

grant execute on function public.envoyer_rappels_cartes(int) to authenticated;
