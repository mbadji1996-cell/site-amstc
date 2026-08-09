-- ============================================================
-- PHASE 54 - Métadonnées publiques des cours (aperçus de partage)
--
-- Quand un lien de cours est partagé sur WhatsApp, l'aperçu affiche
-- « Cours - Daara AMSTC » au lieu du titre réel : le robot de WhatsApp
-- n'exécute pas JavaScript, et l'hébergement statique sert le même
-- fichier quel que soit le ?id=. La correction consiste à pré-générer
-- une page d'aperçu par cours (voir scripts/build-pages-partage.js), ce
-- qui suppose de connaître les titres au moment de la construction.
--
-- Cette fonction expose donc, et UNIQUEMENT, ce qui figure déjà dans
-- l'aperçu : identifiant, titre, description, auteur, catégorie. Jamais
-- le contenu du cours, qui reste réservé aux membres approuvés.
--
-- Ouverte au rôle « anon » à dessein : la construction tourne dans
-- GitHub Actions avec la clé publique du site, sans secret
-- supplémentaire à gérer.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create or replace function public.cours_metadonnees_publiques()
returns table (
  source      text,
  id          uuid,
  title       text,
  description text,
  author      text,
  category    text
)
language sql
stable
security definer
set search_path = public
as $$
  select 'daara'::text, c.id, c.title, c.description, c.author, c.category
    from public.daara_courses c
   where c.is_published = true
  union all
  select 'medical'::text, l.id, l.title, l.description, l.author, l.category
    from public.medical_lessons l
   where l.is_published = true;
$$;

revoke all on function public.cours_metadonnees_publiques() from public;
grant execute on function public.cours_metadonnees_publiques() to anon;
grant execute on function public.cours_metadonnees_publiques() to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : doit lister les cours publiés, sans leur contenu.
select source, title, author from public.cours_metadonnees_publiques() order by source, title;
