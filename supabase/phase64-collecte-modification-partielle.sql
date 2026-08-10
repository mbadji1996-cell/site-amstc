-- ============================================================
-- PHASE 64 - Clôturer une collecte n'efface plus sa description ni sa
-- date limite.
--
-- modifier_collecte (phase55) traitait ses paramètres de façon
-- incohérente : titre et is_open étaient préservés quand on passait NULL
-- (« ne touche pas »), mais description et date_limite étaient écrasés
-- (« mets NULL »).
--
-- Or le seul appelant du site est le bouton « Clôturer » / « Rouvrir »
-- de membres/collectes-admin.html, qui n'envoie que l'identifiant et
-- is_open, et donc NULL partout ailleurs. Résultat : chaque clôture ou
-- réouverture détruisait silencieusement la description et l'échéance de
-- la collecte. Aucune erreur, aucun message - le texte disparaissait
-- simplement de la page des membres.
--
-- Nouvelle règle, uniforme sur les cinq champs : NULL = ne pas toucher.
-- Pour vider une description, passer une chaîne vide plutôt que NULL.
--
-- ATTENTION : ce script répare la fonction, pas les données déjà perdues.
-- Vérifiez les descriptions de vos collectes existantes après exécution.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create or replace function public.modifier_collecte(
  p_id uuid, p_titre text, p_description text,
  p_montant_fcfa int, p_date_limite date, p_is_open boolean
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

  update public.collectes
     set titre        = coalesce(nullif(btrim(coalesce(p_titre, '')), ''), titre),
         -- NULL laisse la description en place ; une chaîne vide l'efface.
         -- Sans cette distinction, le bouton « Clôturer » la détruisait.
         description  = case
                          when p_description is null then description
                          else nullif(btrim(p_description), '')
                        end,
         montant_fcfa = case when type = 'cotisation' then coalesce(p_montant_fcfa, montant_fcfa) else null end,
         -- Une date ne permet pas de distinguer « ne touche pas » de
         -- « efface » avec un seul paramètre : on retient « ne touche
         -- pas », le seul choix qui ne perde jamais de donnée. Retirer
         -- une échéance demandera un paramètre dédié le jour où un
         -- formulaire de modification existera.
         date_limite  = coalesce(p_date_limite, date_limite),
         is_open      = coalesce(p_is_open, is_open)
   where id = p_id;
end;
$$;

-- Contrôle : les collectes dont la description a peut-être été perdue.
-- Une collecte clôturée puis vidée de sa description est le symptôme.
select id, titre, type, is_open, date_limite,
       case when description is null then 'DESCRIPTION VIDE' else 'ok' end as etat
  from public.collectes
 order by created_at desc;
