-- ============================================================
-- PHASE 78 - Éviter les doubles inscriptions
--
-- LE CONSTAT (14/08/2026). Mame Dié MBATHIE avait déjà un compte
-- (diallodie90@gmail.com, carte AMSTC-2023-177) et une SECONDE
-- inscription est arrivée en attente sous diallosie90@gamil.com - une
-- adresse différente d'une lettre et d'une coquille. Une adresse
-- identique est déjà refusée par Supabase Auth ; ce cas-là ne l'était
-- pas.
--
-- DEUX GARDES-FOUS.
--
-- 1. verifier_doublon_inscription(email, telephone, nom) : appelée par
--    le formulaire AVANT la création du compte. Elle répond
--      { email_pris, telephone_pris, nom_pris }
--    sans jamais renvoyer l'identité du membre existant : un formulaire
--    ouvert à tous ne doit pas servir à savoir qui est inscrit. L'e-mail
--    est comparé sans casse ; le téléphone sur ses chiffres, en
--    ignorant l'indicatif +221 ; le nom sans accents ni casse.
--    « email_pris » est un REFUS ; téléphone et nom sont des ALERTES :
--    des homonymes existent, et deux membres d'un même foyer peuvent
--    partager un téléphone.
--
-- 2. Sur l'écran d'administration, une inscription en attente qui
--    ressemble à un compte existant est signalée : même téléphone ou
--    même nom (fonction doublons_probables_en_attente, admin seule).
--
-- POURQUOI PAS UNE CONTRAINTE D'UNICITÉ. Supabase Auth garantit déjà
-- l'unicité de l'e-mail dans auth.users, et profiles.email en est la
-- copie. Rendre le téléphone unique casserait des cas légitimes.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- Normalisation d'un téléphone : chiffres seuls, sans l'indicatif 221.
create or replace function public.telephone_cle(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    else regexp_replace(regexp_replace(p, '\D', '', 'g'), '^221', '')
  end;
$$;

-- Normalisation d'un nom : sans accents, sans casse, espaces réduits.
-- Autonome (pas de dépendance à la phase 70) : « Mame Dié » et « Mame
-- Die » doivent se rejoindre, ce que minuscules_fr ne fait pas.
create or replace function public.nom_cle(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    else lower(regexp_replace(btrim(translate(p,
      'ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÑñÒÓÔÕÖòóôõöÙÚÛÜùúûüÝŸýÿ',
      'AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiNnOOOOOoooooUUUUuuuuYYyy')), '\s+', ' ', 'g'))
  end;
$$;

create or replace function public.verifier_doublon_inscription(
  p_email text,
  p_telephone text default null,
  p_nom text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email_pris boolean := false;
  v_tel_pris   boolean := false;
  v_nom_pris   boolean := false;
  v_tel        text := nullif(public.telephone_cle(p_telephone), '');
  v_nom        text := nullif(public.nom_cle(p_nom), '');
begin
  -- Un e-mail existe s'il figure dans les comptes d'authentification
  -- (source de vérité) ou dans les fiches. La comparaison est faite en
  -- minuscules : les adresses ne distinguent pas la casse.
  if p_email is not null and btrim(p_email) <> '' then
    v_email_pris := exists (
      select 1 from auth.users u where lower(u.email) = lower(btrim(p_email))
    ) or exists (
      select 1 from public.profiles pr where lower(pr.email) = lower(btrim(p_email))
    );
  end if;

  -- Téléphone : au moins 9 chiffres pour éviter les faux positifs sur
  -- des saisies tronquées.
  if v_tel is not null and length(v_tel) >= 9 then
    v_tel_pris := exists (
      select 1 from public.profiles pr
       where public.telephone_cle(pr.phone) = v_tel
    ) or exists (
      select 1 from public.member_cards mc
       where public.telephone_cle(mc.phone) = v_tel
         and mc.claim_status = 'confirmed'
    );
  end if;

  if v_nom is not null and length(v_nom) >= 5 then
    v_nom_pris := exists (
      select 1 from public.profiles pr
       where public.nom_cle(pr.full_name) = v_nom
    );
  end if;

  return jsonb_build_object(
    'email_pris', v_email_pris,
    'telephone_pris', v_tel_pris,
    'nom_pris', v_nom_pris
  );
end;
$$;

-- Ouverte aux visiteurs : c'est avant la création du compte qu'elle
-- sert. Elle ne renvoie que trois booléens.
revoke all on function public.verifier_doublon_inscription(text, text, text) from public;
grant execute on function public.verifier_doublon_inscription(text, text, text) to anon, authenticated;

-- ===== Côté administration : doublons probables parmi les inscriptions
-- en attente =====
create or replace function public.doublons_probables_en_attente()
returns table (
  attente_id    uuid,
  attente_email text,
  existant_id   uuid,
  existant_nom  text,
  existant_email text,
  motif         text
)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.email, e.id, e.full_name, e.email,
         case
           when public.telephone_cle(a.phone) is not null
                and public.telephone_cle(a.phone) = public.telephone_cle(e.phone)
             then 'même téléphone'
           else 'même nom'
         end
    from public.profiles a
    join public.profiles e
      on e.id <> a.id
     and e.status <> 'pending'
     and (
       (public.telephone_cle(a.phone) is not null
        and length(public.telephone_cle(a.phone)) >= 9
        and public.telephone_cle(a.phone) = public.telephone_cle(e.phone))
       or
       (public.nom_cle(a.full_name) is not null
        and length(public.nom_cle(a.full_name)) >= 5
        and public.nom_cle(a.full_name) = public.nom_cle(e.full_name))
     )
   where a.status = 'pending'
     and public.is_admin();
$$;

revoke all on function public.doublons_probables_en_attente() from public, anon;
grant execute on function public.doublons_probables_en_attente() to authenticated;

notify pgrst, 'reload schema';

-- Contrôles.
select public.verifier_doublon_inscription('adresse-inexistante@exemple.test', '000000000', 'Personne Inconnue');
select * from public.doublons_probables_en_attente();
