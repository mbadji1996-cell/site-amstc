-- ============================================================
-- PHASE 29 — Ajoute le téléphone à l'annuaire des membres.
--
-- La Phase 28 excluait volontairement le téléphone par précaution. Décision
-- de l'association : l'annuaire reste réservé à l'espace membres (jamais
-- public), donc afficher le téléphone (déjà fourni par chaque membre à
-- l'inscription) aux autres membres approuvés reste raisonnable pour un
-- annuaire professionnel interne. Toujours aucune policy RLS ajoutée sur
-- profiles, ni changement du plafond LIMIT / de la limite de fréquence.
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase28-annuaire-membres.sql).
-- ============================================================

-- PostgreSQL n'autorise pas CREATE OR REPLACE pour changer les colonnes
-- d'une fonction RETURNS TABLE existante (même en ajoutant une colonne à
-- la fin) : il faut d'abord la supprimer.
drop function if exists public.member_directory(int);

create function public.member_directory(p_limit int default 300)
returns table (
  id            uuid,
  title         text,
  first_name    text,
  last_name     text,
  full_name     text,
  domain        text,
  domain_autre  text,
  specialty     text,
  city          text,
  photo_url     text,
  member_since  int,
  phone         text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_approved_member() then
    raise exception 'Accès réservé aux membres approuvés.';
  end if;

  perform public.check_rate_limit('member_directory', 30, interval '5 minutes');
  return query
    select p.id, p.title, p.first_name, p.last_name, p.full_name,
           p.domain, p.domain_autre, p.specialty, p.city, p.photo_url, p.member_since,
           p.phone
    from public.profiles p
    where p.status = 'approved' and p.is_active
    order by p.last_name nulls last, p.full_name
    limit least(coalesce(p_limit, 300), 500);
end;
$$;

grant execute on function public.member_directory(int) to authenticated;
