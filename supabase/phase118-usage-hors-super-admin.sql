-- ============================================================
-- PHASE 118 - Les indicateurs d'usage ignorent les super-administrateurs
--
-- POURQUOI. Celui qui tient le site l'ouvre dix fois par jour pour
-- vérifier une page, un bouton, une fiche. Ces passages-là ne disent
-- rien de l'usage réel : ils gonflent les visites, placent le Centre
-- d'administration en tête des rubriques, et font passer pour assidu un
-- compte qui ne fait que du contrôle. Sur une association de deux cents
-- membres dont quelques dizaines viennent, un seul compte de ce genre
-- suffit à fausser la lecture.
--
-- CE QUE FAIT CE SCRIPT. Il réécrit usage_kpi() pour écarter, partout,
-- les comptes dont le rôle est « super_admin » : visites, rubriques,
-- frise, assiduité, connexions, décompte des comptes, et jusqu'à
-- l'activité de contenu (quiz, leçons, forum, boutique, collectes).
--
-- CE QU'IL NE FAIT PAS. Il n'efface rien : le journal continue
-- d'enregistrer ces passages, ils sont simplement écartés à la lecture.
-- Revenir en arrière, ou écarter aussi les administrateurs ordinaires,
-- ne demande que de changer la liste ci-dessous et de rejouer ce script.
--
-- Les administrateurs NON super-administrateurs restent comptés : ce
-- sont des membres comme les autres, qui consultent le Daara ou le
-- forum. Si leurs vérifications faussaient à leur tour la lecture,
-- remplacer « role = 'super_admin' » par « role in ('admin',
-- 'super_admin') » dans la requête qui remplit v_exclus.
-- ============================================================

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
  v_exclus uuid[];
  v_res    jsonb;
begin
  if not public.is_admin() then
    raise exception 'Accès réservé aux administrateurs.';
  end if;

  v_jours  := greatest(1, least(coalesce(p_jours, 30), 365));
  v_depuis := now() - make_interval(days => v_jours);
  v_date   := (v_depuis at time zone 'UTC')::date;

  -- Les comptes écartés de toute la mesure.
  select coalesce(array_agg(id), '{}'::uuid[])
    into v_exclus
    from public.profiles
   where role = 'super_admin';

  select jsonb_build_object(
    'jours', v_jours,
    'exclus', coalesce(array_length(v_exclus, 1), 0),

    -- Les comptes : l'assise, indépendante de la période.
    'comptes', (
      select jsonb_build_object(
        'total',      count(*),
        'approuves',  count(*) filter (where status = 'approved'),
        'actifs',     count(*) filter (where status = 'approved' and is_active is distinct from false)
      ) from public.profiles
      where id <> all (v_exclus)
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
        and p.id <> all (v_exclus)
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
        and user_id <> all (v_exclus)
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
          and user_id <> all (v_exclus)
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
          and user_id <> all (v_exclus)
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
          and user_id <> all (v_exclus)
        group by user_id
      ) t
    ),

    -- Ce que les membres font vraiment, lu dans les tables de contenu :
    -- ces chiffres-là sont justes dès le premier affichage, journal ou pas.
    'contenus', jsonb_build_object(
      'quiz_tentatives', (select count(*) from public.quiz_attempts
                           where taken_at >= v_depuis and user_id <> all (v_exclus)),
      'quiz_membres',    (select count(distinct user_id) from public.quiz_attempts
                           where taken_at >= v_depuis and user_id <> all (v_exclus)),
      'lecons',          (select count(*) from public.medical_progress
                           where coalesce(updated_at, completed_at) >= v_depuis
                             and user_id <> all (v_exclus)),
      'cours_daara',     (select count(*) from public.daara_progress
                           where coalesce(updated_at, completed_at) >= v_depuis
                             and user_id <> all (v_exclus)),
      'forum_sujets',    (select count(*) from public.forum_topics
                           where created_at >= v_depuis and author_id <> all (v_exclus)),
      'forum_reponses',  (select count(*) from public.forum_replies
                           where created_at >= v_depuis and author_id <> all (v_exclus)),
      'commandes',       (select count(*) from public.orders
                           where created_at >= v_depuis
                             and (user_id is null or user_id <> all (v_exclus))),
      'participations',  (select count(*) from public.collecte_participations
                           where created_at >= v_depuis and user_id <> all (v_exclus))
    )
  ) into v_res;

  return v_res;
end;
$$;

revoke all on function public.usage_kpi(int) from public, anon;
grant execute on function public.usage_kpi(int) to authenticated;

notify pgrst, 'reload schema';

-- ===== Contrôle =====
-- On n'APPELLE pas usage_kpi ici : dans l'éditeur SQL personne n'est
-- connecté, le contrôle d'accès refuserait, et l'échec annulerait tout
-- le script (leçon de la phase 115).
select count(*) as comptes_ecartes
  from public.profiles
 where role = 'super_admin';

-- Ce que ces comptes pèsent dans le journal, pour mesurer l'écart.
select coalesce(sum(v.visites), 0) as visites_ecartees,
       count(distinct v.jour)      as jours_concernes
  from public.usage_visites v
  join public.profiles p on p.id = v.user_id
 where p.role = 'super_admin';
