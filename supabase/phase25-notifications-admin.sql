-- ============================================================
-- PHASE 25 — Notifications e-mail à l'admin (inscription, réclamation de
-- carte, achat boutique, nouveau sujet forum).
--
-- Envoie un e-mail à l'admin (via Resend) à chaque événement clé, en
-- appelant la fonction Edge partagée "notify-admin" au moyen de
-- l'extension pg_net (requêtes HTTP asynchrones et non bloquantes : un
-- échec d'envoi ne fait JAMAIS échouer l'INSERT/UPDATE de l'utilisateur).
--
-- PRÉREQUIS — dans cet ordre :
--   1. La fonction Edge "notify-admin" (supabase/functions/notify-admin/index.ts)
--      doit être déployée AVANT d'exécuter ce fichier.
--   2. Ses secrets doivent être configurés (RESEND_API_KEY,
--      ADMIN_NOTIFY_EMAIL, éventuellement NOTIFY_ADMIN_SECRET / NOTIFY_FROM_EMAIL).
--   3. Si vous utilisez NOTIFY_ADMIN_SECRET, remplacez la valeur
--      "REMPLACEZ_PAR_VOTRE_JETON" ci-dessous par EXACTEMENT le même jeton
--      avant de coller ce fichier dans le SQL Editor.
-- Voir README-espace-membres.md pour le détail des étapes manuelles.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après schema.sql, phase2-roles.sql,
-- phase4-nouveaux-modules.sql, phase5-cartes-membres.sql, phase12-forum.sql,
-- phase24-nouvel-adherent.sql).
-- ============================================================

-- pg_net est une extension gérée par Supabase ; "if not exists" la rend
-- sûre à rejouer même si elle est déjà active sur ce projet (aucun risque
-- d'erreur si elle l'est déjà).
create extension if not exists pg_net;

-- ===== Fonction relais partagée =====
-- SECURITY DEFINER : les triggers ci-dessous s'exécutent avec le rôle de
-- l'utilisateur qui a déclenché l'INSERT/UPDATE (ex. "authenticated"), qui
-- n'a pas forcément accès à net.http_post. En passant par cette fonction
-- définie par le rôle propriétaire (postgres, celui qui exécute ce script
-- dans le SQL Editor), l'appel HTTP fonctionne quel que soit l'appelant —
-- même schéma que public.claim_member_card / public.is_admin ailleurs
-- dans ce projet.
create or replace function public.notify_admin(event_type text, payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://qcdhtynqhpydtqnptvmo.supabase.co/functions/v1/notify-admin',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- ⚠️ Ceci N'EST PAS la clé "anon" (publique) : c'est un jeton dédié,
      -- à générer vous-même (ex. select encode(gen_random_bytes(24), 'hex');)
      -- et à saisir aussi comme secret NOTIFY_ADMIN_SECRET de la fonction
      -- Edge. Si vous préférez la configuration minimale sans ce contrôle,
      -- laissez cette valeur telle quelle et ne définissez simplement pas
      -- le secret NOTIFY_ADMIN_SECRET côté fonction Edge.
      'Authorization', 'Bearer REMPLACEZ_PAR_VOTRE_JETON'
    ),
    body := jsonb_build_object('event_type', event_type) || payload,
    timeout_milliseconds := 5000
  );
exception when others then
  -- Ne jamais faire échouer la transaction appelante à cause d'un souci
  -- réseau/HTTP : on journalise (visible dans Database > Logs) et on continue.
  raise warning 'notify_admin: échec de l''appel HTTP (%): %', event_type, sqlerrm;
end;
$$;

-- ============================================================
-- 1. Inscription — public.profiles, AFTER INSERT
-- ============================================================

create or replace function public.notify_admin_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_admin('inscription', jsonb_build_object(
    'full_name', new.full_name,
    'email', new.email,
    'phone', new.phone,
    'domain', new.domain,
    'domain_autre', new.domain_autre,
    'specialty', new.specialty,
    'city', new.city,
    'applicant_type', new.applicant_type
  ));
  return new;
end;
$$;

drop trigger if exists on_profile_created_notify_admin on public.profiles;
create trigger on_profile_created_notify_admin
  after insert on public.profiles
  for each row execute function public.notify_admin_on_signup();

-- ============================================================
-- 2. Réclamation de carte — public.member_cards, AFTER UPDATE
-- Ne se déclenche qu'au passage à claim_status = 'pending' (pas sur la
-- confirmation admin ultérieure qui passe à 'confirmed', ni sur le refus
-- qui repasse à 'unclaimed').
-- ============================================================

create or replace function public.notify_admin_on_card_claim()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimant_name  text;
  v_claimant_email text;
begin
  if new.claim_status = 'pending' and old.claim_status is distinct from 'pending' then
    select full_name, email into v_claimant_name, v_claimant_email
    from public.profiles where id = new.claimed_by;

    perform public.notify_admin('reclamation_carte', jsonb_build_object(
      'claimant_name', v_claimant_name,
      'claimant_email', v_claimant_email,
      'card_full_name', new.full_name,
      'card_number', new.card_number,
      'card_city', new.city,
      'card_member_since', new.member_since
    ));
  end if;
  return new;
end;
$$;

drop trigger if exists on_card_claim_notify_admin on public.member_cards;
create trigger on_card_claim_notify_admin
  after update on public.member_cards
  for each row execute function public.notify_admin_on_card_claim();

-- ============================================================
-- 3. Achat boutique — public.orders, AFTER INSERT
-- ============================================================

create or replace function public.notify_admin_on_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_name  text;
  v_buyer_email text;
begin
  select full_name, email into v_buyer_name, v_buyer_email
  from public.profiles where id = new.user_id;

  perform public.notify_admin('achat_boutique', jsonb_build_object(
    'buyer_name', v_buyer_name,
    'buyer_email', v_buyer_email,
    'items', new.items,
    'total_fcfa', new.total_fcfa,
    'payment_method', new.payment_method,
    'payment_reference', new.payment_reference
  ));
  return new;
end;
$$;

drop trigger if exists on_order_created_notify_admin on public.orders;
create trigger on_order_created_notify_admin
  after insert on public.orders
  for each row execute function public.notify_admin_on_order();

-- ============================================================
-- 4. Nouveau sujet forum — public.forum_topics, AFTER INSERT
-- ============================================================

create or replace function public.notify_admin_on_forum_topic()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author_name  text;
  v_author_email text;
begin
  select full_name, email into v_author_name, v_author_email
  from public.profiles where id = new.author_id;

  perform public.notify_admin('nouveau_sujet_forum', jsonb_build_object(
    'author_name', v_author_name,
    'author_email', v_author_email,
    'title', new.title,
    'body', new.body
  ));
  return new;
end;
$$;

drop trigger if exists on_forum_topic_created_notify_admin on public.forum_topics;
create trigger on_forum_topic_created_notify_admin
  after insert on public.forum_topics
  for each row execute function public.notify_admin_on_forum_topic();
