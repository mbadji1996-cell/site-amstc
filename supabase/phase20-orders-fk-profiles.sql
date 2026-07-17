-- Phase 20 : corrige "Could not find a relationship between 'orders' and
-- 'user_id' in the schema cache" dans le panneau Commandes de la Boutique.
--
-- orders.user_id référençait auth.users(id) au lieu de public.profiles(id)
-- (contrairement à toutes les autres tables de paiement du site, ex.
-- card_validity_payments/cotisation_payments dans phase7), donc PostgREST
-- ne pouvait pas résoudre l'embed `profiles:user_id(full_name, email)`
-- utilisé par membres/boutique-admin.html pour afficher le nom du membre.
-- Les valeurs sont identiques (profiles.id = auth.users.id), ce changement
-- ne touche donc aucune donnée existante.

alter table public.orders drop constraint if exists orders_user_id_fkey;
alter table public.orders
  add constraint orders_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;
