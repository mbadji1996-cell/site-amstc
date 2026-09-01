-- ============================================================
-- PHASE 101 - Les audiences d'un envoi groupé
--
-- REMPLACE INTÉGRALEMENT LA PHASE 100, que vous l'ayez exécutée ou non :
-- les trois fonctions sont recréées ici en entier. Exécuter celle-ci
-- suffit ; si la 100 a déjà tourné, elle est simplement écrasée.
--
-- LE BESOIN. L'écran ne visait que deux publics - les retardataires, ou
-- tout le monde. L'association en veut davantage : une annonce à tous,
-- un mot aux seuls porteurs d'une carte à renouveler, une relance à ceux
-- qui ne sont pas à jour, une convocation au Bureau, ou un message à
-- quelques personnes choisies une par une.
--
-- ------------------------------------------------------------
-- LES SEPT AUDIENCES
-- ------------------------------------------------------------
--   tous                 tout membre approuvé, actif, avec une adresse
--   carte_expiree        sa carte est absente ou antérieure à cette année
--   carte_expire_bientot sa carte s'arrête à la fin de l'année en cours
--   cotisation_retard    il manque un mois ÉCHU de l'année en cours
--   retardataires        carte expirée OU cotisation en retard
--   bureau               une fonction au Bureau lui est attribuée
--   selection            les identifiants passés en paramètre
--
-- TOUTES PARTAGENT LE MÊME SOCLE : approuvé, actif, adresse plausible.
-- Sans adresse, on ne peut rien envoyer - ces membres sont dénombrés à
-- part par l'aperçu, pour qu'on sache qu'ils existent au lieu de les
-- croire prévenus.
--
-- « À JOUR » SE COMPTE SUR LES MOIS ÉCHUS, jamais sur douze. En
-- septembre, avoir réglé janvier à septembre suffit ; exiger 12/12
-- rangerait presque tous les membres parmi les retardataires toute
-- l'année. Et l'on ne réclame pas les mois antérieurs à l'ouverture du
-- compte : un inscrit d'août ne doit rien pour janvier. Même définition
-- que la relance collective (phase 96).
--
-- LE BUREAU SE RECONNAÎT À SA « fonction » (phase 52). Ce n'est pas le
-- rôle administrateur : un membre du Bureau n'est pas forcément
-- administrateur, et l'inverse est vrai aussi.
--
-- PRÉREQUIS : phases 50, 51, 52, 65, 96.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger. AUCUN ENVOI n'a lieu à l'exécution.
--
-- NOTE SUR LE SQL EDITOR : il s'exécute sans session, is_admin() y répond
-- donc toujours « non ». Appeler ces fonctions ici renverrait « Accès
-- refusé » - la preuve que la garde tient, pas un défaut. Les contrôles
-- en fin de fichier refont la sélection en SQL nu.
-- ============================================================

