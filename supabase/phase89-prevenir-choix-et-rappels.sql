-- ============================================================
-- PHASE 89 - Prévenir : choisir le message ; et trois rappels
-- qui partent tout seuls
--
-- CE QUE CETTE PHASE APPORTE.
--
-- 1. LE BOUTON « PRÉVENIR » DEVIENT UN MENU. Jusqu'ici il n'envoyait
--    qu'un seul message (« compte activé »). Il propose désormais les
--    CINQ mêmes choix que l'écran Validation du site, dans le même
--    ordre et sous les mêmes intitulés :
--       Carte expirée · Carte à renouveler bientôt · Cotisations en
--       retard · Compte activé, se connecter · Message libre
--    plus le rappel de paiement de la phase 88. Le texte est le même
--    quel que soit l'endroit d'où on écrit.
--
--    Le « message libre » se saisit dans Telegram : le bot demande le
--    texte, l'administrateur répond, et le lien WhatsApp se construit
--    avec ce qu'il a écrit.
--
-- 2. TROIS RAPPELS PLANIFIÉS, qui n'attendent plus qu'on y pense :
--       - les cotisations du mois, aux membres qui ont rattaché
--         leur Telegram (la fonction existait depuis la phase 85 mais
--         n'était appelée par personne) ;
--       - l'échéance de la carte, un mois avant la fin de validité,
--         et le rappel aux cartes déjà expirées ;
--       - les dossiers oubliés : ce qui attend l'administration
--         depuis plus de 48 heures. Le rapport matinal dit ce qui est
--         ARRIVÉ ; celui-ci dit ce qui TRAÎNE.
--    Le rapport matinal de la phase 81, jamais planifié lui non plus,
--    est mis en place par la même occasion.
--
-- LE SILENCE VAUT « RIEN À FAIRE ». Aucun de ces envois ne part quand
-- il n'y a rien à dire : une alerte qui arrive tous les jours pour ne
-- rien annoncer finit par être ignorée, et c'est alors la vraie qui
-- passe inaperçue.
--
-- CHAQUE DESTINATAIRE N'EST PRÉVENU QU'UNE FOIS : deux tables de
-- mémoire (rappels_cotisation_envoyes, alertes_carte_envoyees)
-- empêchent qu'un cron relancé deux fois harcèle les membres.
--
-- PRÉREQUIS : phases 85 et 88.
-- La fonction Edge notify-admin doit être redéployée pour mettre en
-- forme les deux nouveaux événements ; sans cela un message générique
-- part quand même.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. LES TEXTES - les six messages, identiques à ceux du site
-- ============================================================
-- La signature change (un troisième paramètre pour le message libre) :
-- « create or replace » créerait une SURCHARGE, et l'appel à deux
-- arguments deviendrait ambigu. On retire donc l'ancienne d'abord.
drop function if exists public.texte_whatsapp_membre(uuid, text);

create or replace function public.texte_whatsapp_membre(
  p_user_id uuid, p_type text, p_message text default null
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_m      record;
  v_prenom text;
  v_bloc   text;
  v_annee  int := extract(year from now())::int;
  v_nb     int;
  v_bonjour text;
begin
  select first_name, full_name, card_valid_until, legacy_card_number
    into v_m from public.profiles where id = p_user_id;
  v_prenom := nullif(btrim(coalesce(v_m.first_name,
                split_part(btrim(coalesce(v_m.full_name, '')), ' ', 1))), '');
  v_bonjour := case when v_prenom is null then 'Bonjour,' else 'Bonjour ' || v_prenom || ',' end;

  -- Bloc adhésion : recopié de membres/validation.html (blocAdhesion) -
  -- si les montants ou numéros changent, changer AUX DEUX ENDROITS.
  v_bloc := '1. Carte de membre (obligatoire) : *2 000 F*, valable 2 ans.' || chr(10)
         || '2. Cotisation annuelle : *12 000 F* (1 000 F/mois), payable en plusieurs tranches.' || chr(10) || chr(10)
         || '*Règlement à la Commission finances :*' || chr(10)
         || 'Wave : 78 828 32 16' || chr(10)
         || 'Orange Money : 78 867 96 23' || chr(10) || chr(10)
         || 'Une fois le paiement effectué, *envoyez-moi la capture d''écran de la transaction ici, '
         || 'sur WhatsApp* : elle sert de justificatif pour valider votre adhésion.';

  -- Les textes reprennent MOT POUR MOT texte_rappel_membre (phase 65),
  -- que l'écran Validation utilise. Si l'un change, changer l'autre :
  -- un membre relancé deux fois par deux canaux doit lire la même chose.
  if p_type = 'compte_active' then
    return v_bonjour || chr(10) || chr(10)
        || '*Votre compte AMSTC est activé*' || chr(10) || chr(10)
        || 'Votre compte a été validé par l''administration : l''espace membres vous est désormais ouvert.'
        || chr(10) || chr(10)
        || 'Connectez-vous dès maintenant avec l''adresse e-mail de votre inscription. Vous y trouverez '
        || 'votre carte de membre, les formations, l''annuaire et les documents de l''association.'
        || chr(10) || chr(10)
        || 'Si vous avez oublié votre mot de passe, utilisez « Mot de passe oublié ? » sur la page de connexion.'
        || chr(10) || chr(10)
        || 'Espace membres > Se connecter' || chr(10)
        || 'https://amstc.org/membres/connexion.html'
        || chr(10) || chr(10) || '©AMSTC';

  elsif p_type = 'rappel_paiement' then
    return v_bonjour || chr(10) || chr(10)
        || 'Petit rappel pour finaliser votre adhésion à l''AMSTC :' || chr(10) || chr(10)
        || v_bloc || chr(10) || chr(10)
        || 'Merci !'
        || chr(10) || chr(10) || '©AMSTC';

  elsif p_type = 'carte_expiree' then
    return v_bonjour || chr(10) || chr(10)
        || '*Votre carte de membre AMSTC a expiré*' || chr(10) || chr(10)
        || 'Votre carte de membre '
        || coalesce('(' || v_m.legacy_card_number || ') ', '')
        || case when v_m.card_valid_until is null
                then 'n''a pas encore été réglée.'
                else 'a expiré à la fin de l''année ' || v_m.card_valid_until || '.' end
        || chr(10) || chr(10)
        || 'Merci de la renouveler pour continuer à bénéficier de l''accès aux contenus réservés.'
        || chr(10) || chr(10)
        || 'Espace membres > Carte de membre et Cotisations > Validité de la carte' || chr(10)
        || 'https://amstc.org/membres/profil.html?open=validity'
        || chr(10) || chr(10) || '©AMSTC';

  elsif p_type = 'carte_expire_bientot' then
    return v_bonjour || chr(10) || chr(10)
        || '*Votre carte de membre expire fin ' || coalesce(v_m.card_valid_until, v_annee) || '*'
        || chr(10) || chr(10)
        || 'Votre carte de membre est valable jusqu''à la fin de l''année '
        || coalesce(v_m.card_valid_until, v_annee) || '.'
        || chr(10) || chr(10)
        || 'Pensez à la renouveler pour ne pas interrompre votre accès.'
        || chr(10) || chr(10)
        || 'Espace membres > Carte de membre et Cotisations > Validité de la carte' || chr(10)
        || 'https://amstc.org/membres/profil.html?open=validity'
        || chr(10) || chr(10) || '©AMSTC';

  elsif p_type = 'cotisation_retard' then
    -- Le nombre de mois réglés est ajouté au texte du site : « 3/12 »
    -- répond d'avance à la question que le membre pose toujours.
    select coalesce(array_length(months_paid, 1), 0) into v_nb
      from public.cotisations where user_id = p_user_id and year = v_annee;
    v_nb := coalesce(v_nb, 0);
    return v_bonjour || chr(10) || chr(10)
        || '*Cotisations mensuelles AMSTC*' || chr(10) || chr(10)
        || 'Vos cotisations mensuelles de l''année ' || v_annee || ' ne sont pas à jour ('
        || v_nb || '/12 mois réglés).'
        || chr(10) || chr(10)
        || 'Vous pouvez les régler à tout moment par Wave ou Orange Money, puis déclarer '
        || 'la référence de la transaction.'
        || chr(10) || chr(10)
        || 'Espace membres > Carte de membre et Cotisations > Cotisations mensuelles' || chr(10)
        || 'https://amstc.org/membres/profil.html?open=cotis'
        || chr(10) || chr(10) || '©AMSTC';

  elsif p_type = 'libre' then
    -- Un message vide produirait un lien WhatsApp qui n'ouvre rien :
    -- on renvoie null, et l'appelant sait le dire.
    if btrim(coalesce(p_message, '')) = '' then return null; end if;
    return v_bonjour || chr(10) || chr(10)
        || btrim(p_message)
        || chr(10) || chr(10) || '©AMSTC';
  end if;

  return null;
end;
$$;

revoke all on function public.texte_whatsapp_membre(uuid, text, text) from public, anon, authenticated;
grant execute on function public.texte_whatsapp_membre(uuid, text, text) to service_role;

-- ============================================================
-- 2. CE QUE LA FONCTION EDGE DOIT SAVOIR POUR PRÉVENIR
-- ============================================================
-- Inchangée quant au principe (phase 88) : elle N'ENVOIE RIEN, elle
-- renvoie le numéro normalisé et le texte prêt. Seul le message libre
-- s'ajoute, d'où le troisième paramètre.
drop function if exists public.preparer_prevenir_membre(uuid, text);

create or replace function public.preparer_prevenir_membre(
  p_user_id uuid, p_type text, p_message text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_m      record;
  v_digits text;
  v_texte  text;
begin
  select id, status, applicant_type, phone, email, full_name, first_name, telegram_chat_id
    into v_m from public.profiles where id = p_user_id;
  if v_m.id is null then
    return jsonb_build_object('ok', false, 'motif', 'Ce compte n''existe plus.');
  end if;
  if v_m.status <> 'approved' then
    return jsonb_build_object('ok', false,
      'motif', 'Ce compte n''est pas (ou plus) approuvé : approuvez-le d''abord.');
  end if;

  v_texte := public.texte_whatsapp_membre(p_user_id, p_type, p_message);
  if v_texte is null then
    return jsonb_build_object('ok', false,
      'motif', case when p_type = 'libre' then 'Le message est vide.'
                    else 'Type de message inconnu : ' || coalesce(p_type, '') end);
  end if;

  -- Même normalisation que lienWhatsApp() sur le site.
  v_digits := regexp_replace(coalesce(v_m.phone, ''), '\D', '', 'g');
  if v_digits like '00%' then v_digits := substr(v_digits, 3); end if;
  if length(v_digits) between 1 and 9 then v_digits := '221' || v_digits; end if;
  if length(v_digits) < 9 then v_digits := null; end if;

  return jsonb_build_object(
    'ok', true,
    'nom', coalesce(v_m.first_name, v_m.full_name, ''),
    'whatsapp', v_digits,
    'telegram', v_m.telegram_chat_id,
    'email', nullif(btrim(coalesce(v_m.email, '')), ''),
    'texte', v_texte,
    'nouvel_adherent', coalesce(v_m.applicant_type = 'nouvel_adherent', false)
  );
end;
$$;

revoke all on function public.preparer_prevenir_membre(uuid, text, text) from public, anon, authenticated;
grant execute on function public.preparer_prevenir_membre(uuid, text, text) to service_role;

-- ============================================================
-- 3. REPLI : Telegram ou e-mail quand le membre n'a pas de WhatsApp
-- ============================================================
drop function if exists public.prevenir_membre_repli(uuid, text);

create or replace function public.prevenir_membre_repli(
  p_user_id uuid, p_type text, p_message text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m     record;
  v_texte text;
begin
  select id, email, full_name, first_name, telegram_chat_id
    into v_m from public.profiles where id = p_user_id and status = 'approved';
  if v_m.id is null then return 'Ce compte n''est pas approuvé.'; end if;

  v_texte := public.texte_whatsapp_membre(p_user_id, p_type, p_message);
  if v_texte is null then return 'Message vide ou type inconnu.'; end if;

  if v_m.telegram_chat_id is not null then
    perform public.notify_admin('message_telegram', jsonb_build_object(
      'chat_id', v_m.telegram_chat_id, 'texte', v_texte));
    perform public.journaliser('rappel_envoye', p_user_id,
      coalesce(v_m.full_name, v_m.email, '(sans nom)'),
      jsonb_build_object('type', p_type, 'canal', 'telegram', 'depuis', 'bouton telegram'));
    return 'Pas de WhatsApp : membre prévenu sur Telegram (' || coalesce(v_m.first_name, v_m.full_name, '') || ').';
  end if;

  if coalesce(btrim(v_m.email), '') <> '' then
    perform public.notify_membre('rappel_admin', jsonb_build_object(
      'email', v_m.email, 'full_name', v_m.full_name, 'first_name', v_m.first_name,
      'titre', case p_type
                 when 'rappel_paiement'      then 'Finaliser votre adhésion à l''AMSTC'
                 when 'carte_expiree'        then 'Votre carte de membre AMSTC a expiré'
                 when 'carte_expire_bientot' then 'Votre carte de membre AMSTC expire bientôt'
                 when 'cotisation_retard'    then 'Cotisations mensuelles AMSTC'
                 when 'libre'                then 'Message de l''AMSTC'
                 else 'Votre compte AMSTC est activé' end,
      'corps', v_texte));
    perform public.journaliser('rappel_envoye', p_user_id,
      coalesce(v_m.full_name, v_m.email, '(sans nom)'),
      jsonb_build_object('type', p_type, 'canal', 'email', 'depuis', 'bouton telegram'));
    return 'Pas de WhatsApp : membre prévenu par e-mail (' || coalesce(v_m.first_name, v_m.full_name, '') || ').';
  end if;

  return 'Ni WhatsApp, ni Telegram, ni e-mail pour ce membre : impossible de le prévenir d''ici.';
end;
$$;

revoke all on function public.prevenir_membre_repli(uuid, text, text) from public, anon, authenticated;
grant execute on function public.prevenir_membre_repli(uuid, text, text) to service_role;

-- ============================================================
-- 4. LE NOM DU MEMBRE, pour le titre du menu
-- ============================================================
-- Le menu annonce sur QUI il porte : sans cela, deux notifications
-- traitées coup sur coup se confondent.
create or replace function public.nom_membre(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(first_name, full_name, email, '') from public.profiles where id = p_user_id;
$$;

revoke all on function public.nom_membre(uuid) from public, anon, authenticated;
grant execute on function public.nom_membre(uuid) to service_role;

-- ============================================================
-- 5. ALERTE D'ÉCHÉANCE DE CARTE
-- ============================================================
create table if not exists public.alertes_carte_envoyees (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  annee     int  not null,
  type      text not null,          -- 'bientot' ou 'expiree'
  envoye_le timestamptz not null default now(),
  primary key (user_id, annee, type)
);

-- Prévient les membres RATTACHÉS à Telegram, et signale à
-- l'administration ceux qu'il faudra relancer à la main - ce sont
-- précisément ceux que le canal automatique ne touche pas.
--
-- p_mois_avant : à partir de quel mois on prévient d'une carte qui
-- expire à la fin de l'année en cours. 11 = novembre, soit deux mois.
create or replace function public.alerter_cartes_echeance(p_mois_avant int default 11)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_annee   int := extract(year from now())::int;
  v_mois    int := extract(month from now())::int;
  v_membre  record;
  v_type    text;
  v_prevenus int := 0;
  v_manuel   int := 0;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  for v_membre in
    select p.id, p.telegram_chat_id, p.card_valid_until,
           coalesce(p.full_name, p.email, '(sans nom)') as nom
      from public.profiles p
     where p.status = 'approved'
       and coalesce(p.is_active, true) is true
       and p.card_valid_until is not null
       and (p.card_valid_until < v_annee
            or (p.card_valid_until = v_annee and v_mois >= p_mois_avant))
  loop
    v_type := case when v_membre.card_valid_until < v_annee then 'expiree' else 'bientot' end;

    -- Déjà prévenu cette année pour ce motif : on n'insiste pas.
    if exists (select 1 from public.alertes_carte_envoyees a
                where a.user_id = v_membre.id and a.annee = v_annee and a.type = v_type) then
      continue;
    end if;

    if v_membre.telegram_chat_id is null then
      -- Pas de Telegram : c'est à l'administration de l'appeler.
      v_manuel := v_manuel + 1;
      continue;
    end if;

    begin
      perform public.notify_admin('message_telegram', jsonb_build_object(
        'chat_id', v_membre.telegram_chat_id,
        'texte', public.texte_whatsapp_membre(v_membre.id,
                   case v_type when 'expiree' then 'carte_expiree' else 'carte_expire_bientot' end)));
      insert into public.alertes_carte_envoyees (user_id, annee, type)
        values (v_membre.id, v_annee, v_type) on conflict do nothing;
      v_prevenus := v_prevenus + 1;
    exception when others then
      -- Un envoi raté ne fait pas échouer les suivants, et n'est PAS
      -- mémorisé : il sera retenté au passage suivant.
      raise warning 'alerte carte à % : %', v_membre.id, sqlerrm;
    end;
  end loop;

  -- Le point à l'administration, seulement s'il y a quelque chose.
  if v_prevenus > 0 or v_manuel > 0 then
    begin
      perform public.notify_admin('cartes_echeance', jsonb_build_object(
        'prevenus', v_prevenus, 'a_relancer', v_manuel, 'annee', v_annee));
    exception when others then
      raise warning 'alerter_cartes_echeance : notification échouée : %', sqlerrm;
    end;
  end if;

  return jsonb_build_object('prevenus', v_prevenus, 'a_relancer', v_manuel, 'annee', v_annee);
end;
$$;

revoke all on function public.alerter_cartes_echeance(int) from public, anon;
grant execute on function public.alerter_cartes_echeance(int) to authenticated;

-- ============================================================
-- 6. LES DOSSIERS OUBLIÉS
-- ============================================================
-- Le rapport matinal compte TOUT ce qui attend ; celui-ci ne compte que
-- ce qui attend DEPUIS LONGTEMPS. C'est la différence entre « voici la
-- journée » et « attention, on a laissé passer quelque chose ».
--
-- Chaque compteur est isolé dans son propre bloc : une table absente ou
-- dépourvue de created_at est ignorée, elle ne fait pas échouer le
-- reste.
create or replace function public.relancer_dossiers_en_attente(p_heures int default 48)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lignes jsonb := '[]'::jsonb;
  v_total  int := 0;
  v_n      int;
  v_seuil  timestamptz := now() - make_interval(hours => greatest(coalesce(p_heures, 48), 1));
begin
  begin
    select count(*) into v_n from public.profiles
     where status = 'pending' and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'inscription(s) en attente', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  begin
    select count(*) into v_n from public.card_validity_payments
     where status = 'pending' and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de validité à confirmer', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  begin
    select count(*) into v_n from public.cotisation_payments
     where status = 'pending' and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de cotisation à confirmer', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  begin
    select count(*) into v_n from public.collecte_participations
     where status = 'pending' and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'participation(s) à une collecte à confirmer', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  begin
    select count(*) into v_n from public.orders
     where status in ('pending', 'paid', 'processing') and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'commande(s) boutique à traiter', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  begin
    select count(*) into v_n from public.member_cards
     where claim_status = 'pending' and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'réclamation(s) de carte à confirmer', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  begin
    select count(*) into v_n from public.campaign_requests
     where status = 'en_attente' and created_at < v_seuil;
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object('libelle', 'demande(s) de campagne à étudier', 'nombre', v_n);
      v_total := v_total + v_n;
    end if;
  exception when others then null;
  end;

  -- Rien d'ancien : on se tait.
  if v_total = 0 then
    return jsonb_build_object('envoye', false, 'total', 0, 'heures', p_heures);
  end if;

  begin
    perform public.notify_admin('dossiers_oublies', jsonb_build_object(
      'heures', p_heures, 'lignes', v_lignes));
  exception when others then
    raise warning 'relancer_dossiers_en_attente : envoi échoué : %', sqlerrm;
    return jsonb_build_object('envoye', false, 'erreur', sqlerrm, 'lignes', v_lignes);
  end;

  return jsonb_build_object('envoye', true, 'total', v_total, 'heures', p_heures, 'lignes', v_lignes);
end;
$$;

revoke all on function public.relancer_dossiers_en_attente(int) from public, anon;
grant execute on function public.relancer_dossiers_en_attente(int) to authenticated;

-- ============================================================
-- 7. LA PLANIFICATION
-- ============================================================
-- pg_cron fait partie de l'image Supabase, mais il doit être chargé au
-- démarrage du serveur (shared_preload_libraries). S'il ne l'est pas,
-- la création de l'extension échoue - et ce script ne doit pas
-- s'interrompre pour autant : tout ce qui précède reste valable, et le
-- contrôle en fin de fichier le dira clairement.
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise warning 'pg_cron indisponible (%). Les fonctions sont en place, '
    'mais rien ne les appellera : planifiez-les autrement.', sqlerrm;
end;
$$;

-- Les heures sont en UTC, ce qui correspond à l'heure de Dakar.
do $$
declare
  v_jobs text[][] := array[
    -- nom                        planification    commande
    ['amstc-rapport-matinal',     '0 8 * * *',     'select public.rapport_matinal(false);'],
    ['amstc-dossiers-oublies',    '30 8 * * 1',    'select public.relancer_dossiers_en_attente(48);'],
    ['amstc-rappels-cotisations', '0 9 5 * *',     'select public.envoyer_rappels_cotisations_telegram();'],
    ['amstc-cartes-echeance',     '0 9 1 * *',     'select public.alerter_cartes_echeance(11);']
  ];
  v_i int;
begin
  -- to_regprocedure, pas to_regproc : cron.schedule existe en deux
  -- versions (deux et trois arguments), et to_regproc refuse un nom
  -- ambigu. Les deux renvoient null - sans lever d'erreur - quand le
  -- schéma lui-même n'existe pas.
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise warning 'cron.schedule introuvable : planification ignorée.';
    return;
  end if;

  for v_i in 1 .. array_length(v_jobs, 1) loop
    -- On retire d'abord : cron.schedule remplace bien une tâche de même
    -- nom, mais un ancien nom laissé en place ferait doublon.
    begin
      perform cron.unschedule(v_jobs[v_i][1]);
    exception when others then null;
    end;
    perform cron.schedule(v_jobs[v_i][1], v_jobs[v_i][2], v_jobs[v_i][3]);
  end loop;
end;
$$;

notify pgrst, 'reload schema';

-- ============================================================
-- 8. CONTRÔLES
-- ============================================================
-- a) Les six messages se construisent. Sur un membre approuvé au hasard.
select t.type,
       left(public.texte_whatsapp_membre(
         (select id from public.profiles where status = 'approved' limit 1),
         t.type,
         case when t.type = 'libre' then 'Réunion samedi à 10 h au siège.' end), 70) as apercu
  from (values ('carte_expiree'), ('carte_expire_bientot'), ('cotisation_retard'),
               ('compte_active'), ('rappel_paiement'), ('libre')) as t(type);

-- b) Les tâches planifiées. Quatre lignes attendues dans les messages.
--    Le bloc est protégé : sans pg_cron, « select … from cron.job »
--    lèverait une erreur qui annulerait TOUT le script - fonctions
--    comprises - puisque l'éditeur SQL exécute le fichier d'un bloc.
do $$
declare v_j record; v_n int := 0;
begin
  if to_regclass('cron.job') is null then
    raise notice 'pg_cron absent : les quatre fonctions sont en place mais RIEN NE LES APPELLE.';
    return;
  end if;
  for v_j in select jobname, schedule, active from cron.job
              where jobname like 'amstc-%' order by jobname loop
    raise notice 'tâche % : % (active : %)', v_j.jobname, v_j.schedule, v_j.active;
    v_n := v_n + 1;
  end loop;
  raise notice '% tâche(s) planifiée(s) - quatre attendues.', v_n;
end;
$$;

-- c) Ce que les rappels enverraient AUJOURD'HUI, sans rien envoyer.
select (select count(*) from public.profiles
         where status = 'approved' and coalesce(is_active, true)
           and card_valid_until is not null
           and card_valid_until < extract(year from now())::int) as cartes_expirees,
       (select count(*) from public.profiles
         where status = 'approved' and coalesce(is_active, true)
           and card_valid_until = extract(year from now())::int) as cartes_expirant_cette_annee,
       (select count(*) from public.profiles
         where status = 'pending' and created_at < now() - interval '48 hours') as inscriptions_oubliees;
