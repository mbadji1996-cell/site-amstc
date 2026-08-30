-- ============================================================
-- PHASE 98 - Campagnes de collecte de fonds, avec compteur qui se tient
--            à jour tout seul
--
-- LE BESOIN. La page de don portait déjà une jauge, mais son montant
-- était TAPÉ À LA MAIN : le champ Decap disait en toutes lettres « à
-- mettre à jour manuellement au fil des dons reçus ». Un total retapé
-- est un total qui finit par être faux, et personne ne s'en aperçoit.
--
-- CE QUE « AUTOMATIQUE » VEUT DIRE ICI. L'association n'encaisse pas en
-- ligne : les dons arrivent par Wave, Orange Money, virement ou espèces.
-- Le site ne peut donc pas constater un paiement. Ce qu'il peut faire,
-- et c'est le vrai sujet, c'est CESSER DE DEMANDER UN TOTAL : la jauge
-- devient la somme des dons confirmés. Plus personne ne recalcule, plus
-- personne ne retape, et le chiffre affiché ne peut plus diverger de ce
-- qui a été validé.
--
-- LE PARCOURS, calqué sur ce qui fonctionne déjà pour les collectes de
-- l'espace membres (phase 55) :
--
--   1. Le donateur déclare son don sur la page publique - montant,
--      opérateur, référence de transaction, nom facultatif.
--   2. La déclaration arrive « en_attente ». Elle ne compte pas.
--   3. Un administrateur confirme (ou rejette) depuis son écran.
--   4. La jauge suit, d'elle-même.
--
-- Un administrateur peut aussi enregistrer directement un don reçu en
-- espèces ou par virement, sans déclaration préalable : tous les dons
-- ne passeront pas par le formulaire.
--
-- ------------------------------------------------------------
-- CE QUI EST PUBLIC, ET CE QUI NE L'EST PAS
-- ------------------------------------------------------------
-- La page n'affiche QUE le total et le pourcentage. Aucun nom, aucun
-- montant individuel, aucune référence de transaction. Ce n'est pas un
-- réglage d'affichage : la table des dons n'est PAS lisible par un
-- visiteur, et le total transite par une fonction qui ne renvoie que
-- des agrégats. Un curieux qui interrogerait l'API directement
-- n'obtiendrait rien de plus que ce que la page montre.
--
-- LE FORMULAIRE PUBLIC NE PEUT PAS CONFIRMER UN DON. La règle d'écriture
-- l'exige : status = 'en_attente', source = 'public', aucun champ de
-- validation renseigné. Sans cela, il aurait suffi d'un appel bien
-- formé pour gonfler la jauge de l'extérieur.
--
-- UNE SEULE CAMPAGNE ACTIVE À LA FOIS, garanti par un index unique
-- partiel plutôt que par la vigilance : deux campagnes actives et la
-- page ne saurait laquelle montrer.
--
-- PRÉREQUIS : schema.sql (is_admin), phase51 (journaliser), phase25
-- (notify_admin).
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ============================================================
-- 1. LES CAMPAGNES
-- ============================================================
create table if not exists public.campagnes_dons (
  id            uuid primary key default gen_random_uuid(),
  titre         text not null,
  description   text,
  objectif_fcfa int not null check (objectif_fcfa > 0),
  date_debut    date,
  date_fin      date,
  is_active     boolean not null default false,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles(id) on delete set null
);

-- OU DEPOSER LE DON, campagne par campagne. La page affiche sinon les
-- numeros de la Commission finances, qui sont ceux des COTISATIONS : une
-- campagne qui collecte ailleurs enverrait les dons au mauvais endroit.
-- Facultatifs : vides, la carte Mobile Money generale fait foi.
--
-- En « add column if not exists » plutot que dans le create ci-dessus :
-- la table existe peut-etre deja, et « create table if not exists » ne
-- rajoute aucune colonne a une table existante - en silence.
alter table public.campagnes_dons add column if not exists depot_wave text;
alter table public.campagnes_dons add column if not exists depot_orange text;
alter table public.campagnes_dons add column if not exists depot_titulaire text;

