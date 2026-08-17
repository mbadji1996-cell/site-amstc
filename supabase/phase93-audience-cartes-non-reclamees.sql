-- ============================================================
-- PHASE 93 - Diffusion WhatsApp : « Carte jamais réclamée »
--
-- LE BESOIN. Cent soixante-dix-huit cartes du registre importé n'ont
-- jamais été réclamées : des membres qui existent sur le papier, dont on
-- a le nom et le téléphone, mais qui n'ont jamais créé de compte sur le
-- site. Ils ne reçoivent donc AUCUNE des diffusions existantes, qui
-- partent toutes de la table des profils.
--
-- CE QUE CETTE PHASE AJOUTE : une cinquième audience à l'écran de
-- diffusion, qui vise cette table-là. Le message est libre - vous
-- écrirez l'invitation à activer son compte - et part par le modèle
-- Meta déjà approuvé, celui des rappels. Rien de nouveau à faire
-- valider chez Meta.
--
-- DEUX PRÉCAUTIONS, sans lesquelles la diffusion ferait plus de mal que
-- de bien :
--
--   1. ON EXCLUT CEUX QUI ONT DÉJÀ UN COMPTE. Un membre peut s'être
--      inscrit sur le site sans jamais réclamer sa carte du registre :
--      son numéro figure alors des deux côtés. Lui demander d'activer un
--      compte qu'il a déjà le ferait douter du sérieux de l'envoi. Le
--      rapprochement se fait sur le téléphone normalisé
--      (telephone_cle, phase 78), pas sur le nom - deux orthographes
--      d'un même nom sont trop fréquentes pour s'y fier.
--
--   2. ON N'ENVOIE QU'À UN NUMÉRO SÉNÉGALAIS PLAUSIBLE - neuf chiffres
--      après retrait de l'indicatif. Le registre vient d'un tableur, et
--      un numéro tronqué partirait à un inconnu.
--
-- LE NUMÉRO EST RENDU AU FORMAT INTERNATIONAL (221XXXXXXXXX). Les autres
-- audiences renvoient le téléphone brut du profil ; ici la table vient
-- d'un import, ses numéros sont écrits de dix façons, et Meta refuse
-- tout ce qui n'est pas en format international. On normalise donc à la
-- source plutôt que d'espérer.
--
-- IL FAUT AUSSI redéployer notify-members-whatsapp : la fonction Edge
-- tient sa propre liste d'audiences autorisées, et refuserait celle-ci.
--
-- PRÉREQUIS : phases 30, 31, 78.
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

  -- NOUVEAU (phase 93) : le registre, pas les profils.
  elsif p_audience = 'carte_jamais_reclamee' then
    return query
      with cartes as (
        select mc.id, mc.full_name, public.telephone_cle(mc.phone) as cle
          from public.member_cards mc
         where mc.claim_status = 'unclaimed'
      ),
      -- Un même numéro peut porter plusieurs cartes du registre (une par
      -- année d'adhésion, selon les imports) : sans ce regroupement, la
      -- personne recevrait le message deux ou trois fois.
      uniques as (
        select min(id::text)::uuid as id, min(full_name) as full_name, cle
          from cartes
         where cle is not null and length(cle) = 9
         group by cle
      )
      select u.id, '221' || u.cle, u.full_name
        from uniques u
       where not exists (
         select 1 from public.profiles p
          where public.telephone_cle(p.phone) = u.cle
       );

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
-- a) Combien recevraient le message, et ce que l'exclusion a écarté.
select
  (select count(*) from public.member_cards where claim_status = 'unclaimed')
    as cartes_non_reclamees,
  (select count(*) from public.whatsapp_target_members('carte_jamais_reclamee'))
    as destinataires_reels;

-- b) Les cinq premiers, pour vérifier de visu que les numéros ont bien
--    la forme 221XXXXXXXXX.
select full_name, phone from public.whatsapp_target_members('carte_jamais_reclamee')
 order by full_name limit 5;

-- c) Qui a été écarté parce qu'il a DÉJÀ un compte. Ce sont des
--    personnes à qui il ne reste qu'à réclamer leur carte sur le site -
--    l'écran des cartes s'en charge, pas une diffusion.
select mc.full_name as au_registre, p.full_name as compte_existant, p.email
  from public.member_cards mc
  join public.profiles p on public.telephone_cle(p.phone) = public.telephone_cle(mc.phone)
 where mc.claim_status = 'unclaimed'
   and public.telephone_cle(mc.phone) is not null
 order by mc.full_name;

-- d) Et ceux dont le numéro est inexploitable : à corriger à la main
--    dans l'écran des cartes, ou à joindre autrement.
select full_name, phone, city from public.member_cards
 where claim_status = 'unclaimed'
   and coalesce(length(public.telephone_cle(phone)), 0) <> 9
 order by full_name;
