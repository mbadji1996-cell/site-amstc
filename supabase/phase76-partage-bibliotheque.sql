-- ============================================================
-- PHASE 76 - Métadonnées publiques de la bibliothèque (aperçus
-- de partage)
--
-- Les boutons « Partager » de la bibliothèque envoient un lien vers
-- membres/bibliotheque.html?doc=… ; sur WhatsApp, l'aperçu de ce lien
-- affiche le titre générique du site. Pour montrer le TITRE et la
-- COUVERTURE du document, une page d'aperçu est pré-générée par
-- document (voir scripts/build-pages-partage.js, dossier /b/), ce qui
-- suppose de connaître titres et couvertures au moment de la
-- construction.
--
-- Cette fonction expose donc, et UNIQUEMENT, ce qui figurera dans
-- l'aperçu : identifiant, titre, résumé, couverture. JAMAIS le fichier
-- lui-même ni la description longue, qui restent réservés aux membres.
-- Choix validé le 13/08/2026 : le titre et la couverture d'un livre de
-- la bibliothèque deviennent visibles de quiconque reçoit le lien.
--
-- Ouverte au rôle « anon » à dessein : la construction tourne dans
-- GitHub Actions avec la clé publique du site, sans secret
-- supplémentaire à gérer - même montage que la phase 54 (cours).
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor >
-- Run. Ré-exécutable sans danger.
-- ============================================================

create or replace function public.bibliotheque_metadonnees_publiques()
returns table (
  id          uuid,
  title       text,
  excerpt     text,
  cover_image text
)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.title, a.excerpt, a.cover_image
    from public.restricted_articles a
   where a.category = 'bibliotheque';
$$;

revoke all on function public.bibliotheque_metadonnees_publiques() from public;
grant execute on function public.bibliotheque_metadonnees_publiques() to anon;
grant execute on function public.bibliotheque_metadonnees_publiques() to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : doit lister les documents, sans chemin de fichier ni
-- contenu.
select title, cover_image is not null as avec_couverture
  from public.bibliotheque_metadonnees_publiques()
 order by title;
