-- ============================================================
-- PHASE 70 - Casse des noms et des localités, imposée en base.
--
-- LA RÈGLE. Prénom en casse titre, nom de famille en CAPITALES, localité
-- en casse titre : « mouhamed badji » de « médina » devient
-- « Mouhamed BADJI » de « Médina ». C'est la convention de l'état civil,
-- et elle distingue le nom du prénom sur la carte imprimée.
--
-- POURQUOI EN BASE ET PAS SEULEMENT DANS LES FORMULAIRES. Le profil
-- s'écrit par cinq chemins : l'inscription, l'écran de complétion, la
-- fiche du membre, la correction par l'administration, et la reprise des
-- données d'une carte à l'invitation. Corriger chaque formulaire
-- laisserait passer le sixième chemin qu'on ajoutera demain. Un
-- déclencheur AVANT écriture ferme la question une fois pour toutes.
--
-- LA LOCALE N'EST PAS SUPPOSÉE. upper() dépend de la locale de la base :
-- selon son réglage, upper('é') peut renvoyer « é » inchangé, et
-- « séne » deviendrait « SéNE ». Les accents sont donc convertis
-- explicitement par translate() avant d'appeler upper(), ce qui donne le
-- même résultat partout.
--
-- À exécuter après phase69. Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Majuscules et minuscules fiables =====
-- Les deux chaînes de translate() doivent avoir le MÊME nombre de
-- caractères : chacune est la traduction position par position de l'autre.
create or replace function public.majuscules_fr(t text)
returns text language sql immutable as $$
  select upper(translate(coalesce(t, ''),
    'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ',
    'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸ'));
$$;

create or replace function public.minuscules_fr(t text)
returns text language sql immutable as $$
  select lower(translate(coalesce(t, ''),
    'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸ',
    'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ'));
$$;

-- ===== 2. Casse titre =====
-- Le reste du mot est bien ABAISSÉ, pas seulement l'initiale élevée :
-- « MOUHAMED » doit donner « Mouhamed », la saisie tout en capitales
-- étant justement l'un des cas à corriger.
--
-- Coupent un mot : l'espace, le trait d'union et l'apostrophe -
-- « n'diaye » donne « N'Diaye », « marie-claire » donne « Marie-Claire ».
create or replace function public.casse_titre(t text)
returns text language plpgsql immutable as $$
declare
  v_src   text := regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g');
  v_out   text := '';
  v_debut boolean := true;
  v_c     text;
  i       int;
