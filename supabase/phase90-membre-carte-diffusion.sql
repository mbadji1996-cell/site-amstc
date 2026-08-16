-- ============================================================
-- PHASE 90 - Telegram : chercher un membre, sa carte, et parler à tous
--
-- TROIS APPORTS, tous commandés depuis le salon d'administration ou la
-- conversation du membre - jamais depuis le site.
--
-- 1. « /membre <nom> » : la fiche d'un membre dans le groupe. Statut,
--    téléphone, carte, cotisations, Telegram rattaché ou non - et les
--    boutons « Prévenir » et « Voir la fiche » dessous. C'est l'annuaire
--    d'administration dans la poche, sans ouvrir le site.
--
--    Une recherche qui ramène plusieurs personnes propose la liste ; une
--    recherche trop large le dit et demande de préciser, plutôt que de
--    déverser trois cents noms dans le groupe.
--
-- 2. La réponse « carte » au MEMBRE devient une vraie fiche : son nom,
--    son numéro, la validité, ses cotisations de l'année et sa région.
--    Elle tenait en trois lignes ; elle répond maintenant d'avance aux
--    questions qui suivaient toujours.
--
-- 3. « /diffusion <texte> » : une annonce à TOUS les membres qui ont
--    rattaché leur Telegram. Rien ne part au moment où on l'écrit : le
--    bot affiche le texte, compte les destinataires, et attend une
--    confirmation. Un message parti à trois cents personnes ne se
--    rattrape pas.
--
--    Chaque diffusion est enregistrée avec son auteur et son heure
--    d'envoi, et ne peut PARTIR QU'UNE FOIS : recliquer le bouton d'une
--    vieille annonce ne la renverra pas.
--
-- CE QUE LE BOT NE FERA JAMAIS : donner à un membre des informations
-- sur quelqu'un d'autre. « /membre » n'est reconnu que dans le salon
-- d'administration, et la fonction Edge refuse tout autre salon.
--
-- PRÉREQUIS : phases 85 et 89.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. LA FICHE D'UN MEMBRE, POUR LE GROUPE
-- ============================================================
-- Texte brut, sans mise en forme : un nom peut contenir un chevron, et
-- la fonction Edge l'enverrait alors en HTML cassé.
create or replace function public.fiche_membre_telegram(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p     public.profiles%rowtype;
  v_annee int := extract(year from now())::int;
  v_mois  int[];
  v_nb    int;
  v_libel text;
  v_t     text;
begin
  select * into v_p from public.profiles where id = p_user_id;
  if v_p.id is null then return 'Ce compte n''existe plus.'; end if;

  select months_paid into v_mois
    from public.cotisations where user_id = v_p.id and year = v_annee;
  v_mois := coalesce(v_mois, '{}');
  v_nb := coalesce(array_length(v_mois, 1), 0);
  -- Noms des mois écrits en dur : to_char suit la locale de la session,
  -- anglaise sur cette instance (constaté phase 85).
  select string_agg((array['janvier','février','mars','avril','mai','juin','juillet',
                           'août','septembre','octobre','novembre','décembre'])[m],
                    ', ' order by m)
    into v_libel from unnest(v_mois) m where m between 1 and 12;

  v_t := coalesce(v_p.full_name, v_p.email, '(sans nom)') || chr(10)
      || 'Statut : ' || coalesce(v_p.status, '?')
      || case when coalesce(v_p.is_active, true) then '' else ' (désactivé)' end
      || case when v_p.applicant_type = 'nouvel_adherent' then ' · nouvel adhérent'
              when v_p.applicant_type is not null then ' · membre existant' else '' end
      || chr(10)
      || 'Téléphone : ' || coalesce(nullif(btrim(v_p.phone), ''), '-') || chr(10)
      || 'E-mail : ' || coalesce(nullif(btrim(v_p.email), ''), '-') || chr(10)
      || 'Ville : ' || coalesce(nullif(btrim(v_p.city), ''), '-')
      || coalesce(' (' || nullif(btrim(v_p.region), '') || ')', '') || chr(10)
      || 'Carte : ' || coalesce(v_p.legacy_card_number, 'non attribuée')
      || case when v_p.card_valid_until is null then ', validité non réglée'
              when v_p.card_valid_until < v_annee
                then ', EXPIRÉE fin ' || v_p.card_valid_until
              else ', valide jusqu''au 31/12/' || v_p.card_valid_until end
      || chr(10)
      || 'Membre depuis : ' || coalesce(v_p.member_since::text, '-') || chr(10)
      || 'Cotisations ' || v_annee || ' : ' || v_nb || '/12'
      || coalesce(' (' || v_libel || ')', '') || chr(10)
      || 'Telegram : ' || case when v_p.telegram_chat_id is null
                               then 'non rattaché' else 'rattaché' end || chr(10)
      || 'Inscrit le ' || to_char(v_p.created_at, 'DD/MM/YYYY');

  return v_t;
end;
$$;

revoke all on function public.fiche_membre_telegram(uuid) from public, anon, authenticated;
grant execute on function public.fiche_membre_telegram(uuid) to service_role;

-- ============================================================
-- 2. LA RECHERCHE
-- ============================================================
-- Nom, e-mail, téléphone ou numéro de carte : on ne sait jamais avec
-- quoi l'administration cherchera, et exiger le bon champ ferait
-- échouer une recherche sur trois.
create or replace function public.chercher_membres_telegram(
  p_recherche text, p_max int default 8
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q      text := btrim(coalesce(p_recherche, ''));
  v_motif  text;
  v_tel    text;
  v_total  int;
  v_liste  jsonb;
begin
  if length(v_q) < 2 then
    return jsonb_build_object('ok', false, 'motif', 'Cherchez avec au moins deux caractères.');
  end if;

  -- « % » et « _ » saisis par mégarde transformeraient la recherche en
  -- joker : on les neutralise avant de bâtir le motif.
  v_motif := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  -- Un numéro se cherche par ses chiffres seuls : « 77 844 53 92 » et
  -- « +221778445392 » désignent la même personne.
  v_tel := nullif(regexp_replace(v_q, '\D', '', 'g'), '');

  -- Une seule définition du « qui correspond », lue deux fois dans la
  -- même requête : pour compter le total et pour lister les premiers.
  -- Deux requêtes séparées finiraient par diverger.
  with trouves as (
    select p.id, coalesce(p.full_name, p.email, '(sans nom)') as nom, p.status as statut,
           -- Les comptes approuvés d'abord : c'est presque toujours
           -- d'eux qu'il s'agit, et un refusé en tête de liste fait
           -- douter du résultat.
           row_number() over (
             order by case p.status when 'approved' then 0 when 'pending' then 1 else 2 end,
                      coalesce(p.full_name, p.email)) as rang
      from public.profiles p
     where p.full_name ilike v_motif
        or p.email ilike v_motif
        or p.legacy_card_number ilike v_motif
        or (v_tel is not null and length(v_tel) >= 5
            and regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || v_tel || '%')
  )
  select (select count(*) from trouves),
         (select jsonb_agg(jsonb_build_object('id', id, 'nom', nom, 'statut', statut) order by rang)
            from trouves where rang <= greatest(coalesce(p_max, 8), 1))
    into v_total, v_liste;

  if v_total = 0 then
    return jsonb_build_object('ok', true, 'nombre', 0, 'membres', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'ok', true,
    'nombre', v_total,
    'tronque', v_total > greatest(coalesce(p_max, 8), 1),
    'membres', coalesce(v_liste, '[]'::jsonb));
end;
$$;

revoke all on function public.chercher_membres_telegram(text, int) from public, anon, authenticated;
grant execute on function public.chercher_membres_telegram(text, int) to service_role;

-- ============================================================
-- 3. LA CARTE DU MEMBRE, ENRICHIE
-- ============================================================
-- Remplace la version de la phase 85. Le principe ne change pas : la
-- réponse est construite À PARTIR DE LA CONVERSATION, jamais d'un nom
-- saisi - impossible d'interroger le dossier de quelqu'un d'autre.
create or replace function public.infos_membre_telegram(p_chat_id bigint, p_quoi text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p      public.profiles%rowtype;
  v_annee  int := extract(year from now())::int;
  v_mois   int[];
  v_nb     int;
  v_libel  text;
begin
  select * into v_p from public.profiles where telegram_chat_id = p_chat_id;

  if v_p.id is null then
    return 'Votre Telegram n''est rattaché à aucun compte AMSTC. '
        || 'Connectez-vous sur amstc.org, onglet « Carte de membre et Cotisations », '
        || 'et touchez « Recevoir mes rappels sur Telegram ».';
  end if;

  select months_paid into v_mois
    from public.cotisations where user_id = v_p.id and year = v_annee;
  v_mois := coalesce(v_mois, '{}');
  v_nb := coalesce(array_length(v_mois, 1), 0);
  select string_agg((array['janvier','février','mars','avril','mai','juin','juillet',
                           'août','septembre','octobre','novembre','décembre'])[m],
                    ', ' order by m)
    into v_libel from unnest(v_mois) m where m between 1 and 12;

  if p_quoi = 'carte' then
    -- La carte telle qu'elle est imprimée, plus l'état des cotisations :
    -- c'était la question qui suivait systématiquement.
    return 'VOTRE CARTE AMSTC' || chr(10) || chr(10)
        || coalesce(v_p.full_name, '') || chr(10)
        || 'N° ' || coalesce(v_p.legacy_card_number, 'non attribué') || chr(10)
        || 'Membre depuis : ' || coalesce(v_p.member_since::text, '-') || chr(10)
        || case when v_p.card_valid_until is null
                then 'Validité : non réglée'
                when v_p.card_valid_until < v_annee
                then 'Validité : EXPIRÉE fin ' || v_p.card_valid_until
                else 'Valide jusqu''au 31/12/' || v_p.card_valid_until end || chr(10)
        || coalesce('Région : ' || nullif(btrim(v_p.region), '') || chr(10), '')
        || 'Cotisations ' || v_annee || ' : ' || v_nb || '/12' || chr(10)
        || case when coalesce(v_p.card_valid_until, 0) < v_annee
                then chr(10) || 'Votre carte est expirée : renouvelez-la depuis '
                     || 'l''espace membres pour garder l''accès aux contenus réservés.'
                else '' end;

  elsif p_quoi = 'cotisations' then
    return 'Cotisations ' || v_annee || ' : ' || v_nb || '/12' || chr(10)
        || case when v_nb = 0 then 'Aucun mois réglé cette année.'
                else 'Réglés : ' || coalesce(v_libel, '') end
        || chr(10) || 'Reste ' || (12 - v_nb) || ' mois, soit ' || ((12 - v_nb) * 1000) || ' F.'
        || chr(10) || '1 000 F par mois - déclarez vos paiements sur amstc.org.';

  else
    return 'Bonjour ' || coalesce(v_p.first_name, v_p.full_name, '') || ' !' || chr(10)
        || 'Écrivez :' || chr(10)
        || '  carte - votre numéro et la validité' || chr(10)
        || '  cotisations - vos mois réglés' || chr(10)
        || 'Vous recevrez aussi ici les rappels de cotisation et d''échéance de carte.';
  end if;
end;
$$;

revoke all on function public.infos_membre_telegram(bigint, text) from public, anon, authenticated;
grant execute on function public.infos_membre_telegram(bigint, text) to service_role;

-- ============================================================
-- 4. LA DIFFUSION À TOUS LES MEMBRES RATTACHÉS
-- ============================================================
create table if not exists public.diffusions_telegram (
  id            uuid primary key default gen_random_uuid(),
  texte         text not null,
  cree_par      text,
  cree_le       timestamptz not null default now(),
  envoye_le     timestamptz,
  envoye_par    text,
  destinataires int,
  annule_le     timestamptz
);

alter table public.diffusions_telegram enable row level security;
-- Aucune politique : seules les fonctions ci-dessous, en security
-- definer, y accèdent.

-- Écrire l'annonce ne l'envoie pas : on l'enregistre, on compte les
-- destinataires, et l'on rend de quoi demander confirmation.
create or replace function public.preparer_diffusion(p_texte text, p_qui text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t  text := btrim(coalesce(p_texte, ''));
  v_nb int;
  v_id uuid;
begin
  if length(v_t) < 5 then
    return jsonb_build_object('ok', false, 'motif', 'Annonce trop courte : écrivez le message après la commande.');
  end if;
  -- Telegram refuse au-delà de 4096 caractères ; on tranche avant lui,
  -- pour que le refus soit compréhensible.
  if length(v_t) > 3500 then
    return jsonb_build_object('ok', false,
      'motif', 'Annonce trop longue (' || length(v_t) || ' caractères, 3500 au maximum).');
  end if;

  select count(*) into v_nb from public.profiles
   where telegram_chat_id is not null
     and status = 'approved'
     and coalesce(is_active, true) is true;

  if v_nb = 0 then
    return jsonb_build_object('ok', false,
      'motif', 'Aucun membre n''a rattaché son Telegram : personne ne recevrait cette annonce.');
  end if;

  insert into public.diffusions_telegram (texte, cree_par)
    values (v_t, nullif(btrim(coalesce(p_qui, '')), ''))
    returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'nb', v_nb, 'texte', v_t);
end;
$$;

revoke all on function public.preparer_diffusion(text, text) from public, anon, authenticated;
grant execute on function public.preparer_diffusion(text, text) to service_role;

-- L'envoi réel. Verrouillé sur la ligne : deux clics simultanés sur le
-- même bouton ne peuvent pas produire deux envois.
create or replace function public.envoyer_diffusion(p_id uuid, p_qui text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_d      public.diffusions_telegram%rowtype;
  v_membre record;
  v_n      int := 0;
  v_echecs int := 0;
begin
  select * into v_d from public.diffusions_telegram where id = p_id for update;
  if v_d.id is null then return 'Cette annonce est introuvable.'; end if;
  if v_d.annule_le is not null then return 'Cette annonce a été annulée.'; end if;
  if v_d.envoye_le is not null then
    return 'Cette annonce est déjà partie le '
        || to_char(v_d.envoye_le, 'DD/MM à HH24:MI') || ' (' || coalesce(v_d.destinataires, 0) || ' membres).';
  end if;

  for v_membre in
    select id, telegram_chat_id from public.profiles
     where telegram_chat_id is not null
       and status = 'approved'
       and coalesce(is_active, true) is true
  loop
    begin
      perform public.notify_admin('message_telegram', jsonb_build_object(
        'chat_id', v_membre.telegram_chat_id, 'texte', v_d.texte));
      v_n := v_n + 1;
    exception when others then
      -- Un membre qui a bloqué le bot ne doit pas interrompre la
      -- diffusion pour les autres.
      v_echecs := v_echecs + 1;
    end;
  end loop;

  update public.diffusions_telegram
     set envoye_le = now(),
         envoye_par = nullif(btrim(coalesce(p_qui, '')), ''),
         destinataires = v_n
   where id = p_id;

  begin
    perform public.journaliser('diffusion_telegram', null, coalesce(p_qui, '(inconnu)'),
      jsonb_build_object('destinataires', v_n, 'echecs', v_echecs,
                         'apercu', left(v_d.texte, 120)));
  exception when others then null;
  end;

  return 'Annonce envoyée à ' || v_n || ' membre(s)'
      || case when v_echecs > 0 then ' (' || v_echecs || ' échec[s])' else '' end || '.';
end;
$$;

revoke all on function public.envoyer_diffusion(uuid, text) from public, anon, authenticated;
grant execute on function public.envoyer_diffusion(uuid, text) to service_role;

create or replace function public.annuler_diffusion(p_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  update public.diffusions_telegram set annule_le = now()
   where id = p_id and envoye_le is null and annule_le is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then return 'Rien à annuler : cette annonce est déjà partie ou déjà annulée.'; end if;
  return 'Annonce annulée : rien n''a été envoyé.';
end;
$$;

revoke all on function public.annuler_diffusion(uuid) from public, anon, authenticated;
grant execute on function public.annuler_diffusion(uuid) to service_role;

notify pgrst, 'reload schema';

-- ============================================================
-- 5. CONTRÔLES
-- ============================================================
-- a) Les quatre fonctions nouvelles, plus celle qui a été remplacée.
select proname from pg_proc
 where proname in ('fiche_membre_telegram', 'chercher_membres_telegram',
                   'preparer_diffusion', 'envoyer_diffusion', 'annuler_diffusion',
                   'infos_membre_telegram')
 order by proname;

-- b) Une recherche sur les deux premières lettres d'un membre approuvé :
--    elle doit renvoyer au moins une ligne.
select public.chercher_membres_telegram(
  (select left(coalesce(full_name, email), 3) from public.profiles
    where status = 'approved' limit 1)) as recherche;

-- c) La fiche de ce même membre.
select public.fiche_membre_telegram(
  (select id from public.profiles where status = 'approved' limit 1)) as fiche;

-- d) Combien recevraient une diffusion aujourd'hui.
select count(*) as destinataires_diffusion from public.profiles
 where telegram_chat_id is not null and status = 'approved'
   and coalesce(is_active, true) is true;
