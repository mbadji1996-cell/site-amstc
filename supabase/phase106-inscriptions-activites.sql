-- ============================================================
-- PHASE 106 - Inscriptions à une activité (formulaire public ordonné)
--
-- LE BESOIN. Ouvrir les inscriptions à une activité - une campagne de
-- consultations, une journée de formation - à qui veut s'inscrire, y
-- compris à des gens sans compte, en retenant l'ordre d'arrivée et en
-- privilégiant les membres.
--
-- POURQUOI PAS collectes (phase 55). Celle-ci exige un compte
-- (user_id not null), et tourne autour d'un paiement. Ici l'inscription
-- est gratuite, ouverte à tous, et ce qui compte est l'ORDRE.
--
-- L'IDENTITÉ EST FIXE, LES QUESTIONS SONT LIBRES. Nom, téléphone,
-- e-mail et localité sont toujours demandés : ce sont eux qui
-- dédoublonnent, qui rattachent à un compte existant et qui permettent
-- de rappeler quelqu'un. Les questions propres à l'activité vivent dans
-- « questions » (jsonb) et leurs réponses dans « reponses » - la
-- souplesse d'un formulaire libre, sans perdre ce qui fait marcher le
-- classement.
--
-- LA RÈGLE DES PLACES, QUI EST LE CŒUR DE CETTE PHASE.
--   places             - le total (null = illimité)
--   places_non_membres - la part GARANTIE aux personnes sans compte
--   le reste           - pour les membres
-- Et un rattrapage dans les deux sens : la part qu'un groupe ne remplit
-- pas revient à l'autre, dans l'ordre chronologique. Sans ce rattrapage,
-- une activité pourrait se tenir avec des places vides pendant que des
-- gens attendent - ce qui n'aurait aucun sens.
--
-- RECONNAÎTRE UN MEMBRE se fait de DEUX façons, et à la LECTURE :
--   - il était connecté en s'inscrivant (user_id) ;
--   - son téléphone correspond à un profil (telephone_cle, phase 78).
-- À la lecture, et non à l'inscription : quelqu'un qui crée son compte
-- la semaine suivante devient membre pour cette activité aussi, sans
-- qu'on ait rien à reprendre à la main.
--
-- LES INSCRITS NE SONT JAMAIS PUBLICS. Le formulaire est ouvert, la
-- liste ne l'est pas : elle contient des noms et des numéros. Seuls les
-- administrateurs la lisent.
--
-- L'ÉCRITURE PASSE PAR UNE FONCTION SECURITY DEFINER, comme partout sur
-- cette instance. Elle seule décide de user_id : posé depuis auth.uid(),
-- il ne peut pas être forgé par l'appelant pour se déclarer membre.
--
-- PRÉREQUIS : phase 2 (is_admin), phase 78 (telephone_cle).
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create table if not exists public.activites (
  id                 uuid primary key default gen_random_uuid(),
  titre              text not null,
  description        text,
  lieu               text,
  date_activite      date,
  -- null = pas de limite de places.
  places             int check (places is null or places > 0),
  -- Part garantie aux personnes SANS compte. Le reste va aux membres.
  places_non_membres int not null default 0 check (places_non_membres >= 0),
  date_limite        date,
  -- [{ "id": "q1", "label": "...", "type": "texte|long|choix",
  --    "obligatoire": true, "options": ["Oui", "Non"] }]
  questions          jsonb not null default '[]'::jsonb,
  is_open            boolean not null default true,
  created_by         uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  constraint quota_non_membres_tient_dans_les_places
    check (places is null or places_non_membres <= places)
);

create table if not exists public.activite_inscriptions (
  id            uuid primary key default gen_random_uuid(),
  activite_id   uuid not null references public.activites(id) on delete cascade,
  nom           text not null,
  telephone     text not null,
  -- Colonne GÉNÉRÉE : impossible qu'elle diverge du téléphone, et c'est
  -- elle qui porte l'unicité et le rattachement au profil.
  telephone_cle text generated always as (public.telephone_cle(telephone)) stored,
  email         text,
  localite      text,
  reponses      jsonb not null default '{}'::jsonb,
  -- Renseigné seulement si la personne était connectée. Jamais fourni
  -- par l'appelant : la fonction d'inscription le pose depuis auth.uid().
  user_id       uuid references public.profiles(id) on delete set null,
  statut        text not null default 'inscrit'
                check (statut in ('inscrit', 'desiste', 'present', 'absent')),
  note_admin    text,
  created_at    timestamptz not null default now()
);