begin
  if v_src = '' then return null; end if;
  for i in 1..length(v_src) loop
    v_c := substr(v_src, i, 1);
    v_out := v_out || case when v_debut then public.majuscules_fr(v_c)
                           else public.minuscules_fr(v_c) end;
    v_debut := v_c in (' ', '-', '''', '’');
  end loop;
  return v_out;
end;
$$;

-- Nom de famille : capitales, espaces réduits.
create or replace function public.casse_nom(t text)
returns text language sql immutable as $$
  select nullif(public.majuscules_fr(
           regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g')), '');
$$;

-- ===== 3. Le déclencheur sur les profils =====
create or replace function public.normaliser_profil()
returns trigger language plpgsql as $$
begin
  new.first_name := public.casse_titre(new.first_name);
  new.last_name  := public.casse_nom(new.last_name);
  new.city       := public.casse_titre(new.city);

  -- Le nom complet est reconstruit quand les deux parties existent :
  -- « Mouhamed BADJI ». Sinon - inscription Google, qui ne fournit qu'un
  -- nom complet non découpé - on se contente de la casse titre : rien ne
  -- dit lequel des mots est le nom de famille, et le deviner écrirait une
  -- fausse identité.
  if new.first_name is not null and new.last_name is not null then
    new.full_name := new.first_name || ' ' || new.last_name;
  else
    new.full_name := public.casse_titre(new.full_name);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_normaliser_profil on public.profiles;
create trigger trg_normaliser_profil
  before insert or update on public.profiles
  for each row execute function public.normaliser_profil();

-- ===== 4. Le déclencheur sur les cartes =====
-- La LOCALITÉ seulement. member_cards.full_name n'est PAS retouché : il
-- porte un nom complet non découpé (« Dr Awa BA »), et lui appliquer la
-- casse titre écraserait les capitales du nom de famille - la carte
-- afficherait alors « Awa Ba » là où la fiche affiche « Awa BA », et le
-- repère de discordance de phase69 s'allumerait pour toujours. La casse
-- du nom est posée à l'import, où prénom et nom sont encore deux colonnes
-- distinctes.
create or replace function public.normaliser_carte()
returns trigger language plpgsql as $$
begin
  new.city := public.casse_titre(new.city);
  return new;
end;
$$;

drop trigger if exists trg_normaliser_carte on public.member_cards;
create trigger trg_normaliser_carte
  before insert or update on public.member_cards
  for each row execute function public.normaliser_carte();

-- ===== 5. La correction d'identité met en forme AVANT d'écrire =====
-- Copie de phase69, à DEUX lignes près : v_prenom et v_nom passent par la
-- mise en forme. Sans cela, admin_modifier_membre écrirait
-- « Mouhamed Badji » sur la carte et dans sa valeur de retour, pendant
-- que le déclencheur mettrait « Mouhamed BADJI » sur la fiche : le repère
-- de discordance de phase69 s'allumerait à chaque correction, et l'écran
-- afficherait la mauvaise casse jusqu'au rechargement.
create or replace function public.admin_modifier_membre(
  target_user_id uuid,
  p_title        text,
  p_first_name   text,
  p_last_name    text,
  p_domain       text,
  p_domain_autre text,
  p_specialty    text,
  p_city         text,
  p_region       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avant   public.profiles%rowtype;
  v_prenom  text;
  v_nom     text;
  v_complet text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select * into v_avant from public.profiles where id = target_user_id;
  if v_avant.id is null then
    raise exception 'Membre introuvable.';
  end if;

  v_prenom := public.casse_titre(p_first_name);
  v_nom    := public.casse_nom(p_last_name);

  if v_prenom is null or v_nom is null then
    raise exception 'Le prénom et le nom sont obligatoires.';
  end if;

  -- Mêmes listes fermées que la saisie du membre : l'administration
  -- corrige une fiche, elle n'invente pas de valeurs que le reste du
  -- site ne saurait pas afficher.
  if p_domain is null or p_domain not in
     ('medecine', 'pharmacie', 'odontologie', 'soins_infirmiers', 'soins_obstetricaux', 'autre') then
    raise exception 'Domaine invalide.';
  end if;
  if p_title is not null and p_title not in ('Dr', 'Pr') then
    raise exception 'Titre invalide : Dr, Pr, ou aucun.';
  end if;
  if p_region is not null and p_region not in (
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
    'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
    'Thiès', 'Ziguinchor'
  ) then
    raise exception 'Région invalide.';
  end if;

  v_complet := v_prenom || ' ' || v_nom;

  update public.profiles
     set title        = p_title,
         first_name   = v_prenom,
         last_name    = v_nom,
         full_name    = v_complet,
         domain       = p_domain,
         domain_autre = case when p_domain = 'autre'
                             then nullif(btrim(coalesce(p_domain_autre, '')), '')
                             else null end,
         specialty    = nullif(btrim(coalesce(p_specialty, '')), ''),
         city         = nullif(btrim(coalesce(p_city, '')), ''),
         region       = p_region
   where id = target_user_id;

  -- La carte attribuée porte désormais le même nom que sa fiche.
  update public.member_cards
     set full_name = v_complet
   where claimed_by = target_user_id
     and claim_status = 'confirmed'
     and full_name is distinct from v_complet;

  -- Le journal garde l'état d'avant : une correction d'identité est
  -- exactement le genre d'action qu'il faut pouvoir retracer, et le nom
  -- d'origine devient introuvable une fois écrasé.
  perform public.journaliser('membre_identite_modifiee', target_user_id, v_complet,
    jsonb_build_object(
      'avant', jsonb_build_object(
        'title', coalesce(v_avant.title, '(aucun)'),
        'first_name', coalesce(v_avant.first_name, '(aucun)'),
        'last_name', coalesce(v_avant.last_name, '(aucun)'),
        'full_name', coalesce(v_avant.full_name, '(aucun)'),
        'domain', coalesce(v_avant.domain, '(aucun)'),
        'domain_autre', coalesce(v_avant.domain_autre, '(aucun)'),
        'specialty', coalesce(v_avant.specialty, '(aucune)'),
        'city', coalesce(v_avant.city, '(aucune)'),
        'region', coalesce(v_avant.region, '(aucune)')),
      'apres', jsonb_build_object(
        'title', coalesce(p_title, '(aucun)'),
        'first_name', v_prenom,
        'last_name', v_nom,
        'full_name', v_complet,
        'domain', p_domain,
        'domain_autre', coalesce(nullif(btrim(coalesce(p_domain_autre, '')), ''), '(aucun)'),
        'specialty', coalesce(nullif(btrim(coalesce(p_specialty, '')), ''), '(aucune)'),
        'city', coalesce(nullif(btrim(coalesce(p_city, '')), ''), '(aucune)'),
        'region', coalesce(p_region, '(aucune)'))));

  -- L'écran rafraîchit sa liste avec ces valeurs, sans relire la base.
  -- La localité y est relue du profil : le déclencheur l'a mise en forme
  -- après l'écriture, et renvoyer la saisie brute afficherait « médina »
  -- dans la liste alors que la base porte « Médina ».
  return jsonb_build_object(
    'title', p_title, 'first_name', v_prenom, 'last_name', v_nom,
    'full_name', v_complet, 'domain', p_domain,
    'domain_autre', case when p_domain = 'autre'
                         then nullif(btrim(coalesce(p_domain_autre, '')), '') end,
    'specialty', nullif(btrim(coalesce(p_specialty, '')), ''),
    'city', (select city from public.profiles where id = target_user_id),
    'region', p_region);
end;
$$;

revoke all on function public.admin_modifier_membre(uuid, text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.admin_modifier_membre(uuid, text, text, text, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ===== 6. Ce que la reprise va changer, AVANT de l'appliquer =====
select email,
       full_name  as avant,
       case when first_name is not null and last_name is not null
            then public.casse_titre(first_name) || ' ' || public.casse_nom(last_name)
            else public.casse_titre(full_name) end as apres,
       city       as localite_avant,
       public.casse_titre(city) as localite_apres
  from public.profiles
 where full_name is distinct from (
         case when first_name is not null and last_name is not null
              then public.casse_titre(first_name) || ' ' || public.casse_nom(last_name)
              else public.casse_titre(full_name) end)
    or city is distinct from public.casse_titre(city)
 order by full_name;

-- ===== 7. Reprise de l'existant =====
-- « set id = id » : une écriture sans effet propre, dont le seul but est
-- de déclencher trg_normaliser_profil sur chaque ligne. Toute la mise en
-- forme vient du déclencheur, et reste ainsi définie à un seul endroit.
update public.profiles set id = id;
update public.member_cards set id = id;

-- ===== 8. Contrôle : plus rien à corriger =====
select count(*) as profils_encore_mal_casses
  from public.profiles
 where first_name is distinct from public.casse_titre(first_name)
    or last_name  is distinct from public.casse_nom(last_name)
    or city       is distinct from public.casse_titre(city);
