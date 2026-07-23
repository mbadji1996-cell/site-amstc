-- ============================================================
-- PHASE 31 — Rappels WhatsApp ciblés (carte expirée / à renouveler /
-- cotisation du mois impayée), en plus de la diffusion "tous les membres"
-- de la Phase 30.
--
-- Ajoute une colonne "audience" au journal des diffusions, et 3 fonctions :
--   - public._whatsapp_targets(p_audience)   : logique de ciblage partagée
--     (non exposée directement, appelée par les deux fonctions ci-dessous)
--   - public.whatsapp_target_count(p_audience)   : aperçu du nombre de
--     destinataires, appelable par un admin connecté normalement (utilisé
--     par membres/whatsapp-admin.html pour afficher le compteur en direct)
--   - public.whatsapp_target_members(p_audience) : liste complète avec
--     téléphone, réservée à la clé service_role (jamais exposée à
--     authenticated/anon) — utilisée uniquement par la fonction Edge
--     notify-members-whatsapp au moment de l'envoi réel
--
-- Audiences reconnues :
--   'tous'                 - tous les membres approuvés avec téléphone
--   'carte_expiree'        - card_valid_until non défini ou année passée
--   'carte_expire_bientot' - card_valid_until = année en cours (expire au
--                            31 décembre, encore valide mais à renouveler)
--   'cotisation_impayee'   - carte valide, mois en cours absent de
--                            cotisations.months_paid pour l'année en cours
--                            (cohérent avec la contrainte de phase7b :
--                            impossible de payer une cotisation sans carte
--                            valide, donc pas de rappel cotisation envoyé
--                            à un membre à carte expirée - il reçoit déjà
--                            le rappel 'carte_expiree' à la place)
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase30-whatsapp-broadcasts.sql, phase7-
-- validite-cotisations.sql).
-- ============================================================

alter table public.whatsapp_broadcasts
  add column if not exists audience text not null default 'tous';

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

  else
    raise exception 'Audience inconnue : %', p_audience;
  end if;
end;
$$;

revoke all on function public._whatsapp_targets(text) from public, anon, authenticated;

create or replace function public.whatsapp_target_count(p_audience text)
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs.';
  end if;
  return (select count(*) from public._whatsapp_targets(p_audience));
end;
$$;

grant execute on function public.whatsapp_target_count(text) to authenticated;

-- SQL (pas plpgsql) : simple relais, pas de vérification is_admin() ici
-- puisque cette fonction n'est jamais accessible qu'à service_role (voir
-- revoke ci-dessous) - la fonction Edge fait déjà sa propre vérification
-- d'admin sur le JWT de l'appelant avant d'en arriver là.
create or replace function public.whatsapp_target_members(p_audience text)
returns table(id uuid, phone text, full_name text)
language sql
security definer
set search_path = public
as $$
  select * from public._whatsapp_targets(p_audience);
$$;

revoke all on function public.whatsapp_target_members(text) from public, anon, authenticated;

-- Octroi explicite à service_role : REVOKE ALL FROM PUBLIC ne garantit pas
-- que service_role garde l'exécution par défaut selon la configuration du
-- projet - on le rend explicite pour ne dépendre d'aucune supposition.
grant execute on function public.whatsapp_target_members(text) to service_role;
