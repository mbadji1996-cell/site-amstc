-- ============================================================
-- PHASE 96 - Relancer d'un clic tous les retardataires, par courriel
--
-- LE BESOIN. Prévenir un membre en retard se fait déjà, depuis sa fiche
-- (phase 57) ou depuis Telegram (phase 89) : un membre, un clic. Quand
-- ils sont cent quatre-vingts, personne ne le fait. Il manquait le geste
-- collectif : un bouton qui écrit à TOUS ceux dont la carte a expiré ou
-- dont les cotisations ont pris du retard.
--
-- LE MESSAGE N'EST PAS NOUVEAU. Chacun reçoit exactement le texte que
-- lui aurait envoyé un administrateur depuis sa fiche : la composition
-- passe par texte_rappel_membre(), déjà en place. Corriger une tournure
-- là-bas corrige les deux canaux d'un coup ; il n'y a pas deux versions
-- du même rappel à tenir à jour.
--
-- ------------------------------------------------------------
-- POURQUOI L'ENVOI PART EN LOTS, ET NON MEMBRE PAR MEMBRE
-- ------------------------------------------------------------
-- La tentation était d'appeler notify_membre() dans une boucle. C'aurait
-- été un piège : chaque appel déclenche une requête HTTP vers la fonction
-- Edge, donc un envoi Resend, et Resend limite le débit. Deux cents
-- appels lancés dans la même seconde, ce sont des refus 429 - et
-- notify_membre AVALE ses erreurs (« un souci réseau ne doit jamais
-- empêcher un administrateur de valider un compte »). Le bouton aurait
-- donc annoncé deux cents envois pendant qu'une bonne partie partait à la
-- poubelle, sans la moindre trace.
--
-- On envoie donc par PAQUETS DE 50, chacun en un seul appel, que la
-- fonction Edge remet à Resend par son point d'entrée « batch ». Deux
-- cents membres, ce sont quatre appels au lieu de deux cents : aucun
-- risque de plafond.
--
-- LE DÉLAI DE PG_NET, LUI, EST DÉPASSÉ - ET C'EST NORMAL. pg_net coupe
-- la communication au bout de 5 secondes. Un démarrage à froid du
-- conteneur, plus l'appel à Resend, va au-delà : 5801 ms mesurées pour
-- UN SEUL destinataire lors de la mise en service. La fonction Edge
-- répond donc AUSSITÔT (202) et poursuit l'envoi en arrière-plan ; le
-- délai de pg_net ne concerne plus que l'accusé de réception, jamais
-- l'envoi lui-même.
--
-- CE QUE LE BOUTON PEUT PROMETTRE, ET CE QU'IL NE PEUT PAS. pg_net envoie
-- sans attendre la réponse : la fonction rend la main dès les lots
-- déposés. Elle annonce donc des courriels MIS EN FILE, jamais des
-- courriels « reçus ». La preuve de distribution est chez Resend et dans
-- les journaux de la fonction Edge - c'est écrit sur l'écran, pour que
-- personne ne lise « 180 envoyés » comme « 180 arrivés ».
--
-- ------------------------------------------------------------
-- QUI EST CONSIDÉRÉ EN RETARD
-- ------------------------------------------------------------
--   Carte expirée        : card_valid_until absent, ou antérieur à
--                          l'année en cours. Même définition que
--                          l'audience WhatsApp du même nom (phase 93) :
--                          les deux canaux visent les mêmes personnes.
--   Cotisation en retard : il manque au moins un mois ÉCHU de l'année en
--                          cours. Plus large que l'audience WhatsApp,
--                          qui ne regarde que le mois courant - celui
--                          qui a sauté mars et réglé août est en retard,
--                          et n'était visé par rien jusqu'ici.
--
-- ON NE RÉCLAME PAS LES MOIS D'AVANT L'ARRIVÉE. Un compte ouvert en août
-- ne doit rien pour janvier. Le premier mois dû est donc le mois
-- d'ouverture du compte pour qui est arrivé cette année, janvier pour les
-- autres. Sans cette précaution, toute nouvelle recrue recevrait une
-- relance le lendemain de son inscription.
--
-- LA CARTE PRIME SUR LA COTISATION. Qui a les deux reçoit le rappel de
-- carte, et lui seul : deux courriels le même jour pour une même
-- situation feraient désordre, et renouveler la carte est le geste qui
-- débloque le reste.
--
-- SANS ADRESSE, PAS DE COURRIEL. Ceux qui n'en ont pas ne sont pas
-- comptés comme des échecs : ils sont dénombrés à part, à joindre par
-- WhatsApp depuis leur fiche. L'écran le dit.
--
-- GARDE-FOU DES 24 HEURES. Un envoi en masse ne se rattrape pas. Un
-- second appel dans les 24 heures est refusé, sauf demande explicite
-- (p_forcer) - le double-clic, la page rechargée, l'hésitation à deux
-- administrateurs ne doivent pas valoir deux relances.
--
-- PRÉREQUIS : phases 50 (notify_membre), 51 (journal), 57
-- (texte_rappel_membre). La fonction Edge notify-membre doit être
-- redéployée : elle gagne le type « rappel_masse ».
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger. AUCUN ENVOI n'a lieu à l'exécution.
--
-- NOTE SUR LE SQL EDITOR. Il s'exécute sans session : auth.uid() y
-- est vide, donc is_admin() répond toujours « non ». Appeler ici
-- l'une des trois fonctions ci-dessous renverrait « Accès refusé » -
-- ce qui prouve que la garde tient, et non qu'il y a un défaut. Les
-- contrôles en fin de fichier refont donc la sélection en SQL nu.
-- ============================================================

