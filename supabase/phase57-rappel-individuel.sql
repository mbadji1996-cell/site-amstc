-- ============================================================
-- PHASE 57 - Prévenir un membre en particulier, d'un clic
--
-- La diffusion WhatsApp (phase30/31) s'adresse à une audience entière.
-- Il manquait le geste inverse : depuis la fiche d'un membre, lui envoyer
-- un rappel qui le concerne, lui seul - cotisation en retard, carte
-- expirée, ou un mot libre.
--
-- Le texte est composé ICI, pas dans la fonction Edge : ajouter un type
-- de rappel plus tard ne demandera qu'un passage dans le SQL Editor,
-- jamais un redéploiement de fonction.
--
-- PRÉREQUIS : phase50 (notify_membre + fonction Edge notify-membre) et
-- phase51 (journal). La fonction Edge doit être redéployée après cette
-- phase : elle gagne le type de message « rappel_admin ».
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- Compose le titre et le corps d'un rappel pour un membre donné.
-- Renvoyée aussi au navigateur, qui s'en sert pour pré-remplir WhatsApp :
-- les deux canaux disent ainsi exactement la même chose.
create or replace function public.texte_rappel_membre(
  p_user_id uuid, p_type text, p_message text default null
)
returns table (titre text, corps text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m record;
  v_annee int := extract(year from now())::int;
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
    return query select
      'Votre carte de membre AMSTC a expiré'::text,
      ('Votre carte de membre '
        || coalesce('(' || v_m.legacy_card_number || ') ', '')
        || case when v_m.card_valid_until is null
                then 'n''a pas encore été réglée.'
                else 'a expiré à la fin de l''année ' || v_m.card_valid_until || '.' end
        || chr(10) || chr(10)
        || 'Merci de la renouveler depuis votre espace membres pour continuer à '
        || 'bénéficier de l''accès aux contenus réservés.')::text;

  elsif p_type = 'carte_expire_bientot' then
    return query select
      ('Votre carte de membre expire fin ' || coalesce(v_m.card_valid_until, v_annee))::text,
      ('Votre carte de membre est valable jusqu''à la fin de l''année '
        || coalesce(v_m.card_valid_until, v_annee) || '.'
        || chr(10) || chr(10)
        || 'Pensez à la renouveler pour ne pas interrompre votre accès.')::text;

  elsif p_type = 'cotisation_retard' then
    return query select
      'Cotisations mensuelles AMSTC'::text,
      ('Vos cotisations mensuelles de l''année ' || v_annee
        || ' ne sont pas à jour.'
        || chr(10) || chr(10)
        || 'Vous pouvez les régler à tout moment depuis votre espace membres, '
        || 'par Wave ou Orange Money.')::text;

  elsif p_type = 'libre' then
    if btrim(coalesce(p_message, '')) = '' then
      raise exception 'Le message est vide.';
    end if;
    return query select 'Message de l''AMSTC'::text, btrim(p_message)::text;

  else
    raise exception 'Type de rappel inconnu : %', p_type;
  end if;
end;
$$;

-- Envoie le rappel par e-mail et le trace dans le journal.
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
    'corps', v_texte.corps
  ));

  perform public.journaliser('rappel_envoye', p_user_id,
    coalesce(v_m.full_name, v_m.email, '(sans nom)'),
    jsonb_build_object('type', p_type, 'canal', 'email', 'titre', v_texte.titre));
end;
$$;

-- Trace un rappel transmis par WhatsApp. L'envoi lui-même se fait dans
-- l'application WhatsApp de l'administrateur (lien pré-rempli) : le
-- serveur ne peut pas le constater, on enregistre donc l'intention au
-- moment où le lien est ouvert.
create or replace function public.tracer_rappel_whatsapp(p_user_id uuid, p_type text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text;
begin
  if not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;
  select full_name into v_nom from public.profiles where id = p_user_id;
  perform public.journaliser('rappel_envoye', p_user_id, coalesce(v_nom, '(sans nom)'),
    jsonb_build_object('type', p_type, 'canal', 'whatsapp'));
end;
$$;

revoke all on function public.texte_rappel_membre(uuid, text, text) from public, anon;
revoke all on function public.envoyer_rappel_membre(uuid, text, text) from public, anon;
revoke all on function public.tracer_rappel_whatsapp(uuid, text) from public, anon;

grant execute on function public.texte_rappel_membre(uuid, text, text) to authenticated;
grant execute on function public.envoyer_rappel_membre(uuid, text, text) to authenticated;
grant execute on function public.tracer_rappel_whatsapp(uuid, text) to authenticated;

notify pgrst, 'reload schema';

-- Contrôle : les trois fonctions doivent apparaître.
select proname from pg_proc
 where proname in ('texte_rappel_membre','envoyer_rappel_membre','tracer_rappel_whatsapp')
 order by proname;