-- Une personne, une inscription par activité. Le numéro normalisé fait
-- foi : « 77 123 45 67 » et « +221771234567 » sont la même personne.
create unique index if not exists activite_inscriptions_unicite
  on public.activite_inscriptions (activite_id, telephone_cle);

create index if not exists activite_inscriptions_ordre
  on public.activite_inscriptions (activite_id, created_at);

alter table public.activites enable row level security;
alter table public.activite_inscriptions enable row level security;

-- Les activités OUVERTES sont lisibles par tous : c'est ce qui permet à
-- la page publique d'afficher le formulaire sans compte. Les activités
-- fermées ou en préparation ne sortent pas.
grant select on public.activites to anon, authenticated;

drop policy if exists "Anyone can view open activites" on public.activites;
create policy "Anyone can view open activites"
  on public.activites for select
  to anon, authenticated
  using (is_open);

drop policy if exists "Admins can view all activites" on public.activites;
create policy "Admins can view all activites"
  on public.activites for select
  using (public.is_admin());

-- Aucune policy d'écriture : tout passe par les fonctions ci-dessous.
-- Et AUCUNE policy de lecture sur les inscriptions pour anon : la liste
-- porte des noms et des numéros.
drop policy if exists "Admins can view inscriptions" on public.activite_inscriptions;
create policy "Admins can view inscriptions"
  on public.activite_inscriptions for select
  using (public.is_admin());

