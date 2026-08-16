-- ============================================================
-- PHASE 88 - Boutons Telegram : WhatsApp en priorité, rappel paiement,
-- lien vers la fiche
--
-- CE QUI CHANGE PAR RAPPORT À LA PHASE 87.
--
-- 1. WHATSAPP D'ABORD. Un serveur ne peut pas envoyer de WhatsApp
--    libre : seul le téléphone de l'administrateur le peut. Le bouton
--    « Prévenir » devient donc un LIEN wa.me pré-rempli - exactement ce
--    que fait le site - qui ouvre WhatsApp sur le téléphone de celui qui
--    clique, message prêt, à envoyer d'un geste. Telegram et l'e-mail
--    passent en repli, pour les membres SANS numéro WhatsApp.
--
--    Conséquence : le texte du message est fabriqué ici, en SQL, et
--    transmis à la fonction Edge qui construit le lien. Il reprend MOT
--    POUR MOT ceux de l'écran Validation (compte activé, rappel de
--    paiement), pour que le membre reçoive la même chose quel que soit
--    l'endroit d'où on lui écrit.
--
-- 2. RAPPEL PAIEMENT. Sur une inscription de NOUVEL ADHÉRENT approuvée,
--    un second bouton envoie le rappel des montants et numéros de
--    règlement - le second message que le site propose.
--
-- 3. VOIR LA FICHE. Toute notification porte un lien vers l'écran
--    d'administration, pour les cas où le clic ne suffit pas.
--
-- Cette phase remplace prevenir_membre_auto (phase 87) par une fonction
-- qui RENVOIE le nécessaire au bouton au lieu d'envoyer elle-même, et
-- ajoute preparer_prevenir_membre() qui dit à la fonction Edge quels
-- canaux existent pour un membre.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Les textes, identiques à ceux du site =====
create or replace function public.texte_whatsapp_membre(p_user_id uuid, p_type text)
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
begin
  select first_name, full_name into v_m from public.profiles where id = p_user_id;
  v_prenom := nullif(btrim(coalesce(v_m.first_name,
                split_part(btrim(coalesce(v_m.full_name, '')), ' ', 1))), '');

  -- Bloc adhésion : recopié de membres/validation.html (blocAdhesion) -
  -- si les montants ou numéros changent, changer AUX DEUX ENDROITS.
  v_bloc := '1. Carte de membre (obligatoire) : *2 000 F*, valable 2 ans.' || chr(10)
         || '2. Cotisation annuelle : *12 000 F* (1 000 F/mois), payable en plusieurs tranches.' || chr(10) || chr(10)
         || '*Règlement à la Commission finances :*' || chr(10)
         || 'Wave : 78 828 32 16' || chr(10)
         || 'Orange Money : 78 867 96 23' || chr(10) || chr(10)
         || 'Une fois le paiement effectué, *envoyez-moi la capture d''écran de la transaction ici, '
         || 'sur WhatsApp* : elle sert de justificatif pour valider votre adhésion.';

  -- Texte de « compte activé » : recopié de texte_rappel_membre (phase
  -- 65), pour que le membre reçoive la même chose quel que soit le canal.
  if p_type = 'compte_active' then
    return (case when v_prenom is null then 'Bonjour,' else 'Bonjour ' || v_prenom || ',' end)
        || chr(10) || chr(10)
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
    return (case when v_prenom is null then 'Bonjour,' else 'Bonjour ' || v_prenom || ',' end)
        || chr(10) || chr(10)
        || 'Petit rappel pour finaliser votre adhésion à l''AMSTC :' || chr(10) || chr(10)
        || v_bloc || chr(10) || chr(10)
        || 'Merci !'
        || chr(10) || chr(10) || '©AMSTC';
  end if;

  return null;
end;
$$;

revoke all on function public.texte_whatsapp_membre(uuid, text) from public, anon, authenticated;
grant execute on function public.texte_whatsapp_membre(uuid, text) to service_role;

-- ===== 2. Ce que la fonction Edge doit savoir pour prévenir =====
-- Renvoie le numéro WhatsApp normalisé (chiffres, indicatif 221), le
-- texte prêt, et le nom - ou explique pourquoi c'est impossible. Ne fait
-- AUCUN envoi : c'est le téléphone de l'administrateur qui enverra.
create or replace function public.preparer_prevenir_membre(p_user_id uuid, p_type text)
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

  v_texte := public.texte_whatsapp_membre(p_user_id, p_type);
  if v_texte is null then
    return jsonb_build_object('ok', false, 'motif', 'Type de message inconnu : ' || coalesce(p_type, ''));
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

revoke all on function public.preparer_prevenir_membre(uuid, text) from public, anon, authenticated;
grant execute on function public.preparer_prevenir_membre(uuid, text) to service_role;

-- ===== 3. Repli : envoyer par Telegram ou e-mail quand pas de WhatsApp =====
-- Appelée par la fonction Edge UNIQUEMENT quand le membre n'a pas de
-- numéro WhatsApp. Ne fait rien d'autre que ce que faisait phase 87.
create or replace function public.prevenir_membre_repli(p_user_id uuid, p_type text)
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

  v_texte := public.texte_whatsapp_membre(p_user_id, p_type);
  if v_texte is null then return 'Type de message inconnu.'; end if;

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
      'titre', case p_type when 'rappel_paiement' then 'Finaliser votre adhésion à l''AMSTC'
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

revoke all on function public.prevenir_membre_repli(uuid, text) from public, anon, authenticated;
grant execute on function public.prevenir_membre_repli(uuid, text) to service_role;

-- ===== 4. Trace d'un WhatsApp ouvert depuis Telegram =====
-- Comme sur le site, le serveur ne peut pas constater l'envoi : on
-- enregistre l'intention au moment où le lien est proposé.
create or replace function public.tracer_whatsapp_telegram(p_user_id uuid, p_type text, p_qui text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_nom text;
begin
  select full_name into v_nom from public.profiles where id = p_user_id;
  perform public.journaliser('rappel_envoye', p_user_id, coalesce(v_nom, '(sans nom)'),
    jsonb_build_object('type', p_type, 'canal', 'whatsapp', 'depuis', 'bouton telegram',
                       'qui', coalesce(p_qui, '(inconnu)')));
end;
$$;

revoke all on function public.tracer_whatsapp_telegram(uuid, text, text) from public, anon, authenticated;
grant execute on function public.tracer_whatsapp_telegram(uuid, text, text) to service_role;

-- L'ancienne fonction de la phase 87 n'est plus appelée : on la retire
-- pour qu'elle ne survive pas en doublon trompeur.
drop function if exists public.prevenir_membre_auto(uuid, text);

notify pgrst, 'reload schema';

-- Contrôle : les fonctions en place et le texte qui se construit.
select proname from pg_proc
 where proname in ('texte_whatsapp_membre', 'preparer_prevenir_membre',
                   'prevenir_membre_repli', 'tracer_whatsapp_telegram')
 order by proname;
select left(public.texte_whatsapp_membre(
  (select id from public.profiles where status = 'approved' limit 1), 'rappel_paiement'), 120) as apercu;