-- ============================================================
-- 1. QUI SERAIT RELANCÉ - lecture seule, aucun envoi
-- ============================================================
-- Appelée par l'écran pour afficher la liste AVANT d'envoyer, et par la
-- fonction d'envoi pour constituer ses lots : les deux voient donc
-- rigoureusement les mêmes personnes.
--
-- NOMS DES COLONNES DE SORTIE. « returns table(...) » déclare chaque nom
-- comme une variable de la fonction ; un nom qui existerait aussi dans
-- profiles rendrait la requête ambiguë et la ferait échouer à
-- l'exécution (erreur 42702, déjà rencontrée en phase 93). D'où
-- id_membre, nom, courriel plutôt que id, full_name, email.
create or replace function public.membres_a_relancer()
returns table (
  id_membre     uuid,
  nom           text,
  prenom        text,
  courriel      text,
  motif         text,
  carte_jusqu_a int,
  mois_impayes  int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- GARDE INDISPENSABLE. La fonction est SECURITY DEFINER : elle lit
  -- profiles en passant outre les règles d'accès. Sans ce contrôle,
  -- n'importe quel membre connecté appellerait la RPC et repartirait
  -- avec le nom, l'adresse et l'état de cotisation de tous les
  -- retardataires. Le droit « authenticated » ne suffit pas à protéger
  -- une fonction qui, par construction, voit tout.
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  return query
  with reperes as (
    select extract(year from now())::int as annee,
           extract(month from now())::int as mois
  ),
  candidats as (
    select p.id, p.full_name, p.first_name, p.email, p.card_valid_until,
           r.annee, r.mois,
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
  compte as (
    select c.*,
           (select count(*)
              from generate_series(c.premier_mois, c.mois) as m
             where not (m = any(
               coalesce((select ct.months_paid
                           from public.cotisations ct
                          where ct.user_id = c.id and ct.year = c.annee),
                        '{}'::int[]))))::int as impayes
      from candidats c
  )
  select k.id, k.full_name, k.first_name, k.email,
         case when k.card_valid_until is null or k.card_valid_until < k.annee
              then 'carte_expiree' else 'cotisation_retard' end,
         k.card_valid_until,
         k.impayes
    from compte k
   where k.card_valid_until is null
      or k.card_valid_until < k.annee
      or k.impayes > 0
   order by case when k.card_valid_until is null or k.card_valid_until < k.annee
                 then 0 else 1 end,
            k.full_name;
end;
$$;

revoke all on function public.membres_a_relancer() from public, anon;
grant execute on function public.membres_a_relancer() to authenticated;

-- Le décompte affiché sur l'écran : combien par motif, combien
-- d'injoignables faute d'adresse, et quand remonte la dernière relance.
create or replace function public.apercu_relance_courriel()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_annee int := extract(year from now())::int;
  v_mois  int := extract(month from now())::int;
  v_res   jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select jsonb_build_object(
    'total',             count(*),
    'carte_expiree',     count(*) filter (where m.motif = 'carte_expiree'),
    'cotisation_retard', count(*) filter (where m.motif = 'cotisation_retard')
  ) into v_res
  from public.membres_a_relancer() m;

  return v_res
    -- Concernés mais sans adresse : ils ne recevront rien, et il vaut
    -- mieux le savoir que de les croire prévenus.
    || jsonb_build_object('sans_courriel', (
         select count(*) from public.profiles p
          where p.status = 'approved' and p.is_active
            and coalesce(btrim(p.email), '') = ''
            and (p.card_valid_until is null or p.card_valid_until < v_annee
                 or not exists (
                   select 1 from public.cotisations ct
                    where ct.user_id = p.id and ct.year = v_annee
                      and v_mois = any(ct.months_paid)))))
    || jsonb_build_object('derniere_relance', (
         select max(a.cree_le) from public.audit_log a
          where a.action = 'relance_masse_courriel'));
end;
$$;

revoke all on function public.apercu_relance_courriel() from public, anon;
grant execute on function public.apercu_relance_courriel() to authenticated;

-- ============================================================
-- 2. L'ENVOI
-- ============================================================
create or replace function public.relancer_par_courriel(p_forcer boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m           record;
  v_t           record;
  v_lot         jsonb := '[]'::jsonb;
  v_total       int := 0;
  v_cartes      int := 0;
  v_cotisations int := 0;
  v_lots        int := 0;
  v_derniere    timestamptz;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  -- Garde-fou : une relance en masse ne se rattrape pas.
  select max(a.cree_le) into v_derniere
    from public.audit_log a
   where a.action = 'relance_masse_courriel';

  if not p_forcer and v_derniere is not null
     and v_derniere > now() - interval '24 hours' then
    raise exception 'Une relance a déjà été envoyée le % (il y a moins de 24 heures). Cochez « envoyer quand même » pour passer outre.',
      to_char(v_derniere, 'DD/MM/YYYY à HH24:MI');
  end if;

  for v_m in select * from public.membres_a_relancer() loop
    -- Le texte vient d'où viennent les rappels individuels : une seule
    -- rédaction pour les deux canaux.
    select * into v_t from public.texte_rappel_membre(v_m.id_membre, v_m.motif);

    v_lot := v_lot || jsonb_build_object(
      'email',      v_m.courriel,
      'full_name',  v_m.nom,
      'first_name', v_m.prenom,
      'titre',      v_t.titre,
      'corps',      v_t.corps,
      'lien',       'https://amstc.org/membres/profil.html'
    );
    v_total := v_total + 1;
    if v_m.motif = 'carte_expiree'
      then v_cartes := v_cartes + 1;
      else v_cotisations := v_cotisations + 1;
    end if;

    if jsonb_array_length(v_lot) >= 50 then
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

  -- On ne trace QUE si quelque chose est parti : sinon le garde-fou des
  -- 24 heures se déclencherait après un envoi vide et bloquerait la
  -- vraie relance du lendemain.
  if v_total > 0 then
    perform public.journaliser('relance_masse_courriel', null,
      v_total || ' membre(s)',
      jsonb_build_object('canal', 'email', 'total', v_total,
                         'carte_expiree', v_cartes,
                         'cotisation_retard', v_cotisations,
                         'lots', v_lots, 'force', p_forcer));
  end if;

  return jsonb_build_object(
    'mis_en_file',       v_total,
    'carte_expiree',     v_cartes,
    'cotisation_retard', v_cotisations,
    'lots',              v_lots);
end;
$$;

revoke all on function public.relancer_par_courriel(boolean) from public, anon;
grant execute on function public.relancer_par_courriel(boolean) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - aucun envoi n'a lieu ici
--
-- POURQUOI CES REQUÊTES N'APPELLENT PAS LES FONCTIONS CI-DESSUS.
-- Le SQL Editor s'exécute SANS SESSION : auth.uid() y est vide, donc
-- is_admin() répond « non » et toute fonction gardée répondrait
-- « Accès refusé ». Ce n'est pas un défaut des fonctions - c'est la
-- preuve que la garde fonctionne. Les contrôles refont donc la même
-- sélection en SQL nu, ce qui a l'avantage de montrer noir sur blanc
-- ce que la fonction calcule.
-- ============================================================

-- a) La liste des personnes visées, avec leur motif.
--    À LIRE AVANT LE PREMIER ENVOI : c'est le seul moment où l'on peut
--    encore dire non.
with reperes as (
  select extract(year from now())::int as annee,
         extract(month from now())::int as mois
),
candidats as (
  select p.id, p.full_name, p.email, p.card_valid_until,
         r.annee, r.mois,
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
compte as (
  select c.*,
         (select count(*)
            from generate_series(c.premier_mois, c.mois) as m
           where not (m = any(
             coalesce((select ct.months_paid
                         from public.cotisations ct
                        where ct.user_id = c.id and ct.year = c.annee),
                      '{}'::int[]))))::int as impayes
    from candidats c
)
select k.full_name as nom,
       k.email     as courriel,
       case when k.card_valid_until is null or k.card_valid_until < k.annee
            then 'carte_expiree' else 'cotisation_retard' end as motif,
       coalesce(k.card_valid_until::text, 'jamais réglée') as carte_jusqu_a,
       k.impayes as mois_impayes
  from compte k
 where k.card_valid_until is null
    or k.card_valid_until < k.annee
    or k.impayes > 0
 order by motif, nom;

-- b) Le même décompte, résumé : c'est ce que l'écran affichera.
with reperes as (
  select extract(year from now())::int as annee,
         extract(month from now())::int as mois
),
candidats as (
  select p.id, p.card_valid_until, r.annee, r.mois,
         case when extract(year from p.created_at)::int = r.annee
              then extract(month from p.created_at)::int
              else 1 end as premier_mois
    from public.profiles p
    cross join reperes r
   where p.status = 'approved' and p.is_active
     and coalesce(btrim(p.email), '') <> ''
     and position('@' in p.email) > 1
),
compte as (
  select c.*,
         (select count(*)
            from generate_series(c.premier_mois, c.mois) as m
           where not (m = any(
             coalesce((select ct.months_paid
                         from public.cotisations ct
                        where ct.user_id = c.id and ct.year = c.annee),
                      '{}'::int[]))))::int as impayes
    from candidats c
)
select count(*) filter (where k.card_valid_until is null
                           or k.card_valid_until < k.annee) as carte_expiree,
       count(*) filter (where k.card_valid_until is not null
                          and k.card_valid_until >= k.annee
                          and k.impayes > 0)                as cotisation_retard,
       count(*)                                             as total
  from compte k
 where k.card_valid_until is null
    or k.card_valid_until < k.annee
    or k.impayes > 0;

-- c) Les concernés SANS adresse : ils ne recevront rien.
--    À joindre par WhatsApp, depuis leur fiche.
select p.full_name, p.phone, p.card_valid_until
  from public.profiles p
 where p.status = 'approved' and p.is_active
   and coalesce(btrim(p.email), '') = ''
 order by p.full_name;

-- d) Les fonctions sont-elles bien en place, et bien gardées ?
select p.proname,
       case when p.prosecdef then 'security definer' else 'invoker' end as mode
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('membres_a_relancer', 'apercu_relance_courriel',
                     'relancer_par_courriel')
 order by p.proname;

-- e) Preuve que la garde tient : depuis le SQL Editor, sans session,
--    l'appel DOIT echouer avec « Accès refusé ». Si cette ligne renvoie
--    des données au lieu d'une erreur, la garde ne fonctionne pas.
-- select * from public.membres_a_relancer();
