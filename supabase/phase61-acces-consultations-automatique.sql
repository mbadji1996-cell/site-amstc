-- ============================================================
-- PHASE 61 - L'accès à consultations-amstc.org devient automatique
--
-- Il fallait jusqu'ici cliquer « Créer l'accès consultations » sur chaque
-- membre : un geste facile à oublier, et le praticien découvrait qu'il
-- n'avait pas d'accès au moment d'en avoir besoin - souvent sur le
-- terrain, un jour de campagne.
--
-- L'accès est désormais créé dès l'approbation du compte, sans clic.
--
-- QUI EST CONCERNÉ. Uniquement les domaines de santé : médecine,
-- pharmacie, odontologie, soins infirmiers, soins obstétricaux.
-- consultations-amstc.org contient des données de santé de patients ;
-- y ouvrir un accès à un membre dont ce n'est pas le métier ne se
-- justifierait pas, et la restriction existait déjà côté fonction Edge.
-- Un membre au domaine « autre » n'obtient donc pas d'accès.
--
-- QUAND. À l'approbation, et aussi lorsqu'un membre déjà approuvé
-- renseigne enfin son domaine : un compte Google approuvé avant d'avoir
-- complété son profil serait sinon oublié pour toujours.
--
-- PRÉREQUIS : la fonction Edge provision-consultation-user doit être
-- redéployée AVANT ce script (elle accepte désormais l'appel du serveur),
-- et ses secrets CONSULT_SUPABASE_URL / CONSULT_SERVICE_ROLE_KEY doivent
-- être configurés.
--
-- Remplacez REMPLACEZ_PAR_VOTRE_JETON par le jeton de phase25, comme pour
-- les autres appels serveur.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create extension if not exists pg_net;

create or replace function public.provisionner_consultations(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://api.amstc.org/functions/v1/provision-consultation-user',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer REMPLACEZ_PAR_VOTRE_JETON'
    ),
    body := jsonb_build_object('member_id', p_user_id),
    timeout_milliseconds := 10000
  );
exception when others then
  -- Un souci réseau ne doit jamais empêcher l'approbation d'un membre :
  -- on journalise et on continue. Le bouton manuel reste disponible en
  -- secours dans la fiche du membre.
  raise warning 'provisionner_consultations(%) a échoué : %', p_user_id, sqlerrm;
end;
$$;

create or replace function public.trg_acces_consultations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eligible boolean;
  v_etait_eligible boolean;
begin
  v_eligible := new.status = 'approved'
    and new.is_active is not false
    and new.consultation_user_id is null
    and new.domain in ('medecine', 'pharmacie', 'odontologie',
                       'soins_infirmiers', 'soins_obstetricaux');

  if not v_eligible then
    return new;
  end if;

  -- Ne se déclenche qu'au moment où la situation CHANGE : sans cette
  -- comparaison, chaque enregistrement du profil d'un membre approuvé
  -- rappellerait la fonction Edge inutilement.
  v_etait_eligible := old.status = 'approved'
    and old.is_active is not false
    and old.consultation_user_id is null
    and old.domain is not distinct from new.domain;

  if not v_etait_eligible then
    perform public.provisionner_consultations(new.id);
    perform public.journaliser('acces_consultations_demande', new.id,
      coalesce(new.full_name, new.email, '(sans nom)'),
      jsonb_build_object('domaine', new.domain, 'declencheur', 'automatique'));
  end if;

  return new;
end;
$$;

drop trigger if exists acces_consultations on public.profiles;
create trigger acces_consultations
  after update of status, domain, is_active on public.profiles
  for each row
  execute function public.trg_acces_consultations();

-- ===== Rattrapage des membres déjà approuvés =====
-- Les soignants approuvés avant cette phase n'ont pas d'accès : on les
-- provisionne une fois, à l'exécution du script.
do $$
declare
  v_m record;
  v_n int := 0;
begin
  for v_m in
    select id, full_name from public.profiles
     where status = 'approved' and is_active is not false
       and consultation_user_id is null
       and domain in ('medecine', 'pharmacie', 'odontologie',
                      'soins_infirmiers', 'soins_obstetricaux')
  loop
    perform public.provisionner_consultations(v_m.id);
    v_n := v_n + 1;
  end loop;
  raise notice 'Accès consultations demandés pour % membre(s) déjà approuvé(s).', v_n;
end;
$$;

notify pgrst, 'reload schema';

-- Contrôle : à relancer après une minute, le temps que les appels
-- aboutissent. La colonne consultation_user_id doit se remplir.
select count(*) filter (where consultation_user_id is not null) as avec_acces,
       count(*) filter (where consultation_user_id is null)     as sans_acces
  from public.profiles
 where status = 'approved' and is_active is not false
   and domain in ('medecine', 'pharmacie', 'odontologie',
                  'soins_infirmiers', 'soins_obstetricaux');
