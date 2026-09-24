-- ============================================================
-- PHASE 117 - Usage de l'espace membres : le journal et les indicateurs
--
-- POURQUOI. L'espace membres compte une quinzaine de rubriques, et
-- personne ne sait lesquelles servent. Les statistiques d'administration
-- décrivent l'association - qui est membre, qui a payé - mais rien ne dit
-- si les membres ouvrent le Daara, le forum ou la médiathèque, ni combien
-- reviennent d'une semaine à l'autre.
--
-- CE QUE FAIT CE SCRIPT.
--   1. Une table « usage_visites » qui compte les ouvertures de page, par
--      membre, par rubrique et par JOUR. Une ligne par membre, rubrique et
--      jour : pas d'horodatage à la seconde, pas d'adresse IP, pas de
--      parcours reconstituable. De quoi répondre « quelle rubrique sert »
--      sans surveiller personne.
--   2. usage_visite(rubrique) : appelée par les pages de l'espace membres
--      au chargement. Elle ne lève jamais d'exception - un journal ne doit
--      pas casser une page - et n'écrit rien pour un visiteur non approuvé.
--   3. usage_kpi(jours) : réservée aux administrateurs, elle renvoie en un
--      seul appel tout ce qu'affiche la page Statistiques - comptes,
--      connexions, visites, rubriques, jour par jour, et l'activité de
--      contenu (quiz, leçons, forum, boutique, collectes).
--
-- AVANT le script : la page Statistiques affiche la section d'usage vide,
-- avec l'invitation à exécuter ce fichier. Les pages membres continuent de
-- fonctionner normalement - l'appel au journal échoue en silence.
--
-- APRÈS : le journal se remplit à partir des visites SUIVANTES. Les
-- chiffres de contenu (quiz, forum, leçons...) sont eux calculés sur
-- l'existant, et sont donc justes dès le premier affichage.
-- ============================================================

-- ===== 1. Le journal =====
create table if not exists public.usage_visites (
  user_id  uuid        not null references auth.users(id) on delete cascade,
  espace   text        not null,
  jour     date        not null default current_date,
  visites  int         not null default 0,
  vue_le   timestamptz not null default now(),
  primary key (user_id, espace, jour)
);

comment on table public.usage_visites is
  'Ouvertures de page dans l''espace membres, agrégées par membre, rubrique et jour. Écrite uniquement par usage_visite().';

create index if not exists usage_visites_jour_idx   on public.usage_visites (jour desc);
create index if not exists usage_visites_espace_idx on public.usage_visites (espace, jour desc);

alter table public.usage_visites enable row level security;

-- Personne n'écrit directement : usage_visite() est SECURITY DEFINER.
-- Un administrateur peut relire le journal brut si besoin ; les membres,
-- eux, n'y ont aucun accès - ni au leur, ni à celui des autres.
drop policy if exists "Admins lisent le journal d'usage" on public.usage_visites;
create policy "Admins lisent le journal d'usage"
  on public.usage_visites for select
  using (public.is_admin());

