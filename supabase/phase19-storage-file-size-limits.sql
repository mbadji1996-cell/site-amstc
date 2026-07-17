-- Phase 19 : corrige "Erreur d'envoi du fichier : The object exceeded the
-- maximum allowed size" lors de l'envoi d'un document/PDF (Contenu réservé,
-- Bibliothèque) ou d'une photo (Médiathèque, Boutique, profil).
--
-- Aucun des buckets créés jusqu'ici ne définissait file_size_limit :
-- Supabase retombait donc sur la limite par défaut du projet (souvent bien
-- inférieure à la taille d'un PDF de livre/document). On fixe explicitement
-- une limite généreuse par bucket.

update storage.buckets set file_size_limit = 52428800  where id = 'documents-reserves'; -- 50 Mo (PDF documents/livres)
update storage.buckets set file_size_limit = 10485760  where id = 'mediatheque-photos'; -- 10 Mo (photos, déjà redimensionnées côté client)
update storage.buckets set file_size_limit = 10485760  where id = 'boutique-photos';    -- 10 Mo (photos produits)
update storage.buckets set file_size_limit = 5242880   where id = 'member-photos';      -- 5 Mo (photo de profil)
