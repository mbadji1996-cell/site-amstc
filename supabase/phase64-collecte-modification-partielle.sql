-- ============================================================
-- PHASE 64 - Modifier une collecte sans rien détruire.
--
-- Deux corrections liées, l'une réparant un bug, l'autre rendant
-- possible l'écran de modification (membres/collectes-admin.html).
--
-- 1. BUG : modifier_collecte (phase55) traitait ses paramètres de deux
--    façons opposées. titre et is_open étaient préservés quand on
--    passait NULL ; description et date_limite étaient écrasés. Or son
--    seul appelant était le bouton « Clôturer » / « Rouvrir », qui
--    n'envoie que l'identifiant et is_open - donc NULL partout ailleurs.
--    Chaque clôture ou réouverture détruisait ainsi la description et
--    l'échéance de la collecte, sans erreur ni message.
--
-- 2. Règle uniforme désormais : NULL = ne pas toucher. Une chaîne vide
--    efface la description. Une date ne permettant pas de distinguer
--    « ne touche pas » de « efface » avec un seul paramètre, un
--    p_effacer_date explicite s'en charge.
--
-- Le DROP est obligatoire : ajouter un paramètre, même avec valeur par
-- défaut, créerait une seconde fonction au lieu de remplacer la
-- première, et un appel à six arguments deviendrait ambigu.
--
-- ATTENTION : ce script répare la fonction, pas les données déjà
-- perdues. Le dernier select liste les collectes sans description.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

drop function if exists public.modifier_collecte(uuid, text, text, int, date, boolean);

create or replace function public.modifier_collecte(
  p_id uuid,
  p_titre text default null,
  p_description text default null,
  p_montant_fcfa int default null,
  p_date_limite date default null,
  p_is_open boolean default null,
  p_effacer_date boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if not exists (select 1 from public.collectes where id = p_id) then
    raise exception 'Collecte introuvable.';
  end if;

  update public.collectes
     set titre        = coalesce(nullif(btrim(coalesce(p_titre, '')), ''), titre),
         -- NULL laisse la description en place ; une chaîne vide l'efface.
         description  = case
                          when p_description is null then description
                          else nullif(btrim(p_description), '')
                        end,
         montant_fcfa = case when type = 'cotisation' then coalesce(p_montant_fcfa, montant_fcfa) else null end,
         -- Effacer une échéance se demande explicitement : sans ce
         -- drapeau, le NULL du bouton « Clôturer » la supprimerait.
         date_limite  = case
                          when p_effacer_date then null
                          else coalesce(p_date_limite, date_limite)
                        end,
         is_open      = coalesce(p_is_open, is_open)
   where id = p_id;
end;
$$;

revoke all on function public.modifier_collecte(uuid, text, text, int, date, boolean, boolean) from public, anon;
grant execute on function public.modifier_collecte(uuid, text, text, int, date, boolean, boolean) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : les collectes dont la description a peut-être été perdue.
-- Une collecte déjà clôturée puis réouverte est la première suspecte.
select id, titre, type, is_open, date_limite,
       case when description is null then 'DESCRIPTION VIDE' else 'ok' end as etat
  from public.collectes
 order by created_at desc;
