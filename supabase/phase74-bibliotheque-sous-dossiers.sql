-- ============================================================
-- PHASE 74 - Sous-dossiers de la bibliothèque
--
-- Un dossier peut contenir des sous-dossiers, et un document se range
-- dans l'un ou dans l'autre.
--
-- DEUX NIVEAUX, PAS PLUS, et c'est délibéré. Une profondeur libre est
-- facile à écrire et pénible à vivre : l'écran membre devient un
-- labyrinthe, et un document enfoui à quatre niveaux ne se retrouve
-- plus. Deux niveaux couvrent le besoin réel - « Médecine » puis
-- « Cardiologie » - et gardent la bibliothèque lisible d'un coup d'œil.
-- La règle est tenue par un déclencheur, pas seulement par l'écran : une
-- contrainte que seule l'interface applique finit toujours par être
-- contournée.
--
-- SUPPRIMER UN DOSSIER PARENT supprime ses sous-dossiers - ils n'ont
-- aucun sens sans lui - mais AUCUN DOCUMENT : ceux des deux niveaux se
-- retrouvent « sans dossier » et restent consultables. C'est la règle
-- posée en phase73, et elle continue de s'appliquer.
--
-- À exécuter après phase73. Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Le rattachement à un dossier parent =====
-- « on delete cascade » : supprimer un dossier emporte ses sous-dossiers.
-- Les DOCUMENTS, eux, sont protégés par le « on delete set null » posé en
-- phase73 sur restricted_articles.dossier_id.
alter table public.bibliotheque_dossiers
  add column if not exists parent_id uuid
  references public.bibliotheque_dossiers(id) on delete cascade;

create index if not exists bibliotheque_dossiers_parent_idx
  on public.bibliotheque_dossiers (parent_id);

-- ===== 2. Deux dossiers de même nom, mais pas sous le même parent =====
-- « Généralités » a toute sa place sous Médecine ET sous Pharmacie.
-- L'unicité posée en phase73 était globale et l'aurait interdit.
--
-- coalesce vers un UUID fixe : NULL n'entre pas dans l'égalité d'un index
-- unique, deux dossiers RACINE du même nom passeraient donc au travers.
drop index if exists bibliotheque_dossiers_nom_unique;
create unique index if not exists bibliotheque_dossiers_nom_par_parent
  on public.bibliotheque_dossiers (
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(btrim(nom))
  );

-- ===== 3. La profondeur est tenue en base =====
create or replace function public.bibliotheque_dossier_deux_niveaux()
returns trigger
language plpgsql
as $$
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'Un dossier ne peut pas être son propre dossier parent.';
    end if;

    -- Le parent est déjà un sous-dossier : on créerait un troisième niveau.
    if exists (
      select 1 from public.bibliotheque_dossiers
       where id = new.parent_id and parent_id is not null
    ) then
      raise exception 'Un sous-dossier ne peut pas contenir d''autres sous-dossiers.';
    end if;

    -- Ce dossier a lui-même des sous-dossiers : le rattacher en ferait un
    -- troisième niveau par le bas.
    if exists (
      select 1 from public.bibliotheque_dossiers where parent_id = new.id
    ) then
      raise exception 'Ce dossier contient des sous-dossiers : il ne peut pas devenir lui-même un sous-dossier.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_bibliotheque_deux_niveaux on public.bibliotheque_dossiers;
create trigger trg_bibliotheque_deux_niveaux
  before insert or update of parent_id on public.bibliotheque_dossiers
  for each row execute function public.bibliotheque_dossier_deux_niveaux();

-- ===== 4. La liste des dossiers renvoie le parent =====
-- Rien à changer côté documents : un document pointe vers un dossier,
-- que celui-ci soit racine ou sous-dossier. C'est l'affichage qui
-- reconstitue la hiérarchie.

notify pgrst, 'reload schema';

-- ===== 5. Contrôle : l'arborescence et ce qu'elle contient =====
select coalesce(p.nom, d.nom)                as dossier,
       case when p.id is null then '' else d.nom end as sous_dossier,
       count(a.id)                           as documents
  from public.bibliotheque_dossiers d
  left join public.bibliotheque_dossiers p on p.id = d.parent_id
  left join public.restricted_articles a
         on a.dossier_id = d.id and a.category = 'bibliotheque'
 group by p.id, p.nom, d.id, d.nom, d.ordre
 union all
select '(sans dossier)', '', count(*)
  from public.restricted_articles
 where category = 'bibliotheque' and dossier_id is null
 order by 1, 2;
