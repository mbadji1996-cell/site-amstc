-- ============================================================
-- PHASE 56 - Les cotisations mensuelles redeviennent payables en
-- permanence (annule phase7b)
--
-- phase7b exigeait une carte en cours de validité pour déclarer un
-- paiement de cotisation. À l'usage, cette règle bloque exactement les
-- membres qu'on souhaite encaisser :
--   - le nouveau membre tout juste approuvé, dont la validité n'est pas
--     encore saisie par l'administration ;
--   - celui dont le changement d'année d'adhésion attend une validation ;
--   - celui dont la carte est expirée, qui veut précisément se remettre
--     à jour.
--
-- La cotisation mensuelle porte sur l'année en cours, pas sur l'année
-- d'adhésion : les deux n'ont pas à être liées. On revient donc à la
-- règle de phase7 - un membre approuvé déclare ses propres paiements,
-- l'administration les valide comme avant.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

drop policy if exists "Members can insert own cotisation payments" on public.cotisation_payments;
create policy "Members can insert own cotisation payments"
  on public.cotisation_payments for insert
  with check (
    auth.uid() = user_id
    and public.is_approved_member()
  );

notify pgrst, 'reload schema';

-- Contrôle : la condition ne doit plus mentionner card_valid_until.
select polname, pg_get_expr(polwithcheck, polrelid) as condition
  from pg_policy
 where polrelid = 'public.cotisation_payments'::regclass
   and polname = 'Members can insert own cotisation payments';
