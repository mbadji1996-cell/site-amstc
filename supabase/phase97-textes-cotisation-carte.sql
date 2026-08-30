-- ============================================================
-- PHASE 97 - Dire POURQUOI l'on cotise, et que la carte est obligatoire
--
-- LE BESOIN. Les rappels disaient ce qu'il fallait faire, jamais pourquoi.
-- « Vos cotisations ne sont pas à jour » se lit comme une réclamation
-- comptable ; on paie mieux, et plus volontiers, quand on sait à quoi la
-- somme sert. Deux ajouts, donc :
--
--   1. COTISATION : ce qu'elle permet - les activités médicales et
--      sociales de l'AMSTC auprès des populations, et, par le service rendu
--      aux Hommes, le service d'Allah.
--   2. CARTE : qu'elle est OBLIGATOIRE pour tout membre. Le rappel ne le
--      disait pas ; beaucoup la croient facultative, ou réservée à ceux
--      qui veulent lire les contenus réservés.
--
-- ------------------------------------------------------------
-- LES DEUX CANAUX CHANGENT ENSEMBLE
-- ------------------------------------------------------------
-- Les mêmes rappels partent par deux chemins, écrits dans deux fonctions
-- distinctes :
--
--   texte_rappel_membre()   - le courriel (fiche du membre, et le bouton
--                             de relance collective de la phase 96)
--   texte_whatsapp_membre() - WhatsApp et Telegram
--
-- Les commentaires des phases 65 et 89 le répètent : si l'un change,
-- l'autre change. Un membre relancé par les deux canaux doit lire
-- exactement la même chose, sinon il se demande lequel fait foi. Cette
-- phase les modifie donc toutes les deux, d'un seul passage.
--
-- LE RESTE EST REPRIS À L'IDENTIQUE des phases 65 et 89 : même structure,
-- mêmes autres types, mêmes chemins, même signature. Seuls les corps de
-- « carte_expiree », « carte_expire_bientot » et « cotisation_retard »
-- gagnent un paragraphe.
--
-- PRÉREQUIS : phases 57, 60, 65, 89.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger. AUCUN ENVOI n'a lieu à l'exécution.
-- ============================================================

