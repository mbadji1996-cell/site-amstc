-- ============================================================
-- PHASE 102 - Trois campagnes pour un terrain à 15 000 000 FCFA
--
-- LE BESOIN. Le terrain de Tivaouane vaut désormais 15 000 000 FCFA
-- (600 m², contre 5 000 000 pour 300 m² au lancement), payable en trois
-- paliers de 5 000 000 FCFA - voir le dossier de projet et la page
-- projet.html?slug=2026-08-30-terrain-tivaouane-siege-amstc. La collecte
-- en cours reste au premier palier : elle devient « Campagne 1 », et
-- « Campagne 2 » / « Campagne 3 » sont créées dès maintenant, prêtes à
-- être activées d'un clic le moment venu, sans ressaisir le formulaire.
--
-- POURQUOI UNE NOUVELLE COLONNE, ET NON UN SIMPLE is_active. Rien dans
-- campagnes_dons ne distinguait « jamais encore activée » de « activée
-- puis fermée » : membres/dons-admin.html affichait donc les deux avec
-- la même étiquette « Fermée », fausse pour une campagne qui n'a pas
-- encore commencé. a_ete_active tranche ce point une bonne fois - posée
-- à true par activer_campagne_don() et jamais revenue en arrière.
--
-- CE QUE CETTE PHASE NE TOUCHE PAS. La campagne active aujourd'hui garde
-- son objectif (5 000 000 FCFA, déjà exact - vérifié via
-- campagne_don_publique() avant d'écrire ce script) et son montant
-- collecté, calculé comme toujours à partir des dons confirmés. Seul son
-- titre change.
--
-- PRÉREQUIS : phase 98 (campagnes_dons, activer_campagne_don).
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger, SAUF l'insertion des deux campagnes : la
-- ré-exécuter dupliquerait Campagne 2 et Campagne 3. Le contrôle (a) en
-- bas dit si elles existent déjà.
-- ============================================================

-- ============================================================
-- 1. LA COLONNE, ET SON BACKFILL
-- ============================================================
-- Toute campagne déjà en base avant cette phase est une VRAIE campagne,
-- active ou non - ce concept de brouillon « à venir » n'existait pas.
-- On les marque donc a_ete_active AVANT d'inserer les deux nouvelles,
-- qui elles doivent rester à false (valeur par défaut).
alter table public.campagnes_dons
  add column if not exists a_ete_active boolean not null default false;

update public.campagnes_dons set a_ete_active = true where not a_ete_active;

-- ============================================================
-- 2. activer_campagne_don() POSE DÉSORMAIS a_ete_active À TRUE
-- ============================================================
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
  update public.campagnes_dons set is_active = true, a_ete_active = true where id = p_id;

  perform public.journaliser('campagne_don_activee', p_id,
    (select titre from public.campagnes_dons where id = p_id), null);
end;
$$;

-- ============================================================
-- 3. LA CAMPAGNE EN COURS DEVIENT « CAMPAGNE 1 »
-- ============================================================
-- Le titre garde son objet (il s'affiche tel quel sur la page publique,
-- comme titre de la jauge - un « Campagne 1 » nu y perdrait tout son
-- sens pour un visiteur qui découvre la page) : « Campagne 1 » y est
-- préfixé, pas substitué.
update public.campagnes_dons
   set titre = 'Campagne 1 - Acquisition du terrain à Tivaouane'
 where is_active;

-- ============================================================
-- 4. CAMPAGNE 2 ET CAMPAGNE 3, EN ATTENTE
-- ============================================================
insert into public.campagnes_dons (titre, description, objectif_fcfa, is_active, a_ete_active)
select 'Campagne 2 - Acquisition du terrain à Tivaouane',
       'Deuxième palier de l''acquisition du terrain de Tivaouane : '
       || '5 000 000 FCFA supplémentaires pour poursuivre la sécurisation foncière.',
       5000000, false, false
where not exists (
  select 1 from public.campagnes_dons where titre = 'Campagne 2 - Acquisition du terrain à Tivaouane'
);

insert into public.campagnes_dons (titre, description, objectif_fcfa, is_active, a_ete_active)
select 'Campagne 3 - Acquisition du terrain à Tivaouane',
       'Troisième et dernier palier : les 5 000 000 FCFA qui achèvent '
       || 'l''acquisition du terrain de 600 m² à Tivaouane.',
       5000000, false, false
where not exists (
  select 1 from public.campagnes_dons where titre = 'Campagne 3 - Acquisition du terrain à Tivaouane'
);

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - aucun envoi, aucune activation
-- ============================================================
-- a) Les trois campagnes, dans l'ordre attendu.
select titre, objectif_fcfa, is_active, a_ete_active
  from public.campagnes_dons
 order by created_at;

-- b) La page publique voit-elle toujours exactement la meme chose
--    qu'avant cette phase, a l'exception du titre ?
select public.campagne_don_publique() as campagne_active;
