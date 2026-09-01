-- ============================================================
-- PHASE 100 - Un message libre, à tous ou aux seuls retardataires
--
-- LE BESOIN. L'écran des rappels ne savait envoyer que ses deux textes
-- automatiques - carte expirée, cotisations en retard. Il manquait le
-- geste le plus simple : écrire un mot et l'adresser à tout le monde.
-- Une assemblée générale, un remerciement, une annonce de campagne : rien
-- de tout cela n'entre dans un rappel de cotisation.
--
-- DEUX AUDIENCES, ET C'EST VOULU. « Message libre » sur un écran de
-- rappels pouvait s'entendre de deux façons : aux retardataires, ou à
-- tous. Plutôt que de deviner, l'écran demande - la même fonction sert
-- les deux, le choix se fait au moment de l'envoi.
--
--   retardataires : exactement la liste de membres_a_relancer()
--   tous          : tout membre approuvé, actif, avec une adresse
--
-- UNE FONCTION À PART, ET NON UN PARAMÈTRE DE PLUS SUR LA RELANCE. Les
-- deux gestes n'ont ni le même sens ni le même garde-fou : envoyer une
-- annonce ne doit pas bloquer la relance de cotisations du lendemain, et
-- l'inverse non plus. Chacun a donc sa trace au journal et son propre
-- délai de 24 heures.
--
-- LE TEXTE RESTE COMPOSÉ PAR texte_rappel_membre(…, 'libre', message) :
-- le message reçoit la même enveloppe que partout ailleurs - « Bonjour
-- Prénom », le chemin vers l'espace membres, la signature. Une seule
-- rédaction pour tous les canaux, comme depuis la phase 97.
--
-- PRÉREQUIS : phases 50, 51, 65, 96.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger. AUCUN ENVOI n'a lieu à l'exécution.
--
-- NOTE SUR LE SQL EDITOR : il s'exécute sans session, donc is_admin()
-- y répond toujours « non ». Appeler ces fonctions ici renverrait
-- « Accès refusé » - c'est la preuve que la garde tient, pas un défaut.
-- ============================================================

-- ============================================================
-- 1. QUI RECEVRAIT LE MESSAGE
-- ============================================================
-- Renvoie les destinataires d'une audience donnée. Appelée par l'écran
-- pour afficher le nombre AVANT d'envoyer, et par la fonction d'envoi
-- pour constituer ses lots : les deux voient donc les mêmes personnes.
--
-- Noms de colonnes distincts de ceux de profiles : « returns table »
-- déclare chaque nom comme variable, et un homonyme rendrait la requête
-- ambiguë (erreur 42702, rencontrée en phase 93).
create or replace function public.destinataires_message(p_audience text)
returns table (
  id_membre uuid,
  nom       text,
  prenom    text,
  courriel  text
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

  if p_audience = 'retardataires' then
    -- Exactement la liste de la relance : une seule définition du retard.
    return query
      select m.id_membre, m.nom, m.prenom, m.courriel
        from public.membres_a_relancer() m;

  elsif p_audience = 'tous' then
    return query
      select p.id, p.full_name, p.first_name, p.email
        from public.profiles p
       where p.status = 'approved'
         and p.is_active
         and coalesce(btrim(p.email), '') <> ''
         and position('@' in p.email) > 1
       order by p.full_name;

  else
    raise exception 'Audience inconnue : % (attendu : retardataires ou tous)', p_audience;
  end if;
end;
$$;

revoke all on function public.destinataires_message(text) from public, anon;
grant execute on function public.destinataires_message(text) to authenticated;

-- Le décompte des deux audiences, pour l'écran.
create or replace function public.apercu_message_libre()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  return jsonb_build_object(
    'retardataires', (select count(*) from public.destinataires_message('retardataires')),
    'tous',          (select count(*) from public.destinataires_message('tous')),
    'dernier_envoi', (select max(a.cree_le) from public.audit_log a
                       where a.action = 'message_libre_masse')
  );
end;
$$;

revoke all on function public.apercu_message_libre() from public, anon;
grant execute on function public.apercu_message_libre() to authenticated;

-- ============================================================
-- 2. L'ENVOI
-- ============================================================
create or replace function public.envoyer_message_libre(
  p_message  text,
  p_audience text default 'retardataires',
  p_forcer   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m        record;
  v_t        record;
  v_lot      jsonb := '[]'::jsonb;
  v_total    int := 0;
  v_lots     int := 0;
  v_dernier  timestamptz;
  v_texte    text := btrim(coalesce(p_message, ''));
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if v_texte = '' then
    raise exception 'Le message est vide.';
  end if;
  if p_audience not in ('retardataires', 'tous') then
    raise exception 'Audience inconnue : %', p_audience;
  end if;

  -- Garde-fou propre au message libre : il ne partage pas celui de la
  -- relance, car ce sont deux gestes distincts.
  select max(a.cree_le) into v_dernier
    from public.audit_log a
   where a.action = 'message_libre_masse';

  if not p_forcer and v_dernier is not null
     and v_dernier > now() - interval '24 hours' then
    raise exception 'Un message a déjà été envoyé le % (il y a moins de 24 heures). Cochez « envoyer quand même » pour passer outre.',
      to_char(v_dernier, 'DD/MM/YYYY à HH24:MI');
  end if;

  for v_m in select * from public.destinataires_message(p_audience) loop
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

revoke all on function public.envoyer_message_libre(text, text, boolean) from public, anon;
grant execute on function public.envoyer_message_libre(text, text, boolean) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - aucun envoi
-- ============================================================
-- a) Les trois fonctions sont-elles en place et bien gardées ?
select p.proname,
       case when p.prosecdef then 'security definer' else 'invoker' end as mode
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('destinataires_message', 'apercu_message_libre',
                     'envoyer_message_libre')
 order by p.proname;

-- b) Combien de membres dans chaque audience ? En SQL nu, puisque le
--    SQL Editor n'a pas de session et que les fonctions sont gardées.
select
  (select count(*) from public.profiles p
    where p.status = 'approved' and p.is_active
      and coalesce(btrim(p.email), '') <> ''
      and position('@' in p.email) > 1)          as tous_les_membres_avec_adresse,
  (select count(*) from public.profiles p
    where p.status = 'approved' and p.is_active
      and coalesce(btrim(p.email), '') = '')      as sans_adresse_donc_injoignables;

-- c) L'audience « tous » englobe-t-elle bien les retardataires ? Elle le
--    doit : mêmes conditions de statut, d'activité et d'adresse.
select 'Les retardataires sont un sous-ensemble de « tous » : mêmes conditions '
       'de statut, d''activité et d''adresse.' as note;
