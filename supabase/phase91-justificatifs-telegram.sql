-- ============================================================
-- PHASE 91 - Le justificatif de paiement arrive par le bot
--
-- LE GESTE QU'ON RÉPÈTE. Le membre paie par Wave ou Orange Money, prend
-- la capture d'écran de la transaction, et l'envoie sur WhatsApp. Il
-- fallait ensuite la retrouver dans la conversation, l'ouvrir, la
-- rapprocher de la déclaration faite sur le site, et confirmer.
--
-- CE QUI CHANGE. Le membre qui a rattaché son Telegram envoie sa capture
-- AU BOT. Elle arrive aussitôt dans le salon d'administration, sous le
-- nom du membre, avec l'état de son dossier - et, S'IL A DÉJÀ DÉCLARÉ
-- SON PAIEMENT SUR LE SITE, les boutons Confirmer et Refuser de cette
-- déclaration précise. Le rapprochement est fait d'avance.
--
-- CE QUE LE BOT NE FAIT PAS : décider. Une capture d'écran n'est pas une
-- preuve vérifiée, et le montant qu'elle porte n'est pas forcément celui
-- qui a été déclaré. Le bot classe et présente ; c'est
-- l'administration qui confirme, comme avant.
--
-- OÙ VA L'IMAGE. Deux fois, et c'est voulu :
--   - dans le bucket privé « justificatifs », pour la conserver ;
--   - dans le salon d'administration, par son identifiant Telegram,
--     pour être vue tout de suite.
-- Si l'archivage échoue, le message part quand même : mieux vaut un
-- justificatif vu et non archivé qu'un justificatif perdu.
--
-- QUI PEUT ENVOYER. Seuls les membres RATTACHÉS (phase 85). Une photo
-- venant d'un Telegram inconnu reçoit l'explication du rattachement et
-- n'est ni archivée ni transmise : sans compte, elle ne se rapporterait
-- à rien.
--
-- PRÉREQUIS : phases 7, 85 et 90.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Le bucket, privé =====
insert into storage.buckets (id, name, public)
values ('justificatifs', 'justificatifs', false)
on conflict (id) do nothing;

-- Une capture d'écran de téléphone dépasse rarement 2 Mo ; 10 Mo laisse
-- de la marge sans ouvrir la porte à des envois de plusieurs dizaines.
update storage.buckets set file_size_limit = 10485760 where id = 'justificatifs';

-- Le dépôt se fait par le rôle de service, depuis la fonction Edge : les
-- membres n'écrivent JAMAIS directement dans ce bucket, et n'y lisent
-- rien. Seule l'administration consulte.
drop policy if exists "Admins can read justificatifs" on storage.objects;
create policy "Admins can read justificatifs"
  on storage.objects for select
  using (bucket_id = 'justificatifs' and public.is_admin());

drop policy if exists "Admins can delete justificatifs" on storage.objects;
create policy "Admins can delete justificatifs"
  on storage.objects for delete
  using (bucket_id = 'justificatifs' and public.is_admin());

-- ===== 2. Le registre =====
create table if not exists public.justificatifs_paiement (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  -- Le chemin dans le bucket. Null si l'archivage a échoué : le
  -- justificatif reste alors consultable par son file_id Telegram.
  chemin     text,
  -- L'identifiant Telegram de l'image, toujours renseigné. Il permet de
  -- la renvoyer dans un salon sans la retélécharger.
  file_id    text not null,
  legende    text,
  recu_le    timestamptz not null default now(),
  statut     text not null default 'recu'
             check (statut in ('recu', 'traite', 'ecarte')),
  traite_par text,
  traite_le  timestamptz
);

create index if not exists justificatifs_paiement_user_idx
  on public.justificatifs_paiement (user_id, recu_le desc);
create index if not exists justificatifs_paiement_statut_idx
  on public.justificatifs_paiement (statut) where statut = 'recu';

alter table public.justificatifs_paiement enable row level security;

-- Le membre voit les siens ; l'administration voit tout. La fonction
-- Edge, elle, passe par le rôle de service et n'est soumise à rien.
drop policy if exists "Members can read own justificatifs" on public.justificatifs_paiement;
create policy "Members can read own justificatifs"
  on public.justificatifs_paiement for select
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "Admins can manage justificatifs" on public.justificatifs_paiement;
create policy "Admins can manage justificatifs"
  on public.justificatifs_paiement for all
  using (public.is_admin());

