-- ============================================================
-- PHASE 45 - Titres : accepter M., Mme et Me en plus de Dr et Pr.
--
-- Les sélecteurs de titre (inscription.html, profil.html) proposent
-- désormais M., Mme et Me, mais deux contraintes CHECK (phase6 sur
-- profiles, phase9 sur member_cards) ne toléraient que Dr et Pr : tout
-- enregistrement avec un nouveau titre échouerait sans cette migration.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

alter table public.profiles drop constraint if exists profiles_title_check;
alter table public.profiles add constraint profiles_title_check
  check (title is null or title in ('Dr', 'Pr', 'M.', 'Mme', 'Me'));

alter table public.member_cards drop constraint if exists member_cards_title_check;
alter table public.member_cards add constraint member_cards_title_check
  check (title is null or title in ('Dr', 'Pr', 'M.', 'Mme', 'Me'));
