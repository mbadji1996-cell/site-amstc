-- ============================================================
-- PHASE 84 - Boutons d'action dans les notifications Telegram
--
-- Permet d'approuver une inscription ou de confirmer un paiement en
-- touchant un bouton sous la notification, sans ouvrir le site.
--
-- COMMENT L'AUTORISATION EST RÉSOLUE. Les fonctions d'administration
-- (approve_or_reject_user, confirm_card_validity_payment,
-- confirm_cotisation_payment) exigent « is_admin() », qui lit
-- auth.uid(). Or un clic Telegram n'a aucune session : appelées telles
-- quelles depuis la fonction Edge, elles répondraient « Accès refusé ».
--
-- Plutôt que de RECOPIER leur contenu ici - au risque de perdre un
-- verrou ou une règle, comme le calcul cumulatif de card_valid_until -
-- action_telegram() se contente de RENSEIGNER l'identité d'un
-- administrateur pour la durée de la transaction, puis appelle les
-- fonctions existantes SANS LES MODIFIER. Elles gardent donc
-- exactement leur comportement éprouvé.
--
-- L'action est attribuée, dans le journal, au super-administrateur (à
-- défaut au premier administrateur actif) : c'est lui qui tient le bot.
--
-- OÙ SE SITUE LA SÉCURITÉ. Cette fonction n'est PAS ouverte aux
-- membres : seul le rôle « service_role » peut l'exécuter, c'est-à-dire
-- la fonction Edge. Celle-ci vérifie de son côté deux choses avant
-- d'appeler : le jeton secret que Telegram joint à chaque appel, et que
-- le clic vient bien de VOTRE conversation. Un membre connecté au site
-- ne peut rien en faire.
--
-- PRÉREQUIS : phase2 (approve_or_reject_user), phase7 (paiements),
-- phase79 (notifications de paiement).
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create or replace function public.action_telegram(p_action text, p_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid;
  v_nom   text;
begin
  select id into v_admin
    from public.profiles
   where role in ('admin', 'super_admin')
     and coalesce(is_active, true) is true
   order by case when role = 'super_admin' then 0 else 1 end, created_at
   limit 1;

  if v_admin is null then
    return 'Aucun administrateur actif : action impossible.';
  end if;

  -- Vaut pour la TRANSACTION en cours seulement (troisième argument
  -- « true ») : rien ne subsiste après l'appel.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_admin::text)::text, true);

  case p_action
    -- ===== Inscription =====
    when 'ins:ok' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'approved');
      return 'Inscription approuvée : ' || coalesce(v_nom, '');

    when 'ins:no' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'rejected');
      return 'Inscription refusée : ' || coalesce(v_nom, '');

    -- ===== Paiement de validité de carte =====
    when 'val:ok' then
      if not exists (select 1 from public.card_validity_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      perform public.confirm_card_validity_payment(p_id);
      return 'Paiement de validité confirmé.';

    when 'val:no' then
      update public.card_validity_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      return 'Paiement de validité refusé.';

    -- ===== Paiement de cotisation =====
    when 'cot:ok' then
      if not exists (select 1 from public.cotisation_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      perform public.confirm_cotisation_payment(p_id);
      return 'Paiement de cotisation confirmé.';

    when 'cot:no' then
      update public.cotisation_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      return 'Paiement de cotisation refusé.';

    else
      return 'Action inconnue : ' || coalesce(p_action, '(vide)');
  end case;

exception when others then
  -- Le message remonte tel quel dans Telegram : mieux vaut une phrase
  -- technique qu'un bouton qui ne répond rien.
  return 'Échec : ' || sqlerrm;
end;
$$;

revoke all on function public.action_telegram(text, uuid) from public, anon, authenticated;
grant execute on function public.action_telegram(text, uuid) to service_role;

-- ===== Les notifications doivent porter l'IDENTIFIANT de la ligne =====
-- Sans lui, aucun bouton ne saurait sur quoi agir. On repose donc les
-- trois déclencheurs concernés en ajoutant « id » à leur charge utile ;
-- le reste est identique aux phases 79 et 81.

create or replace function public.notify_admin_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doublon text;
begin
  begin
    select case
             when public.telephone_cle(new.phone) is not null
                  and public.telephone_cle(new.phone) = public.telephone_cle(e.phone)
               then 'même téléphone que ' || coalesce(e.full_name, e.email)
             else 'même nom que ' || coalesce(e.full_name, e.email)
           end
      into v_doublon
      from public.profiles e
     where e.id <> new.id
       and e.status <> 'pending'
       and (
         (public.telephone_cle(new.phone) is not null
          and length(public.telephone_cle(new.phone)) >= 9
          and public.telephone_cle(new.phone) = public.telephone_cle(e.phone))
         or
         (public.nom_cle(new.full_name) is not null
          and length(public.nom_cle(new.full_name)) >= 5
          and public.nom_cle(new.full_name) = public.nom_cle(e.full_name))
       )
     limit 1;
  exception when others then
    v_doublon := null;
  end;

  begin
    perform public.notify_admin('inscription', jsonb_build_object(
      'id', new.id,
      'full_name', new.full_name,
      'email', new.email,
      'phone', new.phone,
      'domain', new.domain,
      'domain_autre', new.domain_autre,
      'specialty', new.specialty,
      'city', new.city,
      'applicant_type', new.applicant_type,
      'doublon', v_doublon
    ));
  exception when others then
    raise warning 'notify_admin(inscription) a échoué : %', sqlerrm;
  end;
  return new;
end;
$$;

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
      'id', new.id,
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
      'id', new.id,
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

-- ===== Contrôle =====
-- Doit renvoyer « Action inconnue » : la fonction répond, et un
-- identifiant fantaisiste ne casse rien.
select public.action_telegram('essai', '00000000-0000-0000-0000-000000000000');