-- ============================================================
-- 1. LE COURRIEL
-- ============================================================
create or replace function public.texte_rappel_membre(
  p_user_id uuid, p_type text, p_message text default null
)
returns table (titre text, corps text, lien text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m record;
  v_annee int := extract(year from now())::int;
  v_site text := 'https://amstc.org';
  v_titre text;
  v_corps text;
  v_lien text;
  v_chemin text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select p.first_name, p.full_name, p.card_valid_until, p.legacy_card_number
    into v_m
    from public.profiles p
   where p.id = p_user_id;

  if v_m is null then
    raise exception 'Membre introuvable.';
  end if;

  if p_type = 'compte_active' then
    v_titre := 'Votre compte AMSTC est activé';
    v_corps := 'Votre compte a été validé par l''administration : l''espace membres vous est désormais ouvert.'
      || chr(10) || chr(10)
      || 'Connectez-vous dès maintenant avec l''adresse e-mail de votre inscription. Vous y trouverez '
      || 'votre carte de membre, les formations, l''annuaire et les documents de l''association.'
      || chr(10) || chr(10)
      -- Un compte validé il y a plusieurs semaines a souvent perdu son
      -- mot de passe en route : le dire ici évite un aller-retour.
      || 'Si vous avez oublié votre mot de passe, utilisez « Mot de passe oublié ? » sur la page de connexion.';
    v_lien := v_site || '/membres/connexion.html';
    v_chemin := 'Espace membres > Se connecter';

  elsif p_type = 'carte_expiree' then
    v_titre := 'Votre carte de membre AMSTC a expiré';
    v_corps := 'Votre carte de membre '
      || coalesce('(' || v_m.legacy_card_number || ') ', '')
      || case when v_m.card_valid_until is null
              then 'n''a pas encore été réglée.'
              else 'a expiré à la fin de l''année ' || v_m.card_valid_until || '.' end
      || chr(10) || chr(10)
      -- NOUVEAU (phase 97). Le rappel ne disait pas que la carte est une
      -- obligation : beaucoup la croyaient facultative, ou réservée à qui
      -- veut lire les contenus réservés.
      || 'La carte de membre est obligatoire pour tout membre de l''AMSTC : elle atteste '
      || 'votre appartenance à l''association et ouvre l''accès aux contenus réservés.'
      || chr(10) || chr(10)
      || 'Merci de la renouveler depuis votre espace membres.';
    v_lien := v_site || '/membres/profil.html?open=validity';
    v_chemin := 'Espace membres > Carte de membre et Cotisations > Validité de la carte';

  elsif p_type = 'carte_expire_bientot' then
    v_titre := 'Votre carte de membre expire fin ' || coalesce(v_m.card_valid_until, v_annee);
    v_corps := 'Votre carte de membre est valable jusqu''à la fin de l''année '
      || coalesce(v_m.card_valid_until, v_annee) || '.'
      || chr(10) || chr(10)
      || 'La carte de membre est obligatoire pour tout membre de l''AMSTC : pensez à la '
      || 'renouveler pour ne pas interrompre votre appartenance ni votre accès aux '
      || 'contenus réservés.';
    v_lien := v_site || '/membres/profil.html?open=validity';
    v_chemin := 'Espace membres > Carte de membre et Cotisations > Validité de la carte';

  elsif p_type = 'cotisation_retard' then
    v_titre := 'Cotisations mensuelles AMSTC';
    v_corps := 'Vos cotisations mensuelles de l''année ' || v_annee || ' ne sont pas à jour.'
      || chr(10) || chr(10)
      -- NOUVEAU (phase 97). Dire à quoi la somme sert : un rappel qui
      -- n'énonce qu'une dette se lit comme une réclamation comptable.
      || 'Ces cotisations sont ce qui permet à l''AMSTC de mener à bien ses activités '
      || 'médicales et sociales auprès des populations, et, par le service rendu aux Hommes, '
      || 'de servir Allah. Chaque contribution y participe, si modeste soit-elle.'
      || chr(10) || chr(10)
      || 'Vous pouvez les régler à tout moment par Wave ou Orange Money, puis déclarer '
      || 'la référence de la transaction.';
    v_lien := v_site || '/membres/profil.html?open=cotis';
    v_chemin := 'Espace membres > Carte de membre et Cotisations > Cotisations mensuelles';

  elsif p_type = 'libre' then
    if btrim(coalesce(p_message, '')) = '' then
      raise exception 'Le message est vide.';
    end if;
    v_titre := 'Message de l''AMSTC';
    v_corps := btrim(p_message);
    v_lien := v_site || '/membres/connexion.html';
    v_chemin := 'Espace membres';

  else
    raise exception 'Type de rappel inconnu : %', p_type;
  end if;

  -- Le chemin fait partie du corps : il part ainsi à l'identique par
  -- e-mail et par WhatsApp, et un membre qui lit le message sur son
  -- téléphone n'a plus à chercher où aller.
  v_corps := v_corps || chr(10) || chr(10)
    || 'Où aller : ' || v_chemin || chr(10) || v_lien;

  -- Signature commune à tous les messages sortants.
  v_corps := v_corps || chr(10) || chr(10) || '©AMSTC';

  return query select v_titre, v_corps, v_lien;
end;
$$;

revoke all on function public.texte_rappel_membre(uuid, text, text) from public, anon;
grant execute on function public.texte_rappel_membre(uuid, text, text) to authenticated;

-- ============================================================
-- 2. WHATSAPP ET TELEGRAM - mot pour mot le même texte
-- ============================================================
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
        || 'La carte de membre est *obligatoire* pour tout membre de l''AMSTC : elle atteste '
        || 'votre appartenance à l''association et ouvre l''accès aux contenus réservés.'
        || chr(10) || chr(10)
        || 'Merci de la renouveler depuis votre espace membres.'
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
        || 'La carte de membre est *obligatoire* pour tout membre de l''AMSTC : pensez à la '
        || 'renouveler pour ne pas interrompre votre appartenance ni votre accès aux '
        || 'contenus réservés.'
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
        || 'Ces cotisations sont ce qui permet à l''AMSTC de mener à bien ses activités '
        || 'médicales et sociales auprès des populations, et, par le service rendu aux Hommes, '
        || 'de servir Allah. Chaque contribution y participe, si modeste soit-elle.'
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

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - aucun envoi
-- ============================================================
-- Le SQL Editor s'exécute sans session : texte_rappel_membre() est gardée
-- par is_admin() et répondrait « Accès refusé ». On lit donc les textes
-- par la fonction WhatsApp, qui ne l'est pas - les deux disent la même
-- chose, c'est tout l'objet de cette phase.
--
-- Remplacez l'identifiant par celui d'un membre approuvé de votre base
-- (une ligne du contrôle a) de la phase 96 vous en donne).
--
-- select public.texte_whatsapp_membre(
--   '00000000-0000-0000-0000-000000000000', 'cotisation_retard');
-- select public.texte_whatsapp_membre(
--   '00000000-0000-0000-0000-000000000000', 'carte_expiree');

