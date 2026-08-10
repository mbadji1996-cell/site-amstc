-- ============================================================
-- PHASE 65 - Un rappel de plus : « Compte activé, connectez-vous »
--
-- Après la validation d'un compte, rien n'invitait le membre à venir
-- s'en servir. L'e-mail d'approbation part une fois, au moment de la
-- validation ; passé ce jour-là, l'administration n'avait aucun moyen de
-- relancer quelqu'un qui n'était jamais venu - sinon en écrivant le
-- message à la main.
--
-- Ce script ajoute le type « compte_active » aux rappels individuels de
-- membres/validation.html, à côté de carte_expiree, carte_expire_bientot,
-- cotisation_retard et libre. Comme les autres, il part indifféremment
-- par e-mail ou par WhatsApp, avec le chemin et le lien dans le corps.
--
-- PRÉREQUIS : phase57 puis phase60. Ce script remplace uniquement
-- texte_rappel_membre ; envoyer_rappel_membre est inchangée.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

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

  if p_type = 'compte_active' then
    v_titre := 'Votre compte AMSTC est activé';
    v_corps := 'Votre compte a été validé par l''administration : l''espace membres vous est désormais ouvert.'
      || chr(10) || chr(10)
      || 'Connectez-vous dès maintenant avec l''adresse e-mail de votre inscription. Vous y trouverez '
      || 'votre carte de membre, les formations, l''annuaire et les documents de l''association.'
      || chr(10) || chr(10)
      -- Un compte validé il y a plusieurs semaines a souvent perdu son
      -- mot de passe en route : le dire ici évite un aller-retour.
      || 'Si vous avez oublié votre mot de passe, utilisez « Mot de passe oublié ? » sur la page de connexion.';
    v_lien := v_site || '/membres/connexion.html';
    v_chemin := 'Espace membres > Se connecter';

  elsif p_type = 'carte_expiree' then
    v_titre := 'Votre carte de membre AMSTC a expiré';
    v_corps := 'Votre carte de membre '
      || coalesce('(' || v_m.legacy_card_number || ') ', '')
      || case when v_m.card_valid_until is null
              then 'n''a pas encore été réglée.'
              else 'a expiré à la fin de l''année ' || v_m.card_valid_until || '.' end
      || chr(10) || chr(10)
      || 'Merci de la renouveler pour continuer à bénéficier de l''accès aux contenus réservés.';
    v_lien := v_site || '/membres/profil.html?open=validity';
    v_chemin := 'Espace membres > Carte de membre et Cotisations > Validité de la carte';

  elsif p_type = 'carte_expire_bientot' then
    v_titre := 'Votre carte de membre expire fin ' || coalesce(v_m.card_valid_until, v_annee);
    v_corps := 'Votre carte de membre est valable jusqu''à la fin de l''année '
      || coalesce(v_m.card_valid_until, v_annee) || '.'
      || chr(10) || chr(10)
      || 'Pensez à la renouveler pour ne pas interrompre votre accès.';
    v_lien := v_site || '/membres/profil.html?open=validity';
    v_chemin := 'Espace membres > Carte de membre et Cotisations > Validité de la carte';

  elsif p_type = 'cotisation_retard' then
    v_titre := 'Cotisations mensuelles AMSTC';
    v_corps := 'Vos cotisations mensuelles de l''année ' || v_annee || ' ne sont pas à jour.'
      || chr(10) || chr(10)
      || 'Vous pouvez les régler à tout moment par Wave ou Orange Money, puis déclarer '
      || 'la référence de la transaction.';
    v_lien := v_site || '/membres/profil.html?open=cotis';
    v_chemin := 'Espace membres > Carte de membre et Cotisations > Cotisations mensuelles';

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

revoke all on function public.texte_rappel_membre(uuid, text, text) from public, anon;
grant execute on function public.texte_rappel_membre(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : le nouveau type doit produire un texte, les anciens aussi.
-- Remplacez l'identifiant par celui d'un membre approuvé de votre base.
--
--   select titre, corps
--     from public.texte_rappel_membre('00000000-0000-0000-0000-000000000000',
--                                     'compte_active');
