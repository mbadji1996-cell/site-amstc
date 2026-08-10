-- ============================================================
-- PHASE 58 - État d'adhésion et de cotisation visible par membre,
-- et saisie des cotisations déjà réglées
--
-- Deux besoins :
--   1. Voir d'un coup d'œil, dans la liste des membres, où en est chacun -
--      validité de sa carte et nombre de mois cotisés cette année.
--   2. Enregistrer les cotisations versées AVANT la mise en service du
--      site : elles n'ont laissé aucune trace de paiement déclaré, et le
--      membre apparaît donc à tort comme n'ayant jamais cotisé.
--
-- La saisie rétroactive ne crée volontairement PAS de faux paiements dans
-- cotisation_payments : cette table est le registre des déclarations
-- faites par les membres, et y injecter des lignes fabriquées fausserait
-- les encaissements du tableau de bord. On écrit directement dans
-- `cotisations`, qui est l'état de référence - exactement ce que fait la
-- validation d'un paiement.
--
-- PRÉREQUIS : phase7 (tables) et phase51 (journal).
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== Lecture : l'état de tous les membres pour une année =====
create or replace function public.cotisations_membres(p_year int default null)
returns table (user_id uuid, year int, months_paid int[])
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  return query
    select c.user_id, c.year, c.months_paid
      from public.cotisations c
     where c.year = coalesce(p_year, extract(year from now())::int);
end;
$$;

-- ===== Écriture : corriger les mois cotisés d'un membre =====
create or replace function public.set_cotisations_membre(
  p_user_id uuid, p_year int, p_months int[]
)
returns int[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mois int[];
  v_avant int[];
  v_nom text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if p_year is null or p_year < 2014 or p_year > extract(year from now())::int + 1 then
    raise exception 'Année invalide.';
  end if;

  -- Doublons retirés, valeurs hors 1-12 rejetées, ordre stable : la
  -- grille du site coche des mois, elle ne doit pas pouvoir enregistrer
  -- un « mois 0 » ou deux fois le même.
  select array(
    select distinct m from unnest(coalesce(p_months, '{}'::int[])) as m
     where m between 1 and 12
     order by m
  ) into v_mois;

  select months_paid into v_avant
    from public.cotisations where user_id = p_user_id and year = p_year;

  insert into public.cotisations (user_id, year, months_paid)
  values (p_user_id, p_year, v_mois)
  on conflict (user_id, year) do update set months_paid = excluded.months_paid;

  select full_name into v_nom from public.profiles where id = p_user_id;
  perform public.journaliser('cotisations_modifiees', p_user_id,
    coalesce(v_nom, '(sans nom)'),
    jsonb_build_object('annee', p_year,
                       'avant', coalesce(array_length(v_avant, 1), 0),
                       'apres', coalesce(array_length(v_mois, 1), 0)));

  return v_mois;
end;
$$;

revoke all on function public.cotisations_membres(int) from public, anon;
revoke all on function public.set_cotisations_membre(uuid, int, int[]) from public, anon;
grant execute on function public.cotisations_membres(int) to authenticated;
grant execute on function public.set_cotisations_membre(uuid, int, int[]) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle.
select proname from pg_proc
 where proname in ('cotisations_membres','set_cotisations_membre')
 order by proname;
