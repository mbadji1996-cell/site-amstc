-- ============================================================
-- PHASE 71 - Prénoms et nom correctement séparés.
--
-- LE DÉFAUT. Les cartes portent le nom en un seul morceau. Quand le
-- membre créait son compte par invitation, la page découpait ce nom
-- ainsi : PREMIER MOT = prénom, TOUT LE RESTE = nom de famille.
--
--   « Abdoulaye Amadou NDIAYE »  ->  prénom « Abdoulaye »
--                                    nom    « Amadou Ndiaye »
--   « Dr Mouhamadou Taïb BABOU » ->  prénom « Dr Mouhamadou Taïb Babou »
--
-- Ce n'était pas un défaut d'affichage : c'est cette identité fausse qui
-- part sur la CARTE IMPRIMÉE, où le nom de famille tient sa propre ligne.
--
-- LA RÈGLE RETENUE. Le nom de famille s'écrit en capitales : ce sont donc
-- les derniers mots tout en capitales. Quand la carte n'en porte aucune
-- - « Cheikh Tidiane Diop » -, le dernier mot fait office de nom, ce qui
-- est la convention usuelle. Un « Dr » ou « Pr » de tête devient le titre
-- au lieu d'être pris pour un prénom.
--
-- La carte fait foi : c'est elle qui a été établie par l'association,
-- alors que le découpage du profil a été fabriqué par la page.
--
-- À exécuter après phase70. Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. La règle de découpage =====
create or replace function public.decouper_nom(t text)
returns table (titre text, prenom text, nom text)
language plpgsql immutable as $$
declare
  v_mots text[];
  v_titre text := null;
  v_n int;
  i int;
begin
  v_mots := regexp_split_to_array(
              btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g')), ' ');

  if v_mots is null or array_length(v_mots, 1) is null or v_mots[1] = '' then
    return query select null::text, null::text, null::text;
    return;
  end if;

  if public.majuscules_fr(replace(v_mots[1], '.', '')) in ('DR', 'PR') then
    v_titre := public.casse_titre(replace(v_mots[1], '.', ''));
    v_mots  := v_mots[2:];
  end if;

  v_n := coalesce(array_length(v_mots, 1), 0);
  if v_n = 0 then
    return query select v_titre, null::text, null::text;
    return;
  end if;
  if v_n = 1 then
    return query select v_titre, null::text, public.casse_nom(v_mots[1]);
    return;
  end if;

  -- Remonte tant que le mot précédent est tout en capitales, sans jamais
  -- consommer le premier : il reste au moins un prénom.
  i := v_n + 1;
  while i - 1 >= 2
        and v_mots[i - 1] ~ '[[:alpha:]]'
        and v_mots[i - 1] = public.majuscules_fr(v_mots[i - 1]) loop
    i := i - 1;
  end loop;

  -- Aucune capitale trouvée : le dernier mot fait office de nom.
  if i = v_n + 1 then i := v_n; end if;

  return query select v_titre,
                      public.casse_titre(array_to_string(v_mots[1:i - 1], ' ')),
                      public.casse_nom(array_to_string(v_mots[i:], ' '));
end;
$$;

-- ===== 2. Ce que la correction va changer, AVANT de l'appliquer =====
-- À lire ligne par ligne : c'est la liste exacte de ce que l'étape 3
-- écrira. Une identité mal découpée y saute aux yeux.
select c.card_number,
       c.full_name                      as nom_sur_la_carte,
       p.full_name                      as fiche_avant,
       coalesce(d.titre, p.title, '-')  as titre_apres,
       d.prenom                         as prenom_apres,
       d.nom                            as nom_apres,
       p.email
  from public.member_cards c
  join public.profiles p on p.id = c.claimed_by
  cross join lateral public.decouper_nom(c.full_name) d
 where c.claim_status = 'confirmed'
   and d.prenom is not null
   and d.nom is not null
   and (p.first_name is distinct from d.prenom
     or p.last_name  is distinct from d.nom)
 order by c.card_number;

-- ===== 3. Correction des fiches =====
update public.profiles p
   set title      = coalesce(d.titre, p.title),
       first_name = d.prenom,
       last_name  = d.nom,
       full_name  = d.prenom || ' ' || d.nom
  from public.member_cards c,
       lateral public.decouper_nom(c.full_name) d
 where c.claimed_by = p.id
   and c.claim_status = 'confirmed'
   and d.prenom is not null
   and d.nom is not null
   and (p.first_name is distinct from d.prenom
     or p.last_name  is distinct from d.nom);

-- ===== 4. Les cartes reprennent le nom de leur fiche =====
-- Le titre disparaît de full_name mais reste dans sa propre colonne : les
-- deux écrans cessent de se contredire, et l'affichage le recompose.
--
-- Le titre est repris de la FICHE, que l'étape 3 vient de renseigner, et
-- non recalculé par decouper_nom : un LATERAL placé dans le FROM d'un
-- UPDATE ne peut pas référencer la table mise à jour.
update public.member_cards c
   set title     = coalesce(c.title, p.title),
       full_name = p.full_name
  from public.profiles p
 where p.id = c.claimed_by
   and c.claim_status = 'confirmed'
   and btrim(coalesce(p.full_name, '')) <> ''
   and (c.full_name is distinct from p.full_name
     or (c.title is null and p.title is not null));

-- ===== 5. L'invitation transmet le titre =====
-- Le type de retour change : DROP obligatoire. Sans le titre, une
-- invitation pour « Dr Becaye SALL » afficherait « Becaye SALL » une fois
-- le titre sorti de full_name à l'étape 4.
drop function if exists public.lire_invitation(text);

create or replace function public.lire_invitation(p_jeton text)
returns table (full_name text, card_number text, member_since int, city text, title text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.invitations_carte%rowtype;
begin
  select * into v_inv from public.invitations_carte where jeton = p_jeton;

  if v_inv.id is null then
    raise exception 'Ce lien d''invitation est inconnu.';
  end if;
  if v_inv.used_at is not null then
    raise exception 'Ce lien a déjà été utilisé pour créer un compte.';
  end if;
  if now() > v_inv.expire_le then
    raise exception 'Ce lien a expiré. Demandez-en un nouveau à l''administration.';
  end if;

  return query
    select c.full_name, c.card_number, c.member_since, c.city, c.title
      from public.member_cards c
     where c.id = v_inv.card_id;
end;
$$;

revoke all on function public.lire_invitation(text) from public;
grant execute on function public.lire_invitation(text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ===== 6. Contrôle : plus aucune fiche ne contredit sa carte =====
select count(*) as fiches_encore_mal_decoupees
  from public.member_cards c
  join public.profiles p on p.id = c.claimed_by
  cross join lateral public.decouper_nom(c.full_name) d
 where c.claim_status = 'confirmed'
   and d.prenom is not null and d.nom is not null
   and (p.first_name is distinct from d.prenom
     or p.last_name  is distinct from d.nom);