-- ===== 2. Enregistrer une visite =====
-- Silencieuse par construction : appelée à chaque ouverture de page, elle
-- ne doit jamais faire échouer ce que le membre était venu faire. Pas de
-- RAISE, pas de retour d'erreur.
create or replace function public.usage_visite(p_espace text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_espace text;
begin
  if auth.uid() is null then
    return;
  end if;
  if not public.is_approved_member() then
    return;
  end if;

  -- La rubrique vient du nom de la page : on n'accepte que des lettres,
  -- des chiffres et des tirets, et au plus 40 caractères.
  v_espace := left(lower(regexp_replace(coalesce(p_espace, ''), '[^a-zA-Z0-9-]', '', 'g')), 40);
  if v_espace = '' then
    return;
  end if;

  insert into public.usage_visites (user_id, espace, jour, visites, vue_le)
  values (auth.uid(), v_espace, current_date, 1, now())
  on conflict (user_id, espace, jour)
  do update set visites = public.usage_visites.visites + 1,
                vue_le  = now();
exception
  when others then
    return;   -- un journal muet vaut mieux qu'une page cassée
end;
$$;

revoke all on function public.usage_visite(text) from public, anon;
grant execute on function public.usage_visite(text) to authenticated;

-- ===== 3. Les indicateurs, en un seul appel =====
-- Un seul aller-retour, et tout le calcul côté serveur : la page
-- d'administration n'a pas à télécharger le journal pour le compter, ni à
-- interroger huit tables dont les règles de lecture diffèrent.
create or replace function public.usage_kpi(p_jours int default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jours  int;
  v_depuis timestamptz;
  v_date   date;
  v_res    jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accès réservé aux administrateurs.';
  end if;

  v_jours  := greatest(1, least(coalesce(p_jours, 30), 365));
  v_depuis := now() - make_interval(days => v_jours);
  v_date   := (v_depuis at time zone 'UTC')::date;

  select jsonb_build_object(
    'jours', v_jours,

    -- Les comptes : l'assise, indépendante de la période.
    'comptes', (
      select jsonb_build_object(
        'total',      count(*),
        'approuves',  count(*) filter (where status = 'approved'),
        'actifs',     count(*) filter (where status = 'approved' and is_active is distinct from false)
      ) from public.profiles
    ),

    -- Les connexions, lues dans auth.users : la seule trace de passage
    -- qui existait avant ce journal.
    'connexions', (
      select jsonb_build_object(
        'j7',      count(*) filter (where u.last_sign_in_at > now() - interval '7 days'),
        'j30',     count(*) filter (where u.last_sign_in_at > now() - interval '30 days'),
        'j90',     count(*) filter (where u.last_sign_in_at > now() - interval '90 days'),
        'jamais',  count(*) filter (where u.last_sign_in_at is null)
      )
      from auth.users u
      join public.profiles p on p.id = u.id
      where p.status = 'approved'
    ),

    -- Les visites de la période.
    'visites', (
      select jsonb_build_object(
        'total',   coalesce(sum(visites), 0),
        'membres', count(distinct user_id),
        'jours_ouvres', count(distinct jour)
      )
      from public.usage_visites
      where jour >= v_date
    ),

    -- Rubrique par rubrique, la plus ouverte en tête.
    'espaces', coalesce((
      select jsonb_agg(x order by x.visites desc)
      from (
        select espace,
               sum(visites)::int        as visites,
               count(distinct user_id)::int as membres
        from public.usage_visites
        where jour >= v_date
        group by espace
      ) x
    ), '[]'::jsonb),

    -- Jour par jour, pour voir si l'usage tient dans la durée.
    'serie', coalesce((
      select jsonb_agg(x order by x.jour)
      from (
        select jour::text                as jour,
               sum(visites)::int         as visites,
               count(distinct user_id)::int as membres
        from public.usage_visites
        where jour >= v_date
        group by jour
      ) x
    ), '[]'::jsonb),

    -- Les membres les plus assidus, sans les nommer : seul le nombre de
    -- jours de présence compte ici.
    'assiduite', (
      select jsonb_build_object(
        'un_jour',     count(*) filter (where n = 1),
        'deux_six',    count(*) filter (where n between 2 and 6),
        'sept_plus',   count(*) filter (where n >= 7)
      )
      from (
        select user_id, count(distinct jour) as n
        from public.usage_visites
        where jour >= v_date
        group by user_id
      ) t
    ),

    -- Ce que les membres font vraiment, lu dans les tables de contenu :
    -- ces chiffres-là sont justes des le premier affichage, journal ou pas.
    'contenus', jsonb_build_object(
      'quiz_tentatives', (select count(*) from public.quiz_attempts where taken_at >= v_depuis),
      'quiz_membres',    (select count(distinct user_id) from public.quiz_attempts where taken_at >= v_depuis),
      'lecons',          (select count(*) from public.medical_progress where coalesce(updated_at, completed_at) >= v_depuis),
      'cours_daara',     (select count(*) from public.daara_progress   where coalesce(updated_at, completed_at) >= v_depuis),
      'forum_sujets',    (select count(*) from public.forum_topics  where created_at >= v_depuis),
      'forum_reponses',  (select count(*) from public.forum_replies where created_at >= v_depuis),
      'commandes',       (select count(*) from public.orders where created_at >= v_depuis),
      'participations',  (select count(*) from public.collecte_participations where created_at >= v_depuis)
    )
  ) into v_res;

  return v_res;
end;
$$;

revoke all on function public.usage_kpi(int) from public, anon;
grant execute on function public.usage_kpi(int) to authenticated;

notify pgrst, 'reload schema';

-- ===== 4. Contrôle =====
-- On n'APPELLE ni usage_visite ni usage_kpi ici : dans l'éditeur SQL
-- personne n'est connecté, le contrôle d'accès refuserait, et l'échec
-- annulerait tout le script (leçon de la phase 115).
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'usage_visites'
 order by ordinal_position;

select proname, pg_get_function_identity_arguments(oid) as arguments
  from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('usage_visite', 'usage_kpi')
 order by proname;

select count(*) as visites_deja_enregistrees from public.usage_visites;
