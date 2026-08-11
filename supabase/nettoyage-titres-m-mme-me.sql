-- ============================================================
-- NETTOYAGE - Retirer les titres M., Mme et Me des données existantes
--
-- Les formulaires ne proposent plus que « Aucune », Dr et Pr. Les profils
-- et les cartes enregistrés avant ce changement portent encore M., Mme ou
-- Me ; sans ce script, ces titres subsisteraient jusqu'à ce que chaque
-- membre rouvre sa fiche - au fil de l'eau, pendant des mois.
--
-- Deux tables sont concernées : public.profiles (le compte) et
-- public.member_cards (la carte, dont le titre est imprimé).
--
-- CE SCRIPT EFFACE DES DONNÉES. Il commence donc par les recopier dans
-- une table de sauvegarde, ce qui rend le retour en arrière possible :
-- la requête de restauration est donnée en fin de fichier.
--
-- La contrainte CHECK n'est PAS resserrée : elle accepte toujours les cinq
-- valeurs. Rien n'empêche donc de revenir en arrière, ni l'import Excel
-- des cartes de continuer à détecter ces titres.
--
-- À exécuter dans Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger : la seconde exécution ne trouvera plus rien.
-- ============================================================

-- ===== 1. Ce qui va être modifié, avant de toucher à quoi que ce soit =====
select 'profiles' as source, id, full_name, email, title
  from public.profiles
 where title in ('M.', 'Mme', 'Me')
union all
select 'member_cards', id, full_name, card_number, title
  from public.member_cards
 where title in ('M.', 'Mme', 'Me')
 order by source, full_name;

-- ===== 2. Sauvegarde =====
-- Créée une seule fois, puis complétée : rejouer le script ne l'écrase
-- pas et n'y ajoute rien en double, l'insertion étant filtrée.
create table if not exists public.titres_avant_nettoyage (
  source      text not null,
  ligne_id    uuid not null,
  titre       text not null,
  sauvegarde_le timestamptz not null default now(),
  primary key (source, ligne_id)
);

insert into public.titres_avant_nettoyage (source, ligne_id, titre)
select 'profiles', id, title from public.profiles where title in ('M.', 'Mme', 'Me')
union all
select 'member_cards', id, title from public.member_cards where title in ('M.', 'Mme', 'Me')
on conflict (source, ligne_id) do nothing;

-- ===== 3. Nettoyage =====
update public.profiles     set title = null where title in ('M.', 'Mme', 'Me');
update public.member_cards set title = null where title in ('M.', 'Mme', 'Me');

-- ===== 4. Contrôle =====
-- « restants » doit valoir 0 partout ; « sauvegardes » indique combien de
-- lignes pourraient être restaurées.
select 'profiles' as source,
       (select count(*) from public.profiles where title in ('M.', 'Mme', 'Me')) as restants,
       (select count(*) from public.titres_avant_nettoyage where source = 'profiles') as sauvegardes
union all
select 'member_cards',
       (select count(*) from public.member_cards where title in ('M.', 'Mme', 'Me')),
       (select count(*) from public.titres_avant_nettoyage where source = 'member_cards');

-- ===== Retour en arrière, si besoin =====
-- À exécuter séparément, jamais avec le reste :
--
--   update public.profiles p
--      set title = s.titre
--     from public.titres_avant_nettoyage s
--    where s.source = 'profiles' and s.ligne_id = p.id;
--
--   update public.member_cards c
--      set title = s.titre
--     from public.titres_avant_nettoyage s
--    where s.source = 'member_cards' and s.ligne_id = c.id;
--
-- Une fois la décision définitive, la sauvegarde peut être supprimée :
--   drop table public.titres_avant_nettoyage;