-- Une seule campagne active. L'index porte sur une constante : il ne
-- peut donc exister qu'UNE ligne parmi celles qui sont actives.
create unique index if not exists campagnes_dons_une_seule_active
  on public.campagnes_dons ((true)) where is_active;

alter table public.campagnes_dons enable row level security;

grant select, insert, update, delete on public.campagnes_dons to authenticated;

drop policy if exists "Admins gerent les campagnes de dons" on public.campagnes_dons;
create policy "Admins gerent les campagnes de dons"
  on public.campagnes_dons for all
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- 2. LES DONS
-- ============================================================
create table if not exists public.dons (
  id               uuid primary key default gen_random_uuid(),
  campagne_id      uuid references public.campagnes_dons(id) on delete set null,
  -- Facultatifs : un don peut être anonyme. Le contact ne sert qu'à
  -- délivrer un reçu et n'apparaît jamais publiquement.
  donateur_nom     text,
  donateur_contact text,
  montant_fcfa     int not null check (montant_fcfa > 0),
  methode          text check (methode in ('wave', 'orange_money', 'virement', 'especes', 'autre')),
  reference        text,
  message          text,
  status           text not null default 'en_attente'
                   check (status in ('en_attente', 'confirme', 'rejete')),
  source           text not null default 'public'
                   check (source in ('public', 'admin')),
  valide_par       uuid references public.profiles(id) on delete set null,
  valide_le        timestamptz,
  created_at       timestamptz not null default now()
);

-- Le calcul du total ne lit que les dons confirmés d'une campagne.
create index if not exists dons_campagne_status_idx
  on public.dons (campagne_id, status);
create index if not exists dons_attente_idx
  on public.dons (created_at desc) where status = 'en_attente';

alter table public.dons enable row level security;

-- Sans ce GRANT, Postgres refuse la table avant même d'évaluer les
-- règles ci-dessous (« permission denied for table dons »).
grant insert on public.dons to anon, authenticated;
grant select, update on public.dons to authenticated;

-- ===== Déclaration publique : ouverte, mais bridée =====
-- Les conditions ne sont pas décoratives. Sans « status = 'en_attente' »,
-- n'importe qui pourrait insérer un don DÉJÀ CONFIRMÉ et faire monter la
-- jauge depuis l'extérieur. Le plafond, lui, évite qu'une déclaration
-- fantaisiste à dix milliards ne trône dans la file d'attente.
drop policy if exists "Tout le monde peut declarer un don" on public.dons;
create policy "Tout le monde peut declarer un don"
  on public.dons for insert
  to anon, authenticated
  with check (
    status = 'en_attente'
    and source = 'public'
    and valide_par is null
    and valide_le is null
    and montant_fcfa > 0
    and montant_fcfa <= 100000000
  );

-- ===== Lecture et validation : administrateurs seuls =====
-- Aucune politique de SELECT pour anon : la table est invisible au
-- public, y compris par appel direct à l'API.
drop policy if exists "Admins lisent les dons" on public.dons;
create policy "Admins lisent les dons"
  on public.dons for select
  using (public.is_admin());

drop policy if exists "Admins valident les dons" on public.dons;
create policy "Admins valident les dons"
  on public.dons for update
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- 3. CE QUE VOIT LE PUBLIC - des agrégats, rien d'autre
-- ============================================================
-- Renvoie un objet JSON, et non une table : « returns table » aurait
-- déclaré titre, description… comme variables de la fonction, et toute
-- colonne homonyme aurait rendu la requête ambiguë (erreur 42702, déjà
-- rencontrée en phase 93). Un objet écarte le problème et permettra
-- d'ajouter un champ sans changer la signature.
--
-- Renvoie null quand aucune campagne n'est active : la page masque
-- alors la jauge et redevient la page de don générique.
create or replace function public.campagne_don_publique()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'titre',       c.titre,
    'description', c.description,
    'objectif',    c.objectif_fcfa,
    'collecte',    coalesce((select sum(d.montant_fcfa)
                               from public.dons d
                              where d.campagne_id = c.id
                                and d.status = 'confirme'), 0),
    'echeance',    c.date_fin,
    'depot_wave',      nullif(btrim(coalesce(c.depot_wave, '')), ''),
    'depot_orange',    nullif(btrim(coalesce(c.depot_orange, '')), ''),
    'depot_titulaire', nullif(btrim(coalesce(c.depot_titulaire, '')), '')
  )
  from public.campagnes_dons c
  where c.is_active
  limit 1;
