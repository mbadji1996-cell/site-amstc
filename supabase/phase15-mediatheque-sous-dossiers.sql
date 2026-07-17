-- ============================================================
-- PHASE 15 — Sous-dossiers imbriqués dans la Médiathèque.
--
-- Ajoute une auto-référence parent_id à media_folders, permettant une
-- profondeur illimitée de sous-dossiers (Année > Dossier > Sous-dossier
-- > Sous-sous-dossier > ...). Aucune policy RLS à modifier : les
-- policies existantes (phase14) ne regardent déjà que l'état de
-- publication de la ligne elle-même (ou du dossier parent immédiat pour
-- les photos), pas toute la chaîne d'ancêtres - ça reste vrai quelle que
-- soit la profondeur.
--
-- `on delete cascade` : supprimer un dossier supprime automatiquement
-- tous ses sous-dossiers (récursivement), qui cascadent eux-mêmes sur
-- leurs media_photos (FK déjà en place depuis la phase14).
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase14-mediatheque.sql).
-- ============================================================

alter table public.media_folders
  add column if not exists parent_id uuid references public.media_folders(id) on delete cascade;