-- ============================================================
-- 1. QUI RECEVRAIT LE MESSAGE
-- ============================================================
-- Noms de sortie distincts de ceux de profiles : « returns table »
-- déclare chaque nom comme variable, et un homonyme rendrait la requête
-- ambiguë (erreur 42702, rencontrée en phase 93).
create or replace function public.destinataires_message(
  p_audience text,
  p_ids uuid[] default null
)
returns table (
  id_membre uuid,
  nom       text,
  prenom    text,
  courriel  text,
  motif     text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if p_audience not in ('tous', 'carte_expiree', 'carte_expire_bientot',
                        'cotisation_retard', 'retardataires', 'bureau', 'selection') then
    raise exception 'Audience inconnue : %', p_audience;
  end if;

  if p_audience = 'selection'
     and (p_ids is null or array_length(p_ids, 1) is null) then
    raise exception 'Aucun membre sélectionné.';
  end if;

  return query
  with reperes as (
    select extract(year from now())::int as annee,
           extract(month from now())::int as mois
  ),
  base as (
    select p.id, p.full_name, p.first_name, p.email, p.card_valid_until,
           p.fonction, r.annee, r.mois,
           -- On ne réclame pas les mois d'avant l'arrivée.
           case when extract(year from p.created_at)::int = r.annee
                then extract(month from p.created_at)::int
                else 1 end as premier_mois
      from public.profiles p
      cross join reperes r
     where p.status = 'approved'
       and p.is_active
       and coalesce(btrim(p.email), '') <> ''
       and position('@' in p.email) > 1
  ),
  etat as (
    select b.*,
           (b.card_valid_until is null or b.card_valid_until < b.annee) as carte_expiree,
           (b.card_valid_until = b.annee)                               as carte_bientot,
           (select count(*)
              from generate_series(b.premier_mois, b.mois) as m
             where not (m = any(
               coalesce((select c.months_paid from public.cotisations c
                          where c.user_id = b.id and c.year = b.annee),
                        '{}'::int[]))))::int > 0                        as en_retard
      from base b
  )
  select e.id, e.full_name, e.first_name, e.email,
         case when e.carte_expiree then 'carte_expiree'
              when e.en_retard     then 'cotisation_retard'
              when e.carte_bientot then 'carte_expire_bientot'
              else 'a_jour' end
    from etat e
   where case p_audience
           when 'tous'                 then true
           when 'carte_expiree'        then e.carte_expiree
           when 'carte_expire_bientot' then e.carte_bientot
           when 'cotisation_retard'    then e.en_retard
           when 'retardataires'        then (e.carte_expiree or e.en_retard)
           when 'bureau'               then coalesce(btrim(e.fonction), '') <> ''
           when 'selection'            then e.id = any(p_ids)
         end
   order by e.full_name;
end;
$$;

revoke all on function public.destinataires_message(text, uuid[]) from public, anon;
grant execute on function public.destinataires_message(text, uuid[]) to authenticated;

-- ============================================================
-- 2. LE DÉCOMPTE DE CHAQUE AUDIENCE
-- ============================================================
create or replace function public.apercu_audiences()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_annee int := extract(year from now())::int;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  return jsonb_build_object(
    'tous',                 (select count(*) from public.destinataires_message('tous')),
    'carte_expiree',        (select count(*) from public.destinataires_message('carte_expiree')),
    'carte_expire_bientot', (select count(*) from public.destinataires_message('carte_expire_bientot')),
    'cotisation_retard',    (select count(*) from public.destinataires_message('cotisation_retard')),
    'retardataires',        (select count(*) from public.destinataires_message('retardataires')),
    'bureau',               (select count(*) from public.destinataires_message('bureau')),
    -- Concernés mais injoignables : il vaut mieux le savoir que de les
    -- croire prévenus.
    'sans_courriel',        (select count(*) from public.profiles p
                              where p.status = 'approved' and p.is_active
                                and coalesce(btrim(p.email), '') = ''),
    'dernier_envoi',        (select max(a.cree_le) from public.audit_log a
                              where a.action = 'message_libre_masse')
  );
end;
$$;

revoke all on function public.apercu_audiences() from public, anon;
grant execute on function public.apercu_audiences() to authenticated;

-- La liste nominative d'une audience, pour l'écran : il affiche qui
-- recevra AVANT d'envoyer, et coche une par une pour « selection ».
create or replace function public.liste_membres_message()
returns table (
  id_membre uuid,
  nom       text,
  courriel  text,
  fonction  text,
  motif     text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  return query
    select d.id_membre, d.nom, d.courriel,
           (select btrim(coalesce(p.fonction, '')) from public.profiles p where p.id = d.id_membre),
           d.motif
      from public.destinataires_message('tous') d;
end;
$$;

revoke all on function public.liste_membres_message() from public, anon;
grant execute on function public.liste_membres_message() to authenticated;

-- ============================================================
-- 3. L'ENVOI
-- ============================================================
create or replace function public.envoyer_message_libre(
  p_message  text,
  p_audience text default 'tous',
  p_forcer   boolean default false,
  p_ids      uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m       record;
  v_t       record;
  v_lot     jsonb := '[]'::jsonb;
  v_total   int := 0;
  v_lots    int := 0;
  v_dernier timestamptz;
  v_texte   text := btrim(coalesce(p_message, ''));
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if v_texte = '' then
    raise exception 'Le message est vide.';
  end if;

  -- Garde-fou propre au message libre : il ne partage pas celui de la
  -- relance automatique, car ce sont deux gestes distincts. Envoyer une
  -- annonce ne doit pas bloquer la relance de cotisations du lendemain.
  select max(a.cree_le) into v_dernier
    from public.audit_log a
   where a.action = 'message_libre_masse';

  if not p_forcer and v_dernier is not null
     and v_dernier > now() - interval '24 hours' then
    raise exception 'Un message a déjà été envoyé le % (il y a moins de 24 heures). Cochez « envoyer quand même » pour passer outre.',
      to_char(v_dernier, 'DD/MM/YYYY à HH24:MI');
  end if;

  for v_m in select * from public.destinataires_message(p_audience, p_ids) loop
    -- Même enveloppe que tous les autres messages : « Bonjour Prénom »,
    -- le chemin vers l'espace membres, la signature.
    select * into v_t from public.texte_rappel_membre(v_m.id_membre, 'libre', v_texte);

    v_lot := v_lot || jsonb_build_object(
      'email',      v_m.courriel,
      'full_name',  v_m.nom,
      'first_name', v_m.prenom,
      'titre',      v_t.titre,
      'corps',      v_t.corps,
      'lien',       v_t.lien
    );
    v_total := v_total + 1;

    -- Paquets de 100, le maximum qu'accepte Resend en un appel.
    if jsonb_array_length(v_lot) >= 100 then
      perform public.notify_membre('rappel_masse',
        jsonb_build_object('destinataires', v_lot));
      v_lot := '[]'::jsonb;
      v_lots := v_lots + 1;
    end if;
  end loop;

  if jsonb_array_length(v_lot) > 0 then
    perform public.notify_membre('rappel_masse',
      jsonb_build_object('destinataires', v_lot));
    v_lots := v_lots + 1;
  end if;

  -- On ne trace QUE si quelque chose est parti : sinon le garde-fou se
  -- déclencherait après un envoi vide et bloquerait le vrai du lendemain.
  if v_total > 0 then
    perform public.journaliser('message_libre_masse', null,
      v_total || ' membre(s)',
      jsonb_build_object('audience', p_audience, 'total', v_total,
                         'lots', v_lots, 'force', p_forcer,
                         'extrait', left(v_texte, 200)));
  end if;

  return jsonb_build_object(
    'mis_en_file', v_total,
    'audience',    p_audience,
    'lots',        v_lots);
end;
$$;

revoke all on function public.envoyer_message_libre(text, text, boolean, uuid[])
  from public, anon;
grant execute on function public.envoyer_message_libre(text, text, boolean, uuid[])
  to authenticated;

-- L'ancienne signature à trois arguments de la phase 100 disparaît :
-- laissée en place, PostgreSQL aurait eu deux fonctions du même nom et
-- l'appel sans p_ids serait devenu ambigu.
drop function if exists public.envoyer_message_libre(text, text, boolean);
drop function if exists public.destinataires_message(text);
drop function if exists public.apercu_message_libre();

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - aucun envoi
-- ============================================================
-- a) Les quatre fonctions sont-elles en place et gardées ?
select p.proname, pg_get_function_arguments(p.oid) as arguments,
       case when p.prosecdef then 'security definer' else 'invoker' end as mode
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('destinataires_message', 'apercu_audiences',
                     'liste_membres_message', 'envoyer_message_libre')
 order by p.proname;

-- b) Le décompte de chaque audience, en SQL nu - le SQL Editor n'ayant
--    pas de session, il ne peut pas appeler les fonctions gardées.
with reperes as (
  select extract(year from now())::int as annee, extract(month from now())::int as mois
),
base as (
  select p.id, p.card_valid_until, p.fonction, r.annee, r.mois,
         case when extract(year from p.created_at)::int = r.annee
              then extract(month from p.created_at)::int else 1 end as premier_mois
    from public.profiles p cross join reperes r
   where p.status = 'approved' and p.is_active
     and coalesce(btrim(p.email), '') <> '' and position('@' in p.email) > 1
),
etat as (
  select b.*,
         (b.card_valid_until is null or b.card_valid_until < b.annee) as carte_expiree,
         (b.card_valid_until = b.annee) as carte_bientot,
         (select count(*) from generate_series(b.premier_mois, b.mois) as m
           where not (m = any(coalesce((select c.months_paid from public.cotisations c
                        where c.user_id = b.id and c.year = b.annee), '{}'::int[]))))::int > 0
           as en_retard
    from base b
)
select count(*)                                                as tous,
       count(*) filter (where carte_expiree)                    as carte_expiree,
       count(*) filter (where carte_bientot)                    as carte_expire_bientot,
       count(*) filter (where en_retard)                        as cotisation_retard,
       count(*) filter (where carte_expiree or en_retard)       as retardataires,
       count(*) filter (where coalesce(btrim(fonction),'') <> '') as bureau
  from etat;

-- c) Les membres sans adresse : ils ne recevront rien, quelle que soit
--    l'audience. À joindre par WhatsApp depuis leur fiche.
select p.full_name, p.phone, coalesce(btrim(p.fonction), '-') as fonction
  from public.profiles p
 where p.status = 'approved' and p.is_active
   and coalesce(btrim(p.email), '') = ''
 order by p.full_name;
