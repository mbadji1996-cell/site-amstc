-- ============================================================
-- PHASE 7b — Les cotisations mensuelles ne sont payables que si
-- l'adhésion (validité de carte) est en cours de validité.
-- À exécuter après phase7-validite-cotisations.sql.
-- ============================================================

drop policy if exists "Members can insert own cotisation payments" on public.cotisation_payments;
create policy "Members can insert own cotisation payments"
  on public.cotisation_payments for insert
  with check (
    auth.uid() = user_id
    and public.is_approved_member()
    and exists (
      select 1 from public.profiles
      where id = auth.uid() and card_valid_until >= extract(year from now())::int
    )
  );