-- ===== 3. Enregistrer un justificatif reçu =====
-- Renvoie de quoi bâtir le message d'administration : qui, son dossier,
-- et LES DÉCLARATIONS EN ATTENTE de ce membre - c'est ce rapprochement
-- qui fait tout l'intérêt du dispositif.
create or replace function public.enregistrer_justificatif(
  p_chat_id bigint,
  p_file_id text,
  p_chemin  text default null,
  p_legende text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p       public.profiles%rowtype;
  v_id      uuid;
  v_attente jsonb;
begin
  select * into v_p from public.profiles where telegram_chat_id = p_chat_id;
  if v_p.id is null then
    return jsonb_build_object('ok', false,
      'motif', 'Votre Telegram n''est rattaché à aucun compte AMSTC. '
            || 'Connectez-vous sur amstc.org, onglet « Carte de membre et Cotisations », '
            || 'et touchez « Recevoir mes rappels sur Telegram ». '
            || 'Votre justificatif n''a pas été enregistré.');
  end if;
  if coalesce(p_file_id, '') = '' then
    return jsonb_build_object('ok', false, 'motif', 'Image illisible : réessayez.');
  end if;

  insert into public.justificatifs_paiement (user_id, chemin, file_id, legende)
    values (v_p.id, nullif(btrim(coalesce(p_chemin, '')), ''), p_file_id,
            nullif(btrim(coalesce(p_legende, '')), ''))
    returning id into v_id;

  -- Les déclarations que ce membre a faites sur le site et qui attendent
  -- encore. Les deux types sont réunis, les plus récentes d'abord, et
  -- limitées à trois : au-delà, les boutons deviennent illisibles et
  -- c'est l'écran de vérification qu'il faut ouvrir.
  select jsonb_agg(jsonb_build_object('code', code, 'id', ligne_id, 'libelle', libelle)
                   order by le desc)
    into v_attente
    from (
      select 'val' as code, v.id as ligne_id, v.created_at as le,
             'Validité ' || v.years_requested || ' an(s) - '
             || v.amount_fcfa || ' F - réf. ' || v.payment_reference as libelle
        from public.card_validity_payments v
       where v.user_id = v_p.id and v.status = 'pending'
      union all
      select 'cot', c.id, c.created_at,
             'Cotisations ' || c.months_requested || ' mois ' || c.year || ' - '
             || c.amount_fcfa || ' F - réf. ' || c.payment_reference
        from public.cotisation_payments c
       where c.user_id = v_p.id and c.status = 'pending'
      -- Par position : « le » n'est pas nommé dans la seconde branche.
      order by 3 desc
      limit 3
    ) t;

  return jsonb_build_object(
    'ok', true,
    'justificatif_id', v_id,
    'user_id', v_p.id,
    'nom', coalesce(v_p.full_name, v_p.email, '(sans nom)'),
    'prenom', coalesce(v_p.first_name, v_p.full_name, ''),
    'fiche', public.fiche_membre_telegram(v_p.id),
    'archive', p_chemin is not null,
    'attente', coalesce(v_attente, '[]'::jsonb));
end;
$$;

revoke all on function public.enregistrer_justificatif(bigint, text, text, text)
  from public, anon, authenticated;
grant execute on function public.enregistrer_justificatif(bigint, text, text, text)
  to service_role;

-- ===== 4. Classer un justificatif =====
-- « traité » quand il a servi, « écarté » quand il ne correspond à rien.
-- Dans les deux cas il reste en base : un justificatif effacé, c'est une
-- contestation qu'on ne peut plus trancher.
create or replace function public.statuer_justificatif(
  p_id uuid, p_statut text, p_qui text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.justificatifs_paiement%rowtype;
begin
  if p_statut not in ('traite', 'ecarte') then
    return 'Statut inconnu.';
  end if;

  select * into v_j from public.justificatifs_paiement where id = p_id for update;
  if v_j.id is null then return 'Ce justificatif est introuvable.'; end if;
  if v_j.statut <> 'recu' then
    return 'Déjà classé (' || v_j.statut || ') le ' || to_char(v_j.traite_le, 'DD/MM à HH24:MI') || '.';
  end if;

  update public.justificatifs_paiement
     set statut = p_statut, traite_par = nullif(btrim(coalesce(p_qui, '')), ''), traite_le = now()
   where id = p_id;

  begin
    perform public.journaliser('justificatif_' || p_statut, v_j.user_id,
      (select coalesce(full_name, email, '(sans nom)') from public.profiles where id = v_j.user_id),
      jsonb_build_object('justificatif', p_id, 'qui', coalesce(p_qui, '(inconnu)')));
  exception when others then null;
  end;

  return case p_statut when 'traite' then 'Justificatif classé : traité.'
                       else 'Justificatif écarté.' end;
end;
$$;

revoke all on function public.statuer_justificatif(uuid, text, text) from public, anon, authenticated;
grant execute on function public.statuer_justificatif(uuid, text, text) to service_role;

-- ===== 5. Les justificatifs non classés, pour le rapport =====
-- Ajouté au point du jour et à la relance des dossiers oubliés : un
-- justificatif reçu et jamais regardé est exactement ce que ces deux
-- rapports existent pour éviter.
create or replace function public.rapport_matinal(p_toujours boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lignes jsonb := '[]'::jsonb;
  v_total  int := 0;
  v_n      int;
begin
  select count(*) into v_n from public.profiles where status = 'pending';
  v_lignes := v_lignes || jsonb_build_object('libelle', 'inscription(s) en attente', 'nombre', v_n);
  v_total := v_total + v_n;

  if to_regclass('public.card_validity_payments') is not null then
    select count(*) into v_n from public.card_validity_payments where status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de validité à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  if to_regclass('public.cotisation_payments') is not null then
    select count(*) into v_n from public.cotisation_payments where status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'paiement(s) de cotisation à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- NOUVEAU : les justificatifs reçus par le bot et non classés.
  if to_regclass('public.justificatifs_paiement') is not null then
    select count(*) into v_n from public.justificatifs_paiement where statut = 'recu';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'justificatif(s) reçu(s) non classé(s)', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  if to_regclass('public.collecte_participations') is not null then
    select count(*) into v_n from public.collecte_participations where status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'participation(s) à une collecte à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  if to_regclass('public.orders') is not null then
    select count(*) into v_n from public.orders
     where status in ('pending', 'paid', 'processing');
    v_lignes := v_lignes || jsonb_build_object('libelle', 'commande(s) boutique à traiter', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  if to_regclass('public.member_cards') is not null then
    select count(*) into v_n from public.member_cards where claim_status = 'pending';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'réclamation(s) de carte à confirmer', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  if to_regclass('public.campaign_requests') is not null then
    select count(*) into v_n from public.campaign_requests where status = 'en_attente';
    v_lignes := v_lignes || jsonb_build_object('libelle', 'demande(s) de campagne à étudier', 'nombre', v_n);
    v_total := v_total + v_n;
  end if;

  -- Doublons probables parmi les inscriptions en attente (phase 78).
  -- Le bloc est protégé : la fonction filtre sur is_admin(), or le cron
  -- s'exécute sans utilisateur connecté. On refait donc le calcul ici.
  if to_regproc('public.nom_cle') is not null then
    select count(distinct a.id) into v_n
      from public.profiles a
      join public.profiles e
        on e.id <> a.id and e.status <> 'pending'
       and (
         (public.telephone_cle(a.phone) is not null
          and length(public.telephone_cle(a.phone)) >= 9
          and public.telephone_cle(a.phone) = public.telephone_cle(e.phone))
         or
         (public.nom_cle(a.full_name) is not null
          and length(public.nom_cle(a.full_name)) >= 5
          and public.nom_cle(a.full_name) = public.nom_cle(e.full_name))
       )
     where a.status = 'pending';
    if v_n > 0 then
      v_lignes := v_lignes || jsonb_build_object(
        'libelle', 'inscription(s) en attente ressemblant à un compte existant', 'nombre', v_n);
      -- PAS compté dans le total : ces inscriptions figurent déjà dans
      -- le premier compteur, les additionner gonflerait le bilan.
    end if;
  end if;

  if v_total = 0 and not p_toujours then
    return jsonb_build_object('envoye', false, 'total', 0, 'lignes', v_lignes);
  end if;

  begin
    perform public.notify_admin('rapport_matinal', jsonb_build_object('lignes', v_lignes));
  exception when others then
    raise warning 'rapport_matinal : envoi échoué : %', sqlerrm;
    return jsonb_build_object('envoye', false, 'erreur', sqlerrm, 'lignes', v_lignes);
  end;

  return jsonb_build_object('envoye', true, 'total', v_total, 'lignes', v_lignes);
end;
$$;

revoke all on function public.rapport_matinal(boolean) from public, anon;
grant execute on function public.rapport_matinal(boolean) to authenticated;

notify pgrst, 'reload schema';

-- ===== 6. Contrôles =====
-- a) Le bucket et les fonctions.
select id, public, file_size_limit from storage.buckets where id = 'justificatifs';
select proname from pg_proc
 where proname in ('enregistrer_justificatif', 'statuer_justificatif')
 order by proname;

-- b) L'état du registre.
select statut, count(*) from public.justificatifs_paiement group by statut order by statut;

-- c) Le point du jour porte désormais la ligne des justificatifs.
select jsonb_pretty(public.rapport_matinal(true));
