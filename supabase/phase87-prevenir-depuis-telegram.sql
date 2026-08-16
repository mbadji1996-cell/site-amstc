-- ============================================================
-- PHASE 87 - Prévenir le membre depuis Telegram, en un clic
--
-- LE BESOIN. Après avoir approuvé une inscription depuis le groupe
-- Telegram, il fallait encore ouvrir le site pour prévenir le membre
-- (écran Validation > Prévenir > « Compte activé - se connecter »).
-- Ce script ajoute une action « Prévenir » aux boutons Telegram, qui
-- envoie ce même message.
--
-- PAR QUEL CANAL. On réutilise texte_rappel_membre() - le texte est donc
-- identique à celui du site - et l'on choisit :
--   1. Telegram, si le membre a rattaché le sien (phase 85) : c'est
--      immédiat et gratuit ;
--   2. sinon l'e-mail, par envoyer_rappel_membre() (phase 57) ;
--   3. sinon rien n'est possible depuis Telegram : la réponse le dit et
--      renvoie vers WhatsApp - le serveur ne peut pas envoyer de
--      WhatsApp libre, seul l'administrateur le peut depuis son
--      téléphone.
-- Le canal utilisé est renvoyé dans la réponse et journalisé.
--
-- L'action s'ajoute à action_telegram sous le code « ins:msg » ; le
-- reste de la fonction (phase 86) est inchangé et recopié tel quel.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Prévenir un membre par le meilleur canal disponible =====
create or replace function public.prevenir_membre_auto(p_user_id uuid, p_type text default 'compte_active')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m     record;
  v_texte record;
  v_chat  bigint;
begin
  select id, email, full_name, first_name, telegram_chat_id
    into v_m from public.profiles where id = p_user_id;
  if v_m.id is null then
    return 'Ce compte n''existe plus.';
  end if;

  select * into v_texte from public.texte_rappel_membre(p_user_id, p_type, null);

  -- 1. Telegram rattaché : le membre reçoit dans sa conversation privée
  --    avec le bot, immédiatement.
  v_chat := v_m.telegram_chat_id;
  if v_chat is not null then
    perform public.notify_admin('message_telegram', jsonb_build_object(
      'chat_id', v_chat,
      'texte', v_texte.titre || chr(10) || chr(10) || v_texte.corps));
    perform public.journaliser('rappel_envoye', p_user_id,
      coalesce(v_m.full_name, v_m.email, '(sans nom)'),
      jsonb_build_object('type', p_type, 'canal', 'telegram', 'titre', v_texte.titre,
                         'depuis', 'bouton telegram'));
    return 'Membre prévenu sur Telegram : ' || coalesce(v_m.first_name, v_m.full_name, '');
  end if;

  -- 2. E-mail.
  if coalesce(btrim(v_m.email), '') <> '' then
    perform public.notify_membre('rappel_admin', jsonb_build_object(
      'email', v_m.email,
      'full_name', v_m.full_name,
      'first_name', v_m.first_name,
      'titre', v_texte.titre,
      'corps', v_texte.corps));
    perform public.journaliser('rappel_envoye', p_user_id,
      coalesce(v_m.full_name, v_m.email, '(sans nom)'),
      jsonb_build_object('type', p_type, 'canal', 'email', 'titre', v_texte.titre,
                         'depuis', 'bouton telegram'));
    return 'Membre prévenu par e-mail : ' || coalesce(v_m.first_name, v_m.full_name, '');
  end if;

  -- 3. Rien de possible d'ici.
  return 'Ni Telegram ni e-mail pour ce membre : prévenez-le par WhatsApp depuis le site.';
end;
$$;

revoke all on function public.prevenir_membre_auto(uuid, text) from public, anon, authenticated;
grant execute on function public.prevenir_membre_auto(uuid, text) to service_role;

-- ===== 2. action_telegram : le code « ins:msg » =====
create or replace function public.action_telegram(
  p_action text,
  p_id uuid,
  p_qui text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin    uuid;
  v_nom      text;
  v_resultat text;
  v_qui      text := nullif(btrim(coalesce(p_qui, '')), '');
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

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_admin::text)::text, true);

  case p_action
    when 'ins:ok' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'approved');
      v_resultat := 'Inscription approuvée : ' || coalesce(v_nom, '');

    when 'ins:no' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'rejected');
      v_resultat := 'Inscription refusée : ' || coalesce(v_nom, '');

    -- NOUVEAU : prévenir le membre que son compte est actif. N'agit que
    -- sur un compte APPROUVÉ - prévenir quelqu'un dont l'inscription est
    -- encore en attente lui promettrait un accès qu'il n'a pas.
    when 'ins:msg' then
      select full_name into v_nom from public.profiles
       where id = p_id and status = 'approved';
      if v_nom is null then
        return 'Ce compte n''est pas (ou plus) approuvé : approuvez-le d''abord.';
      end if;
      v_resultat := public.prevenir_membre_auto(p_id, 'compte_active');

    when 'val:ok' then
      if not exists (select 1 from public.card_validity_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      select p.full_name into v_nom
        from public.card_validity_payments v join public.profiles p on p.id = v.user_id
       where v.id = p_id;
      perform public.confirm_card_validity_payment(p_id);
      v_resultat := 'Paiement de validité confirmé.';

    when 'val:no' then
      select p.full_name into v_nom
        from public.card_validity_payments v join public.profiles p on p.id = v.user_id
       where v.id = p_id;
      update public.card_validity_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      v_resultat := 'Paiement de validité refusé.';

    when 'cot:ok' then
      if not exists (select 1 from public.cotisation_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      select p.full_name into v_nom
        from public.cotisation_payments c join public.profiles p on p.id = c.user_id
       where c.id = p_id;
      perform public.confirm_cotisation_payment(p_id);
      v_resultat := 'Paiement de cotisation confirmé.';

    when 'cot:no' then
      select p.full_name into v_nom
        from public.cotisation_payments c join public.profiles p on p.id = c.user_id
       where c.id = p_id;
      update public.cotisation_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      v_resultat := 'Paiement de cotisation refusé.';

    else
      return 'Action inconnue : ' || coalesce(p_action, '(vide)');
  end case;

  begin
    perform public.journaliser('action_telegram', p_id, coalesce(v_nom, '(sans nom)'),
      jsonb_build_object(
        'qui', coalesce(v_qui, '(inconnu)'),
        'action', p_action,
        'resultat', v_resultat,
        'canal', 'telegram'));
  exception when others then
    raise warning 'action_telegram : journalisation échouée : %', sqlerrm;
  end;

  return v_resultat;

exception when others then
  return 'Échec : ' || sqlerrm;
end;
$$;

revoke all on function public.action_telegram(text, uuid, text) from public, anon, authenticated;
grant execute on function public.action_telegram(text, uuid, text) to service_role;

notify pgrst, 'reload schema';

-- Contrôle : la fonction est en place et le texte se construit.
select titre from public.texte_rappel_membre(
  (select id from public.profiles where status = 'approved' limit 1), 'compte_active', null);