-- Les deux fonctions sont-elles bien en place ?
select p.proname,
       case when p.prosecdef then 'security definer' else 'invoker' end as mode
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('texte_rappel_membre', 'texte_whatsapp_membre')
 order by p.proname;

-- Le texte réellement produit, pour un membre réellement concerné.
--
-- MIEUX QU'UNE VÉRIFICATION PAR MOT-CLÉ. Le premier contrôle écrit ici
-- cherchait la chaîne « obligatoire pour tout membre » dans le code des
-- deux fonctions. Il annonçait « false » sur la version WhatsApp, alors
-- que la phrase y était : celle-ci écrit « *obligatoire* », avec les
-- astérisques du gras WhatsApp, ce qui coupait la chaîne cherchée. Une
-- vérification qui crie au loup est pire que pas de vérification. On
-- affiche donc le message tel qu'il partira, et vous le lisez.
--
-- Ces deux requêtes choisissent elles-mêmes un membre concerné : rien à
-- remplacer. Elles n'envoient rien.

-- a) Le rappel de CARTE, tel que le recevra le premier membre dont la
--    carte a expiré.
select public.texte_whatsapp_membre(
  (select p.id from public.profiles p
    where p.status = 'approved' and p.is_active
      and (p.card_valid_until is null
           or p.card_valid_until < extract(year from now())::int)
    order by p.full_name limit 1),
  'carte_expiree') as rappel_carte;

-- b) Le rappel de COTISATION, pour le premier membre à carte valide dont
--    le mois en cours n'est pas réglé.
select public.texte_whatsapp_membre(
  (select p.id from public.profiles p
    where p.status = 'approved' and p.is_active
      and p.card_valid_until >= extract(year from now())::int
      and not exists (
        select 1 from public.cotisations c
         where c.user_id = p.id
           and c.year = extract(year from now())::int
           and extract(month from now())::int = any(c.months_paid))
    order by p.full_name limit 1),
  'cotisation_retard') as rappel_cotisation;

-- Le courriel dit-il la même chose ? Il le dit forcément : les deux
-- fonctions ont été écrites ensemble, ci-dessus, et la seule différence
-- voulue est le gras WhatsApp (*obligatoire*), absent du courriel où le
-- HTML s'en charge. Pour le voir de vos yeux, ouvrez la fiche d'un membre
-- dans l'écran Membres et cliquez « Prévenir » : l'aperçu s'affiche avant
-- tout envoi.
