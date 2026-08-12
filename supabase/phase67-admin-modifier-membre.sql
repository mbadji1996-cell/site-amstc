-- ============================================================
-- PHASE 67 - L'administration corrige l'identité d'un membre.
--
-- POURQUOI. Les membres saisissent eux-mêmes leur fiche et ne respectent
-- pas toujours les consignes : prénom et nom intervertis, nom complet
-- entier collé dans la case « nom », domaine approximatif. Ces valeurs
-- partent telles quelles sur la CARTE DE MEMBRE IMPRIMÉE - il faut
-- pouvoir les corriger avant le tirage, sans attendre le membre.
--
-- L'administration disposait déjà de set_member_phone, set_member_years,
-- set_member_fonction et set_cotisations_membre : il manquait l'identité
-- elle-même. Une fonction par sujet, plutôt qu'un update global : la
-- journalisation reste lisible et chaque écran ne peut toucher que ce
-- qui le concerne.
--
-- La photo n'y figure pas : elle appartient au membre et se remplace
-- depuis sa propre fiche.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

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

-- Contrôle.
select proname from pg_proc where proname = 'admin_modifier_membre';