$$;

revoke all on function public.campagne_don_publique() from public;
grant execute on function public.campagne_don_publique() to anon, authenticated;

-- Identifiant de la campagne active, pour que le formulaire rattache la
-- déclaration à la bonne campagne. Rien d'autre n'en sort.
create or replace function public.campagne_don_active_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id from public.campagnes_dons c where c.is_active limit 1;
$$;

revoke all on function public.campagne_don_active_id() from public;
grant execute on function public.campagne_don_active_id() to anon, authenticated;

-- ============================================================
-- 4. VALIDATION PAR L'ADMINISTRATION
-- ============================================================
create or replace function public.valider_don(p_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_d record;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if p_status not in ('confirme', 'rejete') then
    raise exception 'Statut inconnu : %', p_status;
  end if;

  select * into v_d from public.dons where id = p_id;
  if v_d is null then
    raise exception 'Don introuvable.';
  end if;

  update public.dons
     set status = p_status,
         valide_par = auth.uid(),
         valide_le = now()
   where id = p_id;

  perform public.journaliser('don_' || p_status, p_id,
    coalesce(nullif(btrim(v_d.donateur_nom), ''), '(anonyme)'),
    jsonb_build_object('montant', v_d.montant_fcfa, 'methode', v_d.methode,
                       'source', v_d.source));
end;
$$;

revoke all on function public.valider_don(uuid, text) from public, anon;
grant execute on function public.valider_don(uuid, text) to authenticated;

-- Enregistrer un don reçu hors du formulaire - espèces, virement, don
-- remis de la main à la main. Il entre CONFIRMÉ : c'est un administrateur
-- qui le constate, il n'y a personne d'autre pour le valider ensuite.
create or replace function public.enregistrer_don(
  p_montant int,
  p_methode text default 'especes',
  p_nom text default null,
  p_reference text default null,
  p_contact text default null,
  p_message text default null
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
    raise exception 'Accès refusé.';
  end if;
  if p_montant is null or p_montant <= 0 then
    raise exception 'Le montant doit être supérieur à zéro.';
  end if;

  insert into public.dons (campagne_id, donateur_nom, donateur_contact,
                           montant_fcfa, methode, reference, message,
                           status, source, valide_par, valide_le)
  values (public.campagne_don_active_id(),
          nullif(btrim(coalesce(p_nom, '')), ''),
          nullif(btrim(coalesce(p_contact, '')), ''),
          p_montant,
          coalesce(nullif(btrim(p_methode), ''), 'especes'),
          nullif(btrim(coalesce(p_reference, '')), ''),
          nullif(btrim(coalesce(p_message, '')), ''),
          'confirme', 'admin', auth.uid(), now())
  returning id into v_id;

  perform public.journaliser('don_enregistre', v_id,
    coalesce(nullif(btrim(coalesce(p_nom, '')), ''), '(anonyme)'),
    jsonb_build_object('montant', p_montant, 'methode', p_methode));
  return v_id;
end;
$$;

revoke all on function public.enregistrer_don(int, text, text, text, text, text)
  from public, anon;
grant execute on function public.enregistrer_don(int, text, text, text, text, text)
  to authenticated;

-- Le décompte affiché sur l'écran d'administration.
create or replace function public.apercu_dons()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  v_id := public.campagne_don_active_id();

  return jsonb_build_object(
    'en_attente',   (select count(*) from public.dons where status = 'en_attente'),
    'confirmes',    (select count(*) from public.dons where status = 'confirme'),
    'total_fcfa',   (select coalesce(sum(montant_fcfa), 0) from public.dons
                      where status = 'confirme' and campagne_id is not distinct from v_id),
    'total_general',(select coalesce(sum(montant_fcfa), 0) from public.dons
                      where status = 'confirme'),
    'campagne',     public.campagne_don_publique()
  );
end;
$$;

revoke all on function public.apercu_dons() from public, anon;
grant execute on function public.apercu_dons() to authenticated;

-- Activer une campagne, et désactiver l'ancienne DANS LE MÊME GESTE.
-- L'index unique interdit deux campagnes actives : sans cette fonction,
-- l'écran devrait désactiver puis activer en deux appels, avec un instant
-- où aucune campagne n'est affichée - et, si le second appel échoue, une
-- page de don sans jauge sans que personne l'ait voulu.
create or replace function public.activer_campagne_don(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  if not exists (select 1 from public.campagnes_dons where id = p_id) then
    raise exception 'Campagne introuvable.';
  end if;

  update public.campagnes_dons set is_active = false where is_active and id <> p_id;
  update public.campagnes_dons set is_active = true where id = p_id;

  perform public.journaliser('campagne_don_activee', p_id,
    (select titre from public.campagnes_dons where id = p_id), null);
end;
$$;

revoke all on function public.activer_campagne_don(uuid) from public, anon;
grant execute on function public.activer_campagne_don(uuid) to authenticated;

-- Fermer la campagne en cours : la page de don redevient generique.
create or replace function public.cloturer_campagne_don()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  update public.campagnes_dons set is_active = false where is_active;
  perform public.journaliser('campagne_don_cloturee', null, 'campagne active', null);
end;
$$;

revoke all on function public.cloturer_campagne_don() from public, anon;
grant execute on function public.cloturer_campagne_don() to authenticated;

-- ============================================================
-- 5. PRÉVENIR L'ADMINISTRATION D'UNE DÉCLARATION
-- ============================================================
-- Une déclaration qui dort dans la file ne compte pas : la jauge reste
-- fausse par le bas et le donateur ne voit rien venir. Même mécanisme
-- que les demandes de campagne (phase 33).
create or replace function public.notify_admin_on_don()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source = 'public' then
    perform public.notify_admin('don_declare', jsonb_build_object(
      'donateur_nom', coalesce(nullif(btrim(coalesce(new.donateur_nom, '')), ''), 'Anonyme'),
      'montant', new.montant_fcfa,
      'methode', coalesce(new.methode, '-'),
      'reference', coalesce(new.reference, '-'),
      'contact', coalesce(new.donateur_contact, '-'),
      'message', coalesce(new.message, '')
    ));
  end if;
  return new;
end;
$$;

drop trigger if exists on_don_created_notify_admin on public.dons;
create trigger on_don_created_notify_admin
  after insert on public.dons
  for each row execute function public.notify_admin_on_don();

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES
-- ============================================================
-- a) Les tables et fonctions sont-elles en place ?
select table_name from information_schema.tables
 where table_schema = 'public' and table_name in ('campagnes_dons', 'dons')
 order by table_name;

select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('campagne_don_publique', 'campagne_don_active_id',
                     'valider_don', 'enregistrer_don', 'apercu_dons',
                     'activer_campagne_don', 'cloturer_campagne_don')
 order by p.proname;

-- b) Aucune campagne active pour l'instant : doit renvoyer null, et la
--    page de don doit alors se comporter comme avant.
select public.campagne_don_publique() as campagne_active;

-- c) CRÉER UNE PREMIÈRE CAMPAGNE. Décommentez, ajustez, exécutez.
--    Vous pourrez ensuite tout modifier depuis l'écran d'administration.
--
-- insert into public.campagnes_dons (titre, description, objectif_fcfa, date_fin, is_active)
-- values ('Ndogou Social 2027',
--         'Aidez-nous à servir 500 repas pendant le mois de Ramadan.',
--         2000000, '2027-03-20', true);

-- d) La table des dons est-elle bien invisible au public ? Cette requête
--    doit renvoyer la ligne « anon : aucune politique de lecture ».
select case when exists (
         select 1 from pg_policies
          where tablename = 'dons' and cmd = 'SELECT'
            and 'anon' = any(roles))
       then 'ATTENTION : anon peut lire la table des dons'
       else 'anon : aucune politique de lecture - correct'
       end as controle_confidentialite;
