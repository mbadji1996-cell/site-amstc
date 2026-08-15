-- ============================================================
-- PHASE 79 - Notifications des PAIEMENTS (et option WhatsApp)
--
-- LE CONSTAT (14/08/2026) : « je ne reçois que les nouvelles
-- inscriptions ». C'est exact, et ce n'est pas un réglage : la phase 25
-- n'avait posé de déclencheur que sur cinq événements - inscription,
-- réclamation de carte, achat boutique, demande de campagne, nouveau
-- sujet du forum. Les PAIEMENTS n'en avaient aucun. Rien n'était donc
-- envoyé, quel que soit l'état de Resend.
--
-- CE SCRIPT AJOUTE trois déclencheurs :
--   - card_validity_payments  -> « paiement_validite »
--   - cotisation_payments     -> « paiement_cotisation »
--   - collecte_participations -> « participation_collecte »
--
-- Ils se déclenchent à la DÉCLARATION du paiement (INSERT), le moment
-- où l'administration doit agir - pas à sa confirmation, qu'elle fait
-- elle-même.
--
-- PRÉREQUIS : phase25 (fonction public.notify_admin et fonction Edge
-- « notify-admin » déployée). Si vous aviez remplacé le jeton
-- « REMPLACEZ_PAR_VOTRE_JETON » dans phase25, il n'y a rien à refaire
-- ici : ce script réutilise public.notify_admin telle qu'elle existe.
--
-- La fonction Edge doit être redéployée pour connaître ces trois
-- nouveaux types (voir supabase/functions/notify-admin/index.ts).
-- Sans redéploiement, l'appel part mais l'e-mail n'est pas construit.
--
--
-- GARDE-FOU IMPORTANT : chaque envoi est enveloppe d'un « exception when
-- others then null ». Un declencheur AFTER INSERT s'execute dans la
-- transaction du membre : sans cette enveloppe, une notification en
-- panne - extension pg_net absente, file saturee, fonction Edge
-- injoignable - ferait ECHOUER la declaration de paiement elle-meme. La
-- notification est utile ; le paiement est essentiel.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Paiement de validité de carte =====
create or replace function public.notify_admin_validity_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom   text;
  v_email text;
begin
  select full_name, email into v_nom, v_email
    from public.profiles where id = new.user_id;

  begin
    perform public.notify_admin('paiement_validite', jsonb_build_object(
      'member_name', coalesce(v_nom, '(sans nom)'),
      'member_email', coalesce(v_email, '-'),
      'years', new.years_requested,
      'amount_fcfa', new.amount_fcfa,
      'payment_method', new.payment_method,
      'payment_reference', new.payment_reference
    ));
  exception when others then
    raise warning 'notify_admin(paiement_validite) a échoué : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_validity_payment_notify_admin on public.card_validity_payments;
create trigger on_validity_payment_notify_admin
  after insert on public.card_validity_payments
  for each row execute function public.notify_admin_validity_payment();

-- ===== 2. Paiement de cotisations =====
create or replace function public.notify_admin_cotisation_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom   text;
  v_email text;
begin
  select full_name, email into v_nom, v_email
    from public.profiles where id = new.user_id;

  begin
    perform public.notify_admin('paiement_cotisation', jsonb_build_object(
      'member_name', coalesce(v_nom, '(sans nom)'),
      'member_email', coalesce(v_email, '-'),
      'year', new.year,
      'months', new.months_requested,
      'amount_fcfa', new.amount_fcfa,
      'payment_method', new.payment_method,
      'payment_reference', new.payment_reference
    ));
  exception when others then
    raise warning 'notify_admin(paiement_cotisation) a échoué : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_cotisation_payment_notify_admin on public.cotisation_payments;
create trigger on_cotisation_payment_notify_admin
  after insert on public.cotisation_payments
  for each row execute function public.notify_admin_cotisation_payment();

-- ===== 3. Participation à une collecte =====
-- La table n'existe que si la phase 55 a été exécutée : le bloc est
-- conditionnel pour que ce script reste exécutable sans elle.
do $$
begin
  if to_regclass('public.collecte_participations') is null then
    raise notice 'collecte_participations absente (phase55 non exécutée) : déclencheur ignoré.';
    return;
  end if;

  execute $f$
    create or replace function public.notify_admin_collecte_participation()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    declare
      v_nom      text;
      v_email    text;
      v_collecte text;
      v_item     text;
    begin
      select full_name, email into v_nom, v_email
        from public.profiles where id = new.user_id;
      select titre into v_collecte
        from public.collectes where id = new.collecte_id;
      if new.item_id is not null then
        select libelle into v_item
          from public.collecte_items where id = new.item_id;
      end if;

      begin
        perform public.notify_admin('participation_collecte', jsonb_build_object(
          'member_name', coalesce(v_nom, '(sans nom)'),
          'member_email', coalesce(v_email, '-'),
          'collecte', coalesce(v_collecte, '-'),
          'item', coalesce(v_item, '-'),
          'mode', new.mode,
          'amount_fcfa', coalesce(new.montant_fcfa, 0),
          'payment_method', coalesce(new.payment_method, '-'),
          'payment_reference', coalesce(new.payment_reference, '-')
        ));
      exception when others then
        raise warning 'notify_admin(participation_collecte) a échoué : %', sqlerrm;
      end;
      return new;
    end;
    $body$;
  $f$;

  execute 'drop trigger if exists on_collecte_participation_notify_admin on public.collecte_participations';
  execute 'create trigger on_collecte_participation_notify_admin
             after insert on public.collecte_participations
             for each row execute function public.notify_admin_collecte_participation()';
end $$;

-- ===== Contrôle : les déclencheurs de notification en place =====
select c.relname as table_surveillee, t.tgname as declencheur
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal
   and t.tgname like '%notify_admin%'
 order by c.relname;
