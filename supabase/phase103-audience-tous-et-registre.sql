-- ============================================================
-- PHASE 103 - Diffusion WhatsApp : « Membres inscrits et registre »
--
-- LE BESOIN. Pour une annonce qui doit toucher tout le monde - une
-- collecte de fonds, une convocation - « Tous les membres » (phase 30)
-- ne suffit pas : elle ne vise que les profils avec compte, laissant de
-- côté les personnes du registre qui n'ont jamais réclamé leur carte
-- (phase 93). Cette phase ajoute une sixième audience qui réunit les
-- deux.
--
-- POURQUOI UNE UNION SQL, ET NON UNE REQUÊTE RÉÉCRITE. Les deux
-- ensembles sont DÉJÀ DISJOINTS par construction : 'carte_jamais_
-- reclamee' exclut explicitement (phase 93) quiconque a un profil dont
-- le téléphone normalisé correspond. Réunir les deux appels existants
-- avec UNION garantit que cette nouvelle audience évolue automatiquement
-- si l'une des deux définitions change un jour - il n'y a qu'un seul
-- endroit où « tous » et « carte_jamais_reclamee » sont définis, et ça
-- reste vrai après cette phase.
--
-- QUEL MODÈLE META. Comme 'tous', cette audience part par le modèle
-- Marketing (nouvelle_annonce) - voir la mise à jour de
-- notify-members-whatsapp ci-dessous. Ce n'est pas un rappel de compte,
-- c'est une annonce large.
--
-- IL FAUT REDÉPLOYER notify-members-whatsapp : comme pour la phase 93,
-- la fonction Edge tient sa propre liste d'audiences autorisées.
--
-- PRÉREQUIS : phases 31, 78, 93.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create or replace function public._whatsapp_targets(p_audience text)
returns table(id uuid, phone text, full_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year  int := extract(year from now())::int;
  v_month int := extract(month from now())::int;
begin
  if p_audience = 'tous' then
    return query
      select p.id, p.phone, p.full_name
      from public.profiles p
      where p.status = 'approved' and p.is_active and p.phone is not null;

  elsif p_audience = 'carte_expiree' then
    return query
      select p.id, p.phone, p.full_name
      from public.profiles p
      where p.status = 'approved' and p.is_active and p.phone is not null
        and (p.card_valid_until is null or p.card_valid_until < v_year);

  elsif p_audience = 'carte_expire_bientot' then
    return query
      select p.id, p.phone, p.full_name
      from public.profiles p
      where p.status = 'approved' and p.is_active and p.phone is not null
        and p.card_valid_until = v_year;

  elsif p_audience = 'cotisation_impayee' then
    return query
      select p.id, p.phone, p.full_name
      from public.profiles p
      where p.status = 'approved' and p.is_active and p.phone is not null
        and p.card_valid_until is not null and p.card_valid_until >= v_year
        and not exists (
          select 1 from public.cotisations c
          where c.user_id = p.id and c.year = v_year and v_month = any(c.months_paid)
        );

  elsif p_audience = 'carte_jamais_reclamee' then
    return query
      with cartes as (
        select mc.id as carte_id, mc.full_name as nom,
               public.telephone_cle(mc.phone) as cle
          from public.member_cards mc
         where mc.claim_status = 'unclaimed'
      ),
      uniques as (
        select min(c.carte_id::text)::uuid as carte_id,
               min(c.nom) as nom,
               c.cle as cle
          from cartes c
         where c.cle is not null and length(c.cle) = 9
         group by c.cle
      )
      select u.carte_id, '221' || u.cle, u.nom
        from uniques u
       where not exists (
         select 1 from public.profiles p
          where public.telephone_cle(p.phone) = u.cle
       );

  -- NOUVEAU (phase 103). Simple reunion des deux audiences ci-dessus :
  -- aucune logique de ciblage propre, donc aucun risque de divergence
  -- avec elles au fil du temps.
  elsif p_audience = 'tous_et_registre' then
    return query
      select * from public._whatsapp_targets('tous')
      union
      select * from public._whatsapp_targets('carte_jamais_reclamee');

  else
    raise exception 'Audience inconnue : %', p_audience;
  end if;
end;
$$;

revoke all on function public._whatsapp_targets(text) from public, anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - aucun envoi
-- ============================================================
-- a) La nouvelle audience doit compter EXACTEMENT la somme des deux
--    autres : aucun chevauchement, aucune perte.
select
  (select count(*) from public.whatsapp_target_members('tous'))
    as tous,
  (select count(*) from public.whatsapp_target_members('carte_jamais_reclamee'))
    as registre_non_reclame,
  (select count(*) from public.whatsapp_target_members('tous_et_registre'))
    as tous_et_registre,
  (select count(*) from public.whatsapp_target_members('tous'))
    + (select count(*) from public.whatsapp_target_members('carte_jamais_reclamee'))
    as somme_attendue;

-- b) Un echantillon des deux origines, pour verifier de visu que les
--    deux populations sont bien presentes.
select full_name, phone from public.whatsapp_target_members('tous_et_registre')
 order by random() limit 10;