-- ============================================================
-- S'INSCRIRE
--
-- Rend la position chronologique provisoire, pour l'afficher tout de
-- suite à la personne. « Provisoire » n'est pas une précaution de
-- style : un membre inscrit plus tard peut passer devant, tant que
-- l'activité n'est pas close.
-- ============================================================
create or replace function public.activite_inscrire(
  p_activite_id uuid,
  p_nom text,
  p_telephone text,
  p_email text default null,
  p_localite text default null,
  p_reponses jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_act    public.activites;
  v_cle    text := public.telephone_cle(p_telephone);
  v_nom    text := trim(coalesce(p_nom, ''));
  v_id     uuid;
  v_rang   int;
begin
  select * into v_act from public.activites where id = p_activite_id;
  if not found then
    return jsonb_build_object('ok', false, 'erreur', 'Cette activité n''existe pas.');
  end if;
  if not v_act.is_open then
    return jsonb_build_object('ok', false, 'erreur', 'Les inscriptions à cette activité sont closes.');
  end if;
  if v_act.date_limite is not null and v_act.date_limite < current_date then
    return jsonb_build_object('ok', false, 'erreur', 'La date limite d''inscription est passée.');
  end if;
  if v_nom = '' then
    return jsonb_build_object('ok', false, 'erreur', 'Le nom est obligatoire.');
  end if;
  -- Neuf chiffres après retrait de l'indicatif : la forme sénégalaise.
  -- Un numéro incomplet rendrait le rappel impossible et casserait le
  -- dédoublonnage, qui repose entièrement dessus.
  if v_cle is null or length(v_cle) <> 9 then
    return jsonb_build_object('ok', false, 'erreur',
      'Le numéro de téléphone doit comporter 9 chiffres, par exemple 77 123 45 67.');
  end if;

  if exists (
    select 1 from public.activite_inscriptions
     where activite_id = p_activite_id and telephone_cle = v_cle
  ) then
    return jsonb_build_object('ok', false, 'deja_inscrit', true, 'erreur',
      'Ce numéro est déjà inscrit à cette activité.');
  end if;

  insert into public.activite_inscriptions
    (activite_id, nom, telephone, email, localite, reponses, user_id)
  values
    (p_activite_id, v_nom, trim(p_telephone), nullif(trim(coalesce(p_email, '')), ''),
     nullif(trim(coalesce(p_localite, '')), ''), coalesce(p_reponses, '{}'::jsonb), auth.uid())
  returning id into v_id;

  select count(*)::int into v_rang
    from public.activite_inscriptions
   where activite_id = p_activite_id and statut <> 'desiste';

  return jsonb_build_object('ok', true, 'id', v_id, 'position', v_rang);
end;
$$;

-- ============================================================
-- LE CLASSEMENT
--
-- Rendu dans l'ordre où un administrateur le lit : les retenus d'abord,
-- par ordre d'arrivée, puis la liste d'attente, par ordre d'arrivée.
--
-- L'ATTRIBUTION SE FAIT EN DEUX TEMPS :
--   1. chaque groupe remplit sa part - les non-membres leur quota
--      garanti, les membres tout le reste ;
--   2. les places qu'un groupe n'a pas consommées reviennent à l'autre,
--      dans l'ordre chronologique. C'est ce second temps qui évite une
--      activité à moitié vide avec des gens en attente.
-- ============================================================
create or replace function public.activite_classement(p_activite_id uuid)
returns table(
  id             uuid,
  nom            text,
  telephone      text,
  email          text,
  localite       text,
  reponses       jsonb,
  statut         text,
  note_admin     text,
  est_membre     boolean,
  membre_nom     text,
  created_at     timestamptz,
  rang           int,
  retenu         boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_places      int;
  v_non_membres int;
  v_membres     int;
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;

  select a.places, a.places_non_membres into v_places, v_non_membres
    from public.activites a where a.id = p_activite_id;
  -- Illimité : tout le monde est retenu, seul l'ordre compte.
  v_non_membres := coalesce(v_non_membres, 0);
  v_membres := case when v_places is null then null else greatest(0, v_places - v_non_membres) end;

  return query
  with base as (
    select i.id, i.nom, i.telephone, i.email, i.localite, i.reponses,
           i.statut, i.note_admin, i.created_at,
           (i.user_id is not null or p.id is not null) as est_membre,
           p.full_name as membre_nom
      from public.activite_inscriptions i
      -- Le rattachement se fait ICI, pas à l'inscription : une
      -- adhésion postérieure vaut pour les inscriptions passées.
      left join lateral (
        select pr.id, pr.full_name
          from public.profiles pr
         where public.telephone_cle(pr.phone) = i.telephone_cle
         order by pr.created_at asc
         limit 1
      ) p on true
     where i.activite_id = p_activite_id
  ),
  -- Les désistements sortent du classement mais restent affichés : on
  -- les remet à la fin, sans place.
  actifs as (
    select b.*,
           row_number() over (partition by b.est_membre order by b.created_at, b.id) as rang_groupe
      from base b
     where b.statut <> 'desiste'
  ),
  quota as (
    select a.*,
           case
             when v_places is null then true
             when a.est_membre then a.rang_groupe <= coalesce(v_membres, 0)
             else a.rang_groupe <= v_non_membres
           end as retenu_quota
      from actifs a
  ),
  repechage as (
    select q.*,
           case
             when q.retenu_quota then true
             else row_number() over (
                    partition by q.retenu_quota order by q.created_at, q.id
                  ) <= greatest(0, coalesce(v_places, 0)
                                   - (select count(*) from quota where retenu_quota))
           end as retenu_final
      from quota q
  ),
  ordonne as (
    select r.id, r.nom, r.telephone, r.email, r.localite, r.reponses,
           r.statut, r.note_admin, r.est_membre, r.membre_nom, r.created_at,
           r.retenu_final as retenu
      from repechage r
    union all
    select b.id, b.nom, b.telephone, b.email, b.localite, b.reponses,
           b.statut, b.note_admin, b.est_membre, b.membre_nom, b.created_at,
           false
      from base b
     where b.statut = 'desiste'
  )
  select o.id, o.nom, o.telephone, o.email, o.localite, o.reponses,
         o.statut, o.note_admin, o.est_membre, o.membre_nom, o.created_at,
         (row_number() over (
            order by (o.statut = 'desiste'), (not o.retenu), o.created_at, o.id
          ))::int as rang,
         o.retenu
    from ordonne o
   order by (o.statut = 'desiste'), (not o.retenu), o.created_at, o.id;
end;
$$;

-- ============================================================
-- ADMINISTRER
-- ============================================================
create or replace function public.activite_enregistrer(
  p_id uuid,
  p_titre text,
  p_description text,
  p_lieu text,
  p_date_activite date,
  p_places int,
  p_places_non_membres int,
  p_date_limite date,
  p_questions jsonb,
  p_is_open boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;
  if trim(coalesce(p_titre, '')) = '' then
    raise exception 'Le titre est obligatoire';
  end if;
  if p_places is not null and coalesce(p_places_non_membres, 0) > p_places then
    raise exception 'Les places réservées aux non-membres dépassent le total des places';
  end if;

  if p_id is null then
    insert into public.activites
      (titre, description, lieu, date_activite, places, places_non_membres,
       date_limite, questions, is_open, created_by)
    values
      (trim(p_titre), nullif(trim(coalesce(p_description, '')), ''),
       nullif(trim(coalesce(p_lieu, '')), ''), p_date_activite, p_places,
       coalesce(p_places_non_membres, 0), p_date_limite,
       coalesce(p_questions, '[]'::jsonb), coalesce(p_is_open, true), auth.uid())
    returning id into v_id;
  else
    update public.activites set
      titre = trim(p_titre),
      description = nullif(trim(coalesce(p_description, '')), ''),
      lieu = nullif(trim(coalesce(p_lieu, '')), ''),
      date_activite = p_date_activite,
      places = p_places,
      places_non_membres = coalesce(p_places_non_membres, 0),
      date_limite = p_date_limite,
      questions = coalesce(p_questions, '[]'::jsonb),
      is_open = coalesce(p_is_open, true)
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Activité introuvable';
    end if;
  end if;

  return v_id;
end;
$$;

create or replace function public.activite_marquer(
  p_inscription_id uuid,
  p_statut text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;
  if p_statut not in ('inscrit', 'desiste', 'present', 'absent') then
    raise exception 'Statut inconnu : %', p_statut;
  end if;
  update public.activite_inscriptions
     set statut = p_statut,
         note_admin = nullif(trim(coalesce(p_note, '')), '')
   where id = p_inscription_id;
end;
$$;

-- Le compte des inscrits d'une activité, pour la page publique : elle
-- doit pouvoir dire « 32 inscrits sur 50 places » sans lire la liste.
create or replace function public.activite_compte(p_activite_id uuid)
returns int
language sql
security definer
set search_path = public
as $$
  select count(*)::int
    from public.activite_inscriptions
   where activite_id = p_activite_id and statut <> 'desiste';
$$;

revoke all on function public.activite_inscrire(uuid, text, text, text, text, jsonb) from public;
revoke all on function public.activite_classement(uuid) from public, anon;
revoke all on function public.activite_enregistrer(uuid, text, text, text, date, int, int, date, jsonb, boolean) from public, anon;
revoke all on function public.activite_marquer(uuid, text, text) from public, anon;
revoke all on function public.activite_compte(uuid) from public;

grant execute on function public.activite_inscrire(uuid, text, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.activite_compte(uuid) to anon, authenticated;
grant execute on function public.activite_classement(uuid) to authenticated;
grant execute on function public.activite_enregistrer(uuid, text, text, text, date, int, int, date, jsonb, boolean) to authenticated;
grant execute on function public.activite_marquer(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - rien n'est créé, rien n'est envoyé
--
-- Comme aux phases 104 et 105, ils n'appellent pas les fonctions
-- réservées aux administrateurs : is_admin() lit auth.uid(), inexistant
-- dans l'éditeur SQL. Elles se vérifient depuis la page, connecté.
-- ============================================================
-- a) Les deux tables existent.
select
  (select count(*) from public.activites) as activites,
  (select count(*) from public.activite_inscriptions) as inscriptions;

-- b) Les cinq fonctions sont en place.
select p.proname, pg_get_function_identity_arguments(p.oid) as parametres
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('activite_inscrire', 'activite_classement',
                     'activite_enregistrer', 'activite_marquer', 'activite_compte')
 order by p.proname;

-- c) La colonne générée fonctionne : elle doit rendre 9 chiffres pour
--    les trois écritures d'un même numéro.
select public.telephone_cle('77 123 45 67')   as saisie_espacee,
       public.telephone_cle('+221771234567')  as saisie_internationale,
       public.telephone_cle('771234567')      as saisie_brute;
