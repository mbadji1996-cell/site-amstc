-- ============================================================
-- PHASE 75 - Espace de stockage des images de couverture
--
-- CE QUI EXISTAIT. Les couvertures des cours, formations, leçons et
-- livres ne pouvaient être qu'une ADRESSE COLLÉE : il fallait avoir
-- hébergé l'image ailleurs. D'où la tentation du lien Google Drive, qui
-- ne fonctionne pas - une adresse de partage Drive désigne une PAGE WEB,
-- pas un fichier image, et aucun navigateur ne peut l'afficher dans une
-- balise <img>.
--
-- CE QUE FAIT CE SCRIPT. Un espace de stockage pour envoyer directement
-- l'image depuis l'écran d'administration.
--
-- BUCKET PUBLIC, et c'est indispensable, pas un relâchement :
--   - WhatsApp, Facebook et les moteurs lisent les aperçus de partage
--     SANS ÊTRE CONNECTÉS. Une couverture protégée n'apparaîtrait sur
--     aucun aperçu, ce qui est précisément ce que les pages /c/ servent
--     à obtenir.
--   - Les pages publiques montrent déjà titre, résumé et couverture des
--     contenus réservés, le corps du texte restant, lui, protégé.
--
-- Une couverture n'est jamais confidentielle : c'est une vignette
-- d'illustration. Le contenu réservé, lui, reste gouverné par ses
-- propres règles, inchangées.
--
-- L'ENVOI RESTE RÉSERVÉ AUX ADMINISTRATEURS : public en lecture ne veut
-- pas dire ouvert en écriture.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit)
values ('couvertures', 'couvertures', true, 5242880)  -- 5 Mo
on conflict (id) do update set public = true, file_size_limit = 5242880;

-- Lecture ouverte : c'est tout l'objet d'un bucket public, et la policy
-- doit l'autoriser explicitement pour anon comme pour authenticated.
drop policy if exists "Couvertures lisibles par tous" on storage.objects;
create policy "Couvertures lisibles par tous"
  on storage.objects for select
  using (bucket_id = 'couvertures');

drop policy if exists "Admins envoient les couvertures" on storage.objects;
create policy "Admins envoient les couvertures"
  on storage.objects for insert
  with check (bucket_id = 'couvertures' and public.is_admin());

drop policy if exists "Admins remplacent les couvertures" on storage.objects;
create policy "Admins remplacent les couvertures"
  on storage.objects for update
  using (bucket_id = 'couvertures' and public.is_admin());

drop policy if exists "Admins suppriment les couvertures" on storage.objects;
create policy "Admins suppriment les couvertures"
  on storage.objects for delete
  using (bucket_id = 'couvertures' and public.is_admin());

-- Contrôle : le bucket et sa limite.
select id,
       public as lecture_publique,
       coalesce((file_size_limit / 1048576)::text || ' Mo', 'illimité') as limite
  from storage.buckets
 where id = 'couvertures';
