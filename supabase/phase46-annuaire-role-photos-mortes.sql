-- ============================================================
-- PHASE 46 - Annuaire : afficher qui est administrateur, et purger les
-- URL de photos mortes héritées de la migration.
--
-- 1. member_directory renvoie désormais le rôle, pour que l'annuaire
--    puisse marquer les comptes admin/super admin d'un badge. Le rôle
--    n'est pas une donnée sensible : il est déjà visible de tous sur les
--    pages qu'administrent ces comptes.
--
-- 2. Les photos envoyées AVANT la migration vers le VPS (24/07/2026)
--    pointent encore vers l'ancienne instance cloud (*.supabase.co),
--    éteinte : carte de membre et annuaire affichaient une image cassée.
--    On remet ces photo_url à NULL : les pages retombent proprement sur
--    les initiales, et la bannière « complétez votre profil » invite le
--    membre à renvoyer sa photo. Seul api.amstc.org est un hôte valide.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger (la purge ne touche que les URL étrangères).
-- ============================================================

-- ===== 1. Le rôle dans l'annuaire =====
-- PostgreSQL n'autorise pas CREATE OR REPLACE à changer les colonnes d'une
-- fonction RETURNS TABLE : il faut la supprimer d'abord (comme en phase29).
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
  phone         text,
  role          text
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
           p.phone, p.role
    from public.profiles p
    where p.status = 'approved' and p.is_active
    order by p.last_name nulls last, p.full_name
    limit least(coalesce(p_limit, 300), 500);
end;
$$;

grant execute on function public.member_directory(int) to authenticated;

-- ===== 2. Purge des photos mortes =====
update public.profiles
   set photo_url = null
 where photo_url is not null
   and photo_url not like 'https://api.amstc.org/%';
