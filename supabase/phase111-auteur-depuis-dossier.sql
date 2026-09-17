-- ============================================================
-- PHASE 111 - L'auteur reprend le nom du dossier
--
-- POURQUOI. Une bonne partie de la bibliothèque est rangée PAR AUTEUR :
-- le dossier « Cheikh Seydil Hadji Malick SY » contient ses ouvrages,
-- dont « Ya Kachifa Da'i ». Le champ auteur (phase 110) arrive vide sur
-- des dizaines de fiches déjà publiées, alors que l'information est déjà
-- là, dans le nom du dossier.
--
-- CE QUE FAIT CE SCRIPT. Les dossiers d'auteurs sont des dossiers
-- PRINCIPAUX ici : le script traite donc tous les dossiers, principaux
-- comme sous-dossiers, SAUF ceux que vous nommez à la partie 0 - ceux
-- qui désignent un domaine et non une personne (« Médecine »,
-- « Urgences »...). Les fiches qui portent déjà un auteur ne sont jamais
-- touchées, pour ne pas effacer une saisie faite à la main.
--
-- COMMENT S'EN SERVIR.
--   0. Complétez la liste des dossiers à EXCLURE.
--   1. Exécutez la partie 1 : elle montre ce qui changerait, sans écrire.
--   2. Si la liste est juste, exécutez la partie 2.
--   3. La partie 3 contrôle et liste ce qui reste sans auteur.
--
-- POUR UN SEUL DOSSIER, pas besoin de ce script : le bouton
-- « Auteur = <nom du dossier> », dans Administration > Bibliothèque >
-- Dossiers de la bibliothèque, fait le même travail en un clic.
-- ============================================================

-- ===== 0. Les dossiers qui ne sont PAS des auteurs =====
-- Une vue jetable, pour que les parties 1 et 2 lisent la même liste.
-- Ajoutez ou retirez des noms ; la comparaison ignore la casse.
create or replace temporary view dossiers_non_auteurs as
select unnest(array[
  'Médecine',
  'Islam',
  'Formations internes',
  'Documents administratifs',
  'Autres documents'
]) as nom;

-- ===== 1. Aperçu : ce qui changerait =====
select d.nom                                        as auteur_propose,
       case when d.parent_id is null then 'principal' else 'sous-dossier' end as niveau,
       count(*)                                     as documents,
       string_agg(a.title, ' | ' order by a.title)  as titres
  from public.restricted_articles a
  join public.bibliotheque_dossiers d on d.id = a.dossier_id
 where a.category = 'bibliotheque'
   and nullif(btrim(a.auteur), '') is null
   and lower(btrim(d.nom)) not in (select lower(btrim(nom)) from dossiers_non_auteurs)
 group by d.nom, d.parent_id
 order by d.nom;

-- ===== 2. L'écriture =====
-- À lancer seulement si la liste ci-dessus est juste.
update public.restricted_articles a
   set auteur = d.nom
  from public.bibliotheque_dossiers d
 where d.id = a.dossier_id
   and a.category = 'bibliotheque'
   and nullif(btrim(a.auteur), '') is null
   and lower(btrim(d.nom)) not in (select lower(btrim(nom)) from dossiers_non_auteurs);

-- ===== 3. Contrôle =====
select count(*) filter (where nullif(btrim(auteur), '') is not null) as avec_auteur,
       count(*) filter (where nullif(btrim(auteur), '') is null)     as sans_auteur,
       count(*)                                                      as total
  from public.restricted_articles
 where category = 'bibliotheque';

-- Les fiches restées sans auteur, avec leur dossier : à traiter à la main
-- ou par le bouton de l'administration.
select a.title, coalesce(d.nom, '(sans dossier)') as dossier
  from public.restricted_articles a
  left join public.bibliotheque_dossiers d on d.id = a.dossier_id
 where a.category = 'bibliotheque'
   and nullif(btrim(a.auteur), '') is null
 order by dossier, a.title;
