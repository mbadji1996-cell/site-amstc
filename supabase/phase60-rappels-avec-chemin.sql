-- ============================================================
-- PHASE 60 - Les rappels indiquent le chemin à suivre (remplace la
-- composition de texte de phase57)
--
-- Les messages disaient quoi faire (« renouvelez votre carte ») sans dire
-- OÙ : ni adresse, ni parcours dans le site. Le membre devait chercher.
--
-- Chaque rappel se termine désormais par le chemin exact et un lien qui
-- ouvre directement la bonne section : la fiche profil accepte
-- ?open=validity et ?open=cotis, qui déplient et font défiler jusqu'à la
-- section voulue.
--
-- Le chemin est écrit DANS le corps du message : il part ainsi à
-- l'identique par e-mail et par WhatsApp, sans dépendre du canal.
--
-- PRÉREQUIS : phase57. Ce script remplace texte_rappel_membre et
-- envoyer_rappel_membre ; rien d'autre à modifier.
--
-- La fonction Edge notify-membre doit être redéployée après ce script :
-- le bouton de l'e-mail pointe désormais vers la section concernée.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- Ancienne signature (2 colonnes) : à supprimer avant de recréer, le type
-- de retour d'une fonction ne pouvant pas changer par CREATE OR REPLACE.
drop function if exists public.texte_rappel_membre(uuid, text, text);

create or replace function public.texte_rappel_membre(
  p_user_id uuid, p_type text, p_message text default null
)
returns table (titre text, corps text, lien text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m record;
  v_annee int := extract(year from now())::int;
  v_site text := 'https://amstc.org';
  v_titre text;
  v_corps text;
  v_lien text;
  v_chemin text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select p.first_name, p.full_name, p.card_valid_until, p.legacy_card_number
    into v_m
    from public.profiles p
   where p.id = p_user_id;

  if v_m is null then
    raise exception 'Membre introuvable.';
  end if;

  if p_type = 'carte_expiree' then
    v_titre := 'Votre carte de membre AMSTC a expiré';
    v_corps := 'Votre carte de membre '
      || coalesce('(' || v_m.legacy_card_number || ') ', '')
      || case when v_m.card_valid_until is null
              then 'n''a pas encore été réglée.'
              else 'a expiré à la fin de l''année ' || v_m.card_valid_until || '.' end
      || chr(10) || chr(10)
      || 'Merci de la renouveler pour continuer à bénéficier de l''accès aux contenus réservés.';
    v_lien := v_site || '/membres/profil.html?open=validity';
    v_chemin := 'Espace membres > Mon Profil & Adhésion > Validité de la carte';

  elsif p_type = 'carte_expire_bientot' then
    v_titre := 'Votre carte de membre expire fin ' || coalesce(v_m.card_valid_until, v_annee);
    v_corps := 'Votre carte de membre est valable jusqu''à la fin de l''année '
      || coalesce(v_m.card_valid_until, v_annee) || '.'
      || chr(10) || chr(10)
      || 'Pensez à la renouveler pour ne pas interrompre votre accès.';
    v_lien := v_site || '/membres/profil.html?open=validity';
    v_chemin := 'Espace membres > Mon Profil & Adhésion > Validité de la carte';

  elsif p_type = 'cotisation_retard' then
    v_titre := 'Cotisations mensuelles AMSTC';
    v_corps := 'Vos cotisations mensuelles de l''année ' || v_annee || ' ne sont pas à jour.'
      || chr(10) || chr(10)
      || 'Vous pouvez les régler à tout moment par Wave ou Orange Money, puis déclarer '
      || 'la référence de la transaction.';
    v_lien := v_site || '/membres/profil.html?open=cotis';
    v_chemin := 'Espace membres > Mon Profil & Adhésion > Cotisations mensuelles';

  elsif p_type = 'libre' then
    if btrim(coalesce(p_message, '')) = '' then
      raise exception 'Le message est vide.';
    end if;
    v_titre := 'Message de l''AMSTC';
    v_corps := btrim(p_message);
    v_lien := v_site || '/membres/connexion.html';
    v_chemin := 'Espace membres';

  else
    raise exception 'Type de rappel inconnu : %', p_type;
  end if;

  -- Le chemin fait partie du corps : il part ainsi à l'identique par
  -- e-mail et par WhatsApp, et un membre qui lit le message sur son
  -- téléphone n'a plus à chercher où aller.
  v_corps := v_corps || chr(10) || chr(10)
    || 'Où aller : ' || v_chemin || chr(10) || v_lien;

  return query select v_titre, v_corps, v_lien;
end;
$$;

-- Transmet aussi le lien : le bouton de l'e-mail ouvre la bonne section
-- au lieu de la seule page de connexion.
create or replace function public.envoyer_rappel_membre(
  p_user_id uuid, p_type text, p_message text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_texte record;
  v_m record;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  select * into v_texte from public.texte_rappel_membre(p_user_id, p_type, p_message);

  select email, full_name, first_name into v_m
    from public.profiles where id = p_user_id;

  if coalesce(btrim(v_m.email), '') = '' then
    raise exception 'Ce membre n''a pas d''adresse e-mail : utilisez WhatsApp.';
  end if;

  perform public.notify_membre('rappel_admin', jsonb_build_object(
    'email', v_m.email,
    'full_name', v_m.full_name,
    'first_name', v_m.first_name,
    'titre', v_texte.titre,
    'corps', v_texte.corps,
    'lien', v_texte.lien
  ));

  perform public.journaliser('rappel_envoye', p_user_id,
    coalesce(v_m.full_name, v_m.email, '(sans nom)'),
    jsonb_build_object('type', p_type, 'canal', 'email', 'titre', v_texte.titre));
end;
$$;

revoke all on function public.texte_rappel_membre(uuid, text, text) from public, anon;
revoke all on function public.envoyer_rappel_membre(uuid, text, text) from public, anon;
grant execute on function public.texte_rappel_membre(uuid, text, text) to authenticated;
grant execute on function public.envoyer_rappel_membre(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : le corps doit se terminer par « Où aller : … » suivi du lien.
select proname from pg_proc
 where proname in ('texte_rappel_membre','envoyer_rappel_membre')
 order by proname;
