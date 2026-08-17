-- ============================================================
-- PHASE 92 - Interroger l'association depuis Telegram
--
-- LE MANQUE. Les boutons répondent à ce qui ARRIVE ; les commandes de la
-- phase 90 cherchent une personne. Rien ne permettait de demander l'état
-- des lieux : ce qui attend, qui attend, ce qui a été payé, quelles
-- cartes n'ont pas trouvé leur propriétaire. Il fallait ouvrir le site.
--
-- SIX RÉPONSES, chacune joignable par une commande ET par un bouton -
-- « /point » sert de sommaire, et l'on passe de l'une à l'autre sans
-- retaper quoi que ce soit :
--
--   /point          ce qui attend, tous onglets confondus
--   /attente        QUI attend, nommément, avec un bouton par dossier
--   /justificatifs  les captures reçues et non classées, réaffichées
--   /cotisations    l'état des cotisations de l'année
--   /cartes         les cartes non attribuées, dans les deux sens
--   /aide           la liste de tout cela
--
-- « CARTES NON ATTRIBUÉES » RECOUVRE DEUX CHOSES, et les confondre fait
-- chercher au mauvais endroit :
--   1. les cartes du REGISTRE que personne n'a réclamées - des gens qui
--      existent sur le papier mais n'ont jamais créé de compte ;
--   2. les MEMBRES INSCRITS à qui aucun numéro n'a été donné - l'inverse
--      exact : le compte existe, la carte manque.
-- Les deux listes sont renvoyées séparément.
--
-- AU PASSAGE : les compteurs du point du jour, jusqu'ici recopiés dans
-- rapport_matinal puis dans relancer_dossiers_en_attente, sont réunis
-- dans une seule fonction. Trois copies finissent toujours par diverger,
-- et c'est le genre d'écart qu'on ne remarque jamais.
--
-- PRÉREQUIS : phases 89, 90 et 91.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. LES COMPTEURS, EN UN SEUL ENDROIT
-- ============================================================
-- Renvoie { lignes: [ {libelle, nombre} ], total }.
--
-- p_depuis : ne compter que ce qui attend depuis cette date. Null pour
-- tout compter - c'est ce que fait le point du jour ; la relance des
-- dossiers oubliés, elle, passe un seuil.
--
-- Chaque compteur est isolé : une table absente ou sans created_at est
-- ignorée, elle ne fait pas échouer le reste.
create or replace function public.compteurs_attente(p_depuis timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_lignes jsonb := '[]'::jsonb;
  v_total  int := 0;
  v_n      int;
  -- « infinity », et surtout pas « -infinity » : sans date de seuil il
  -- faut TOUT compter, or « created_at < -infinity » ne ramène jamais
  -- rien - le point du jour aurait annoncé zéro en permanence.
  v_d      timestamptz := coalesce(p_depuis, 'infinity'::timestamptz);
begin
  begin
    select count(*) into v_n from public.profiles
     where status = 'pending' and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'inscription(s) en attente', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.card_validity_payments
     where status = 'pending' and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de validité à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.cotisation_payments
     where status = 'pending' and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de cotisation à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.justificatifs_paiement
     where statut = 'recu' and recu_le < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'justificatif(s) reçu(s) non classé(s)', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.collecte_participations
     where status = 'pending' and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'participation(s) à une collecte à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.orders
     where status in ('pending', 'paid', 'processing') and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'commande(s) boutique à traiter', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.member_cards
     where claim_status = 'pending' and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'réclamation(s) de carte à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  begin
    select count(*) into v_n from public.campaign_requests
     where status = 'en_attente' and created_at < v_d;
    v_lignes := v_lignes || jsonb_build_object('libelle', 'demande(s) de campagne à étudier', 'nombre', v_n);
    v_total := v_total + v_n;
  exception when others then null; end;

  -- Doublons probables (phase 78). PAS comptés dans le total : ces
  -- inscriptions figurent déjà dans le premier compteur, les additionner
  -- gonflerait le bilan. Recalculé ici plutôt qu'appelé, la fonction
  -- d'origine filtrant sur is_admin() - or le cron n'a pas d'utilisateur.
  begin
    if to_regproc('public.nom_cle') is not null then
      select count(distinct a.id) into v_n
        from public.profiles a
        join public.profiles e
          on e.id <> a.id and e.status <> 'pending'
         and (
           (public.telephone_cle(a.phone) is not null
            and length(public.telephone_cle(a.phone)) >= 9
            and public.telephone_cle(a.phone) = public.telephone_cle(e.phone))
           or
           (public.nom_cle(a.full_name) is not null
            and length(public.nom_cle(a.full_name)) >= 5
            and public.nom_cle(a.full_name) = public.nom_cle(e.full_name))
         )
       where a.status = 'pending' and a.created_at < v_d;
      if v_n > 0 then
        v_lignes := v_lignes || jsonb_build_object(
          'libelle', 'inscription(s) en attente ressemblant à un compte existant', 'nombre', v_n);
      end if;
    end if;
  exception when others then null; end;

  return jsonb_build_object('lignes', v_lignes, 'total', v_total);
end;
$$;

revoke all on function public.compteurs_attente(timestamptz) from public, anon;
grant execute on function public.compteurs_attente(timestamptz) to authenticated, service_role;

-- Les deux fonctions planifiées reposent désormais dessus.
create or replace function public.rapport_matinal(p_toujours boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c      jsonb := public.compteurs_attente(null);
  v_lignes jsonb := v_c->'lignes';
  v_total  int   := (v_c->>'total')::int;
begin
  -- Rien à traiter : on se tait, sauf demande explicite. Une
  -- notification quotidienne vide finit par être ignorée, et c'est alors
  -- la vraie qui passe inaperçue.
  if v_total = 0 and not p_toujours then
    return jsonb_build_object('envoye', false, 'total', 0, 'lignes', v_lignes);
  end if;

  begin
    perform public.notify_admin('rapport_matinal', jsonb_build_object('lignes', v_lignes));
  exception when others then
    raise warning 'rapport_matinal : envoi échoué : %', sqlerrm;
    return jsonb_build_object('envoye', false, 'erreur', sqlerrm, 'lignes', v_lignes);
  end;

  return jsonb_build_object('envoye', true, 'total', v_total, 'lignes', v_lignes);
end;
$$;

revoke all on function public.rapport_matinal(boolean) from public, anon;
grant execute on function public.rapport_matinal(boolean) to authenticated;

create or replace function public.relancer_dossiers_en_attente(p_heures int default 48)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_h      int := greatest(coalesce(p_heures, 48), 1);
  v_c      jsonb := public.compteurs_attente(now() - make_interval(hours => v_h));
  v_lignes jsonb := v_c->'lignes';
  v_total  int   := (v_c->>'total')::int;
begin
  if v_total = 0 then
    return jsonb_build_object('envoye', false, 'total', 0, 'heures', v_h);
  end if;

  begin
    perform public.notify_admin('dossiers_oublies', jsonb_build_object(
      'heures', v_h, 'lignes', v_lignes));
  exception when others then
    raise warning 'relancer_dossiers_en_attente : envoi échoué : %', sqlerrm;
    return jsonb_build_object('envoye', false, 'erreur', sqlerrm, 'lignes', v_lignes);
  end;

  return jsonb_build_object('envoye', true, 'total', v_total, 'heures', v_h, 'lignes', v_lignes);
end;
$$;

revoke all on function public.relancer_dossiers_en_attente(int) from public, anon;
grant execute on function public.relancer_dossiers_en_attente(int) to authenticated;

-- ============================================================
-- 2. « /point » - le sommaire
-- ============================================================
create or replace function public.point_telegram()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c     jsonb := public.compteurs_attente(null);
  v_total int   := (v_c->>'total')::int;
  v_texte text;
begin
  select string_agg('• ' || (l->>'nombre') || ' ' || (l->>'libelle'), chr(10))
    into v_texte
    from jsonb_array_elements(v_c->'lignes') l
   where (l->>'nombre')::int > 0;

  return jsonb_build_object(
    'total', v_total,
    'texte', case when v_total = 0 and v_texte is null
                  then 'Rien n''attend votre validation. Bonne journée.'
                  else coalesce(v_texte, '') end);
end;
$$;

revoke all on function public.point_telegram() from public, anon, authenticated;
grant execute on function public.point_telegram() to service_role;

-- ============================================================
-- 3. « /attente » - QUI attend, nommément
-- ============================================================
-- Le point du jour dit « 3 inscriptions » ; celui-ci dit lesquelles.
-- Les inscriptions portent un bouton chacune - c'est le geste qui suit ;
-- les paiements sont listés sans bouton de confirmation : dans une liste
-- longue, « Confirmer » se touche par mégarde, et un paiement confirmé
-- par erreur ne se voit pas.
create or replace function public.dossiers_en_attente_liste(p_max int default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_max  int := greatest(coalesce(p_max, 10), 1);
  v_ins  jsonb;
  v_nins int := 0;
  v_pai  text;
  v_npai int := 0;
begin
  begin
    select count(*) into v_nins from public.profiles where status = 'pending';
    select jsonb_agg(jsonb_build_object('id', id, 'libelle', libelle) order by rang)
      into v_ins
      from (
        select p.id,
               coalesce(p.full_name, p.email, '(sans nom)')
               || ' - ' || to_char(p.created_at, 'DD/MM') as libelle,
               row_number() over (order by p.created_at) as rang
          from public.profiles p where p.status = 'pending'
      ) t where rang <= v_max;
  exception when others then null; end;

  begin
    select coalesce(string_agg(ligne, chr(10) order by le), ''), count(*)
      into v_pai, v_npai
      from (
        select v.created_at as le,
               '• ' || coalesce(p.full_name, p.email, '(sans nom)')
               || ' - validité ' || v.years_requested || ' an(s), '
               || v.amount_fcfa || ' F, réf. ' || v.payment_reference
               || ' (' || to_char(v.created_at, 'DD/MM') || ')' as ligne
          from public.card_validity_payments v
          join public.profiles p on p.id = v.user_id
         where v.status = 'pending'
        union all
        select c.created_at,
               '• ' || coalesce(p.full_name, p.email, '(sans nom)')
               || ' - cotisations ' || c.months_requested || ' mois ' || c.year || ', '
               || c.amount_fcfa || ' F, réf. ' || c.payment_reference
               || ' (' || to_char(c.created_at, 'DD/MM') || ')'
          from public.cotisation_payments c
          join public.profiles p on p.id = c.user_id
         where c.status = 'pending'
      ) x;
  exception when others then null; end;

  return jsonb_build_object(
    'nb_inscriptions', coalesce(v_nins, 0),
    'inscriptions', coalesce(v_ins, '[]'::jsonb),
    'nb_paiements', coalesce(v_npai, 0),
    'paiements', coalesce(v_pai, ''));
end;
$$;

revoke all on function public.dossiers_en_attente_liste(int) from public, anon, authenticated;
grant execute on function public.dossiers_en_attente_liste(int) to service_role;

-- ============================================================
-- 4. « /justificatifs » - les captures non classées
-- ============================================================
-- Renvoie de quoi les RÉAFFICHER : le file_id permet de reposer l'image
-- dans le salon sans la retélécharger, et les déclarations en attente du
-- membre remettent les boutons de confirmation là où ils servent.
create or replace function public.justificatifs_en_attente(p_max int default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_max   int := greatest(coalesce(p_max, 5), 1);
  v_total int := 0;
  v_liste jsonb;
begin
  select count(*) into v_total from public.justificatifs_paiement where statut = 'recu';

  -- Les déclarations en attente sont rassemblées PAR MEMBRE d'abord,
  -- puis rattachées. Les chercher depuis chaque justificatif aurait
  -- demandé une sous-requête corrélée à deux niveaux, que PostgreSQL
  -- refuse hors « lateral ».
  with declarations as (
    select v.user_id, 'val' as code, v.id as did,
           'Validité ' || v.years_requested || ' an(s) - '
           || v.amount_fcfa || ' F - réf. ' || v.payment_reference as libelle
      from public.card_validity_payments v where v.status = 'pending'
    union all
    select c.user_id, 'cot', c.id,
           'Cotisations ' || c.months_requested || ' mois ' || c.year || ' - '
           || c.amount_fcfa || ' F - réf. ' || c.payment_reference
      from public.cotisation_payments c where c.status = 'pending'
  ),
  par_membre as (
    select user_id,
           jsonb_agg(jsonb_build_object('code', code, 'id', did, 'libelle', libelle)) as attente
      from declarations group by user_id
  ),
  classes as (
    select j.id, j.file_id, j.user_id, j.legende, j.recu_le,
           coalesce(p.full_name, p.email, '(sans nom)') as nom,
           coalesce(m.attente, '[]'::jsonb) as attente,
           row_number() over (order by j.recu_le) as rang
      from public.justificatifs_paiement j
      join public.profiles p on p.id = j.user_id
      left join par_membre m on m.user_id = j.user_id
     where j.statut = 'recu'
  )
  select jsonb_agg(jsonb_build_object(
           'id', id, 'file_id', file_id, 'user_id', user_id,
           'nom', nom, 'legende', legende,
           'recu', to_char(recu_le, 'DD/MM à HH24:MI'),
           'attente', attente) order by rang)
    into v_liste
    from classes where rang <= v_max;

  return jsonb_build_object('total', v_total, 'liste', coalesce(v_liste, '[]'::jsonb));
end;
$$;

revoke all on function public.justificatifs_en_attente(int) from public, anon, authenticated;
grant execute on function public.justificatifs_en_attente(int) to service_role;

-- ============================================================
-- 5. « /cotisations » - l'état de l'année
-- ============================================================
create or replace function public.etat_cotisations_telegram(p_annee int default null)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_a       int := coalesce(p_annee, extract(year from now())::int);
  v_membres int;
  v_ajour   int;
  v_partiel int;
  v_aucun   int;
  v_mois    int;
  v_encaisse bigint;
  v_retard  text;
begin
  select count(*) into v_membres from public.profiles
   where status = 'approved' and coalesce(is_active, true) is true;

  select count(*) filter (where nb >= 12),
         count(*) filter (where nb between 1 and 11),
         count(*) filter (where nb = 0),
         coalesce(sum(nb), 0)
    into v_ajour, v_partiel, v_aucun, v_mois
    from (
      select coalesce(array_length(c.months_paid, 1), 0) as nb
        from public.profiles p
        left join public.cotisations c on c.user_id = p.id and c.year = v_a
       where p.status = 'approved' and coalesce(p.is_active, true) is true
    ) x;

  v_encaisse := v_mois::bigint * 1000;

  -- Les cinq plus en retard, pour savoir par où commencer.
  select string_agg('• ' || nom || ' (' || nb || '/12)', chr(10) order by nb, nom)
    into v_retard
    from (
      select coalesce(p.full_name, p.email, '(sans nom)') as nom,
             coalesce(array_length(c.months_paid, 1), 0) as nb
        from public.profiles p
        left join public.cotisations c on c.user_id = p.id and c.year = v_a
       where p.status = 'approved' and coalesce(p.is_active, true) is true
         and coalesce(array_length(c.months_paid, 1), 0) < 12
       order by coalesce(array_length(c.months_paid, 1), 0), coalesce(p.full_name, p.email)
       limit 5
    ) y;

  return 'COTISATIONS ' || v_a || chr(10) || chr(10)
      || 'Membres actifs : ' || v_membres || chr(10)
      || 'À jour (12/12) : ' || v_ajour || chr(10)
      || 'Partiels : ' || v_partiel || chr(10)
      || 'Aucun mois : ' || v_aucun || chr(10) || chr(10)
      || 'Mois réglés au total : ' || v_mois || ' sur ' || (v_membres * 12) || chr(10)
      || 'Encaissé : ' || v_encaisse || ' F (1 000 F par mois)' || chr(10)
      || case when v_retard is null then ''
              else chr(10) || 'Les plus en retard :' || chr(10) || v_retard end;
end;
$$;

revoke all on function public.etat_cotisations_telegram(int) from public, anon, authenticated;
grant execute on function public.etat_cotisations_telegram(int) to service_role;

-- ============================================================
-- 6. « /cartes » - les cartes non attribuées, dans les deux sens
-- ============================================================
create or replace function public.cartes_non_attribuees(p_max int default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_max      int := greatest(coalesce(p_max, 10), 1);
  v_nreg     int := 0;
  v_registre text := '';
  v_nsans    int := 0;
  v_sans     jsonb;
begin
  -- 1. Le REGISTRE : des cartes qui existent, sans propriétaire déclaré.
  --    Aucun bouton possible - il n'y a pas de compte à ouvrir. C'est
  --    l'écran des cartes qui sert à les rapprocher d'une personne.
  begin
    select count(*) into v_nreg from public.member_cards where claim_status = 'unclaimed';
    select coalesce(string_agg(ligne, chr(10) order by rang), '')
      into v_registre
      from (
        select '• ' || coalesce(card_number, '(sans numéro)') || ' - ' || full_name
               || coalesce(' (' || nullif(btrim(city), '') || ')', '')
               || coalesce(' - ' || phone, '') as ligne,
               row_number() over (order by card_number, full_name) as rang
          from public.member_cards where claim_status = 'unclaimed'
      ) t where rang <= v_max;
  exception when others then null; end;

  -- 2. L'INVERSE : des comptes approuvés sans numéro de carte. Chacun
  --    porte un bouton, sa fiche menant à tout le reste.
  begin
    select count(*) into v_nsans from public.profiles
     where status = 'approved' and coalesce(is_active, true) is true
       and nullif(btrim(coalesce(legacy_card_number, '')), '') is null;
    select jsonb_agg(jsonb_build_object('id', id, 'libelle', libelle) order by rang)
      into v_sans
      from (
        select p.id,
               coalesce(p.full_name, p.email, '(sans nom)')
               || coalesce(' - ' || p.member_since::text, '') as libelle,
               row_number() over (order by p.member_since nulls last,
                                           coalesce(p.full_name, p.email)) as rang
          from public.profiles p
         where p.status = 'approved' and coalesce(p.is_active, true) is true
           and nullif(btrim(coalesce(p.legacy_card_number, '')), '') is null
      ) t where rang <= v_max;
  exception when others then null; end;

  return jsonb_build_object(
    'nb_registre', v_nreg, 'registre', v_registre,
    'nb_sans_numero', v_nsans, 'sans_numero', coalesce(v_sans, '[]'::jsonb),
    'max', v_max);
end;
$$;

revoke all on function public.cartes_non_attribuees(int) from public, anon, authenticated;
grant execute on function public.cartes_non_attribuees(int) to service_role;

notify pgrst, 'reload schema';

-- ============================================================
-- 7. CONTRÔLES
-- ============================================================
select proname from pg_proc
 where proname in ('compteurs_attente', 'point_telegram', 'dossiers_en_attente_liste',
                   'justificatifs_en_attente', 'etat_cotisations_telegram',
                   'cartes_non_attribuees', 'rapport_matinal', 'relancer_dossiers_en_attente')
 order by proname;

-- Ce que chaque commande répondrait, maintenant, sans rien envoyer.
select jsonb_pretty(public.point_telegram())            as point;
select jsonb_pretty(public.dossiers_en_attente_liste()) as attente;
select jsonb_pretty(public.justificatifs_en_attente())  as justificatifs;
select public.etat_cotisations_telegram()               as cotisations;
select jsonb_pretty(public.cartes_non_attribuees())     as cartes;
