-- ============================================================
-- PHASE 28 — Annuaire des membres (espace membres uniquement).
--
-- Aucune policy RLS n'est ajoutée sur profiles : les policies existantes
-- (schema.sql) restent "un membre ne voit que sa propre ligne, sauf
-- admin". Cette phase ajoute une fonction RPC dédiée, SECURITY DEFINER,
-- qui expose volontairement un sous-ensemble limité de colonnes (jamais
-- l'e-mail, le téléphone, le rôle, le statut de carte...) pour tout
-- membre approuvé, avec la même protection anti-aspiration que les
-- autres listes du site (LIMIT + limite de fréquence, voir phase26 et
-- phase27).
--
-- À exécuter une seule fois dans Supabase : Dashboard > SQL Editor > New
-- query > coller > Run (après phase27-rate-limiting-rpc.sql).
-- ============================================================

create or replace function public.member_directory(p_limit int default 300)
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
  member_since  int
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
           p.domain, p.domain_autre, p.specialty, p.city, p.photo_url, p.member_since
    from public.profiles p
    where p.status = 'approved' and p.is_active
    order by p.last_name nulls last, p.full_name
    limit least(coalesce(p_limit, 300), 500);
end;
$$;

grant execute on function public.member_directory(int) to authenticated;
