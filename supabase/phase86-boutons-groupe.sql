-- ============================================================
-- PHASE 86 - Boutons Telegram partagés entre administrateurs :
-- qui a cliqué est journalisé
--
-- LE BESOIN. Les notifications et leurs boutons vont être déplacés vers
-- un GROUPE Telegram réunissant plusieurs administrateurs. Or
-- action_telegram (phase 84) exécute l'action sous l'identité de
-- l'administrateur par défaut - le premier super-administrateur actif.
-- Le journal d'administration attribuerait donc chaque clic à cette
-- même personne, quel que soit celui des membres du groupe qui a
-- réellement approuvé ou refusé. Dans un groupe, c'est inacceptable :
-- une décision doit avoir un auteur.
--
-- CE QUI CHANGE. action_telegram accepte désormais le NOM TELEGRAM du
-- cliqueur (prénom, nom, identifiant @). Chaque action laisse une entrée
-- de journal dédiée, « action_telegram », dont les détails portent :
--   - qui : le nom Telegram, tel que transmis par Telegram lui-même
--   - quoi : l'action (ins:ok, val:no…) et son résultat
--   - sur qui : la cible
--
-- POURQUOI LE NOM TELEGRAM ET PAS UN COMPTE DU SITE. Il n'existe aucun
-- lien fiable entre un utilisateur Telegram et une fiche membre du
-- côté administration - le rattachement de la phase 85 est volontaire
-- et concerne les membres. Le nom Telegram est ce que l'on a de plus
-- sûr : il vient de Telegram, pas d'une saisie, et il ne peut pas être
-- falsifié par celui qui clique.
--
-- L'ANCIEN APPEL RESTE VALABLE : sans nom, l'entrée dit « (inconnu) ».
-- Une fonction Edge pas encore redéployée n'est pas cassée.
--
-- Le nom est fabriqué côté fonction Edge à partir des champs que
-- Telegram fournit dans callback_query.from ; il arrive ici comme un
-- simple texte, échappé à l'affichage par l'écran du journal.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

drop function if exists public.action_telegram(text, uuid);

create or replace function public.action_telegram(
  p_action text,
  p_id uuid,
  p_qui text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin    uuid;
  v_nom      text;
  v_resultat text;
  v_qui      text := nullif(btrim(coalesce(p_qui, '')), '');
begin
  select id into v_admin
    from public.profiles
   where role in ('admin', 'super_admin')
     and coalesce(is_active, true) is true
   order by case when role = 'super_admin' then 0 else 1 end, created_at
   limit 1;

  if v_admin is null then
    return 'Aucun administrateur actif : action impossible.';
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_admin::text)::text, true);

  case p_action
    when 'ins:ok' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'approved');
      v_resultat := 'Inscription approuvée : ' || coalesce(v_nom, '');

    when 'ins:no' then
      select full_name into v_nom from public.profiles where id = p_id;
      if v_nom is null then return 'Ce compte n''existe plus.'; end if;
      perform public.approve_or_reject_user(p_id, 'rejected');
      v_resultat := 'Inscription refusée : ' || coalesce(v_nom, '');

    when 'val:ok' then
      if not exists (select 1 from public.card_validity_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      select p.full_name into v_nom
        from public.card_validity_payments v join public.profiles p on p.id = v.user_id
       where v.id = p_id;
      perform public.confirm_card_validity_payment(p_id);
      v_resultat := 'Paiement de validité confirmé.';

    when 'val:no' then
      select p.full_name into v_nom
        from public.card_validity_payments v join public.profiles p on p.id = v.user_id
       where v.id = p_id;
      update public.card_validity_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      v_resultat := 'Paiement de validité refusé.';

    when 'cot:ok' then
      if not exists (select 1 from public.cotisation_payments
                      where id = p_id and status = 'pending') then
        return 'Ce paiement a déjà été traité.';
      end if;
      select p.full_name into v_nom
        from public.cotisation_payments c join public.profiles p on p.id = c.user_id
       where c.id = p_id;
      perform public.confirm_cotisation_payment(p_id);
      v_resultat := 'Paiement de cotisation confirmé.';

    when 'cot:no' then
      select p.full_name into v_nom
        from public.cotisation_payments c join public.profiles p on p.id = c.user_id
       where c.id = p_id;
      update public.cotisation_payments
         set status = 'rejected'
       where id = p_id and status = 'pending';
      if not found then return 'Ce paiement a déjà été traité.'; end if;
      v_resultat := 'Paiement de cotisation refusé.';

    else
      return 'Action inconnue : ' || coalesce(p_action, '(vide)');
  end case;

  -- L'entrée dédiée : QUI a cliqué, sur QUOI, avec quel RÉSULTAT. Elle
  -- s'ajoute à celle que l'action elle-même a pu produire (approbation,
  -- confirmation), attribuée à l'administrateur par défaut - c'est
  -- celle-ci qui porte l'auteur réel.
  begin
    perform public.journaliser('action_telegram', p_id, coalesce(v_nom, '(sans nom)'),
      jsonb_build_object(
        'qui', coalesce(v_qui, '(inconnu)'),
        'action', p_action,
        'resultat', v_resultat,
        'canal', 'telegram'));
  exception when others then
    -- Le journal ne doit jamais faire échouer l'action : elle est déjà
    -- faite. On préfère une entrée manquante à un bouton qui dit
    -- « échec » alors que l'inscription est approuvée.
    raise warning 'action_telegram : journalisation échouée : %', sqlerrm;
  end;

  return v_resultat;

exception when others then
  return 'Échec : ' || sqlerrm;
end;
$$;

revoke all on function public.action_telegram(text, uuid, text) from public, anon, authenticated;
grant execute on function public.action_telegram(text, uuid, text) to service_role;

notify pgrst, 'reload schema';

-- ===== Contrôle : les dernières actions par Telegram, avec leur auteur =====
select a.cree_le,
       a.details->>'qui'      as qui_a_clique,
       a.details->>'action'   as action,
       a.cible_nom            as sur_qui,
       a.details->>'resultat' as resultat
  from public.audit_log a
 where a.action = 'action_telegram'
 order by a.cree_le desc
 limit 20;
