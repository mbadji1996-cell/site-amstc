-- ============================================================
-- PHASE 69 - Le nom de la carte suit celui de son porteur.
--
-- LA DISCORDANCE. Le nom existe à deux endroits : sur la ligne de la
-- carte (member_cards.full_name, tel qu'il a été importé du tableur) et
-- sur la fiche du membre (profiles). Tant que la carte n'est pas
-- attribuée, ce doublon est normal - la carte existe avant le compte.
--
-- Une fois la carte CONFIRMÉE, les deux devraient se rejoindre, et rien
-- ne les y obligeait :
--   - l'écran des cartes affiche member_cards.full_name,
--   - l'écran des membres affiche profiles.full_name,
--   - et LA CARTE IMPRIMÉE prend le nom de la FICHE DU MEMBRE
--     (dessinerCarteMembre lit p.first_name / p.last_name).
--
-- L'administration voyait donc deux noms pour une même personne, sans
-- savoir lequel serait imprimé. C'est la fiche du membre qui fait foi :
-- ce script y aligne la carte, une fois pour les cartes déjà
-- discordantes, puis en continu.
--
-- Le nom SEUL est aligné. La localité et la région de la carte ne le sont
-- pas : elles n'ont servi qu'à alimenter le profil au moment de
-- l'invitation, leur divergence ultérieure est sans conséquence, et les
-- écraser détruirait la trace de ce qui avait été importé.
--
-- À exécuter après phase67. Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Les cartes discordantes, AVANT correction =====
-- À lire : c'est la liste de ce que l'étape 2 va modifier.
select c.card_number,
       c.full_name  as nom_sur_la_carte,
       p.full_name  as nom_du_membre,
       p.email
  from public.member_cards c
  join public.profiles p on p.id = c.claimed_by
 where c.claim_status = 'confirmed'
   and btrim(coalesce(p.full_name, '')) <> ''
   and c.full_name is distinct from p.full_name
 order by c.card_number;

-- ===== 2. Alignement des cartes déjà attribuées =====
update public.member_cards c
   set full_name = p.full_name
  from public.profiles p
 where p.id = c.claimed_by
   and c.claim_status = 'confirmed'
   and btrim(coalesce(p.full_name, '')) <> ''
   and c.full_name is distinct from p.full_name;

-- ===== 3. Et désormais, à chaque correction d'identité =====
-- Reprend admin_modifier_membre (phase67) en y ajoutant l'alignement de
-- la carte. Corriger une identité sans propager laisserait réapparaître
-- la discordance dès la première correction.
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

  v_prenom := nullif(btrim(coalesce(p_first_name, '')), '');
  v_nom    := nullif(btrim(coalesce(p_last_name, '')), '');

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
  return jsonb_build_object(
    'title', p_title, 'first_name', v_prenom, 'last_name', v_nom,
    'full_name', v_complet, 'domain', p_domain,
    'domain_autre', case when p_domain = 'autre'
                         then nullif(btrim(coalesce(p_domain_autre, '')), '') end,
    'specialty', nullif(btrim(coalesce(p_specialty, '')), ''),
    'city', nullif(btrim(coalesce(p_city, '')), ''),
    'region', p_region);
end;
$$;

revoke all on function public.admin_modifier_membre(uuid, text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.admin_modifier_membre(uuid, text, text, text, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ===== 4. Contrôle : plus aucune carte confirmée ne diverge =====
select count(*) as cartes_encore_discordantes
  from public.member_cards c
  join public.profiles p on p.id = c.claimed_by
 where c.claim_status = 'confirmed'
   and btrim(coalesce(p.full_name, '')) <> ''
   and c.full_name is distinct from p.full_name;
