-- ============================================================
-- PHASE 111 - L'auteur reprend le nom du dossier
--
-- POURQUOI. Une bonne partie de la bibliothèque est rangée PAR AUTEUR :
-- le sous-dossier « Cheikh Seydil Hadji Malick SY » contient ses
-- ouvrages, dont « Ya Kachifa Da'i ». Le champ auteur (phase 110) arrive
-- vide sur des dizaines de fiches déjà publiées ; l'information est déjà
-- là, dans le nom du dossier.
--
-- CE QUE FAIT CE SCRIPT. Il n'agit que sur les documents rangés dans un
-- SOUS-dossier : ce sont eux qui portent un nom d'auteur. Les dossiers
-- principaux nomment un domaine (« Médecine », « Islam »), pas une
-- personne, et sont laissés de côté. Les fiches qui portent déjà un
-- auteur ne sont jamais touchées.
--
-- COMMENT S'EN SERVIR. Exécutez d'abord la partie 1 seule : elle montre
-- ce qui changerait, sans rien écrire. Si la liste vous convient, lancez
-- la partie 2. La partie 3 contrôle le résultat.
--
-- POUR UN DOSSIER PRINCIPAL dont le nom EST un auteur, ne touchez pas à
-- ce script : le bouton « Auteur = <nom du dossier> », dans
-- Administration > Bibliothèque > Dossiers, fait le même travail pour ce
-- seul dossier, en un clic.
-- ============================================================

-- ===== 1. Aperçu : ce qui changerait =====
select d.nom            as auteur_propose,
       p.nom            as dossier_principal,
       count(*)         as documents,
       string_agg(a.title, ' | ' order by a.title) as titres
  from public.restricted_articles a
  join public.bibliotheque_dossiers d on d.id = a.dossier_id
  join public.bibliotheque_dossiers p on p.id = d.parent_id
 where a.category = 'bibliotheque'
   and d.parent_id is not null
   and coalesce(nullif(btrim(a.auteur), ''), null) is null
 group by d.nom, p.nom
 order by p.nom, d.nom;

-- ===== 2. L'écriture =====
-- À lancer seulement si la liste ci-dessus est juste.
update public.restricted_articles a
   set auteur = d.nom
  from public.bibliotheque_dossiers d
 where d.id = a.dossier_id
   and a.category = 'bibliotheque'
   and d.parent_id is not null
   and coalesce(nullif(btrim(a.auteur), ''), null) is null;

-- ===== 3. Contrôle =====
-- Combien de fiches portent un auteur, et combien n'en ont pas encore.
select count(*) filter (where coalesce(nullif(btrim(auteur), ''), null) is not null) as avec_auteur,
       count(*) filter (where coalesce(nullif(btrim(auteur), ''), null) is null)     as sans_auteur,
       count(*)                                                                      as total
  from public.restricted_articles
 where category = 'bibliotheque';

-- Les fiches restées sans auteur, avec leur dossier : c'est la liste à
-- traiter à la main ou par le bouton de l'administration.
select a.title, coalesce(d.nom, '(sans dossier)') as dossier
  from public.restricted_articles a
  left join public.bibliotheque_dossiers d on d.id = a.dossier_id
 where a.category = 'bibliotheque'
   and coalesce(nullif(btrim(a.auteur), ''), null) is null
 order by dossier, a.title;
