-- ============================================================
-- PHASE 81 - Point du jour + alerte de doublon à l'inscription
--
-- DEUX APPORTS.
--
-- 1. public.rapport_matinal() : un bilan quotidien de tout ce qui
--    attend l'administration - inscriptions, paiements, commandes,
--    réclamations de carte, demandes de campagne, doublons probables.
--    Appelée par le cron à 8 h, elle part sur les mêmes canaux que les
--    autres notifications (e-mail, Telegram, WhatsApp si configuré).
--
--    Par défaut elle NE DIT RIEN quand il n'y a rien à traiter : une
--    notification quotidienne vide finit par être ignorée, et c'est
--    alors la vraie qui passe inaperçue. Le silence signifie « rien à
--    faire ». Pour un bilan systématique, appelez rapport_matinal(true).
--
-- 2. Le déclencheur d'inscription porte désormais l'alerte de doublon
--    de la phase 78 : la notification dit elle-même « même téléphone
--    que X », au lieu de laisser découvrir le doublon sur l'écran.
--
-- ROBUSTESSE. Chaque compteur est isolé par to_regclass : une table
-- absente (phase non exécutée sur cette instance) est ignorée, elle ne
-- fait pas échouer le rapport entier.
--
-- PRÉREQUIS : phase25 (notify_admin). La phase 78 est facultative -
-- sans elle, le compteur de doublons vaut simplement zéro.
--
-- La fonction Edge doit être redéployée pour connaître le type
-- « rapport_matinal ». Sans cela, un message générique part quand même
-- (la fonction ne rejette plus les types inconnus), mais sans mise en
-- forme.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Le point du jour =====
create or replace function public.rapport_matinal(p_toujours boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lignes jsonb := '[]'::jsonb;
  v_total  int := 0;
  v_n      int;

-- Les lignes à zéro sont CONSERVÉES dans le rapport : la fonction Edge
-- les filtre pour l'affichage, et les garder permet de contrôler le
-- rapport à la main sans se demander si un compteur a été oublié ou
-- vaut réellement zéro.
begin
  -- Inscriptions en attente
  select count(*) into v_n from public.profiles where status = 'pending';
  v_lignes := v_lignes || jsonb_build_object('libelle', 'inscription(s) en attente', 'nombre', v_n);
  v_total := v_total + v_n;

  -- Paiements de validité de carte à confirmer
  if to_regclass('public.card_validity_payments') is not null then
    select count(*) into v_n from public.card_validity_payments where status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de validité à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Paiements de cotisation à confirmer
  if to_regclass('public.cotisation_payments') is not null then
    select count(*) into v_n from public.cotisation_payments where status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de cotisation à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Participations à une collecte à confirmer
  if to_regclass('public.collecte_participations') is not null then
    select count(*) into v_n from public.collecte_participations where status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'participation(s) à une collecte à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Commandes de la boutique à traiter (tout sauf expédiée et annulée)
  if to_regclass('public.orders') is not null then
    select count(*) into v_n from public.orders
     where status in ('pending', 'paid', 'processing');
    v_lignes := v_lignes || jsonb_build_object('libelle', 'commande(s) boutique à traiter', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Réclamations de carte à confirmer
  if to_regclass('public.member_cards') is not null then
    select count(*) into v_n from public.member_cards where claim_status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'réclamation(s) de carte à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Demandes de campagne à étudier
  if to_regclass('public.campaign_requests') is not null then
    select count(*) into v_n from public.campaign_requests where status = 'en_attente';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'demande(s) de campagne à étudier', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Doublons probables parmi les inscriptions en attente (phase 78).
  -- Le bloc est protégé : la fonction filtre sur is_admin(), or le cron
  -- s'exécute sans utilisateur connecté. On refait donc le calcul ici.
  if to_regproc('public.nom_cle') is not null then
    select count(distinct a.id) into v_n
      from public.profiles a
      join public.profiles e
        on e.id <> a.id and e.status <> 'pending'
       and (
         (public.telephone_cle(a.phone) is not null
          and length(public.telephone_cle(a.phone)) >= 9
          and public.telephone_cle(a.phone) = public.telephone_cle(e.phone))
         or
         (public.nom_cle(a.full_name) is not null
          and length(public.nom_cle(a.full_name)) >= 5
          and public.nom_cle(a.full_name) = public.nom_cle(e.full_name))
       )
     where a.status = 'pending';
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object(
        'libelle', 'inscription(s) en attente ressemblant à un compte existant', 'nombre', v_n);
      -- PAS compté dans le total : ces inscriptions figurent déjà dans
      -- le premier compteur, les additionner gonflerait le bilan.
    end if;
  end if;

  -- Rien à traiter : on se tait, sauf demande explicite.
  if v_total = 0 and not p_toujours then
    return jsonb_build_object('envoye', false, 'total', 0, 'lignes', v_lignes);
  end if;

  -- Un envoi en panne ne doit pas faire échouer le cron : il ferait
  -- alors croire à une panne de la base.
  begin
    perform public.notify_admin('rapport_matinal', jsonb_build_object('lignes', v_lignes));
  exception when others then
    raise warning 'rapport_matinal : envoi échoué : %', sqlerrm;
    return jsonb_build_object('envoye', false, 'erreur', sqlerrm, 'lignes', v_lignes);
  end;

  return jsonb_build_object('envoye', true, 'total', v_total, 'lignes', v_lignes);
end;
$$;

revoke all on function public.rapport_matinal(boolean) from public, anon;
grant execute on function public.rapport_matinal(boolean) to authenticated;

-- ===== 2. L'inscription signale son doublon probable =====
create or replace function public.notify_admin_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doublon text;
begin
  -- Recherche d'un compte existant qui partage le téléphone ou le nom.
  -- Le bloc est protégé : la phase 78 est facultative, et son absence ne
  -- doit pas empêcher la notification d'inscription de partir.
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
    -- Même principe que la phase 79 : la notification ne doit jamais
    -- empêcher quelqu'un de s'inscrire.
    raise warning 'notify_admin(inscription) a échoué : %', sqlerrm;
  end;
  return new;
end;
$$;

-- Le déclencheur lui-même n'a pas changé : on le repose par sécurité,
-- au cas où il aurait été retiré.
drop trigger if exists on_profile_created_notify_admin on public.profiles;
create trigger on_profile_created_notify_admin
  after insert on public.profiles
  for each row execute function public.notify_admin_on_signup();

-- ===== 3. Contrôle - le rapport, sans rien envoyer =====
-- Renvoie le detail des compteurs. « envoye: false » avec un total à 0
-- signifie simplement qu'il n'y avait rien à signaler.
select jsonb_pretty(public.rapport_matinal(false));
