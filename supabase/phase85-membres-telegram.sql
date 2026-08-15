-- ============================================================
-- PHASE 85 - Telegram pour les MEMBRES : rattachement, consultation,
-- rappels de cotisation
--
-- WHATSAPP N'EST PAS TOUCHÉ. Rien de ce qui existe n'est modifié :
-- l'écran de diffusion WhatsApp, ses audiences et ses modèles Meta
-- continuent exactement comme avant. Telegram vient EN PLUS, pour les
-- membres qui l'auront rattaché - et c'est l'adoption réelle qui dira,
-- dans quelques mois, s'il peut prendre le relais.
--
-- LE PROBLÈME DU RATTACHEMENT. Un bot Telegram ne peut pas écrire le
-- premier : c'est le membre qui doit le démarrer. Et une fois qu'il l'a
-- fait, encore faut-il savoir QUI il est - Telegram ne transmet qu'un
-- identifiant de conversation, sans rapport avec le compte du site.
--
-- LA SOLUTION : un lien à usage unique. Depuis son profil, le membre
-- (donc déjà authentifié) demande un jeton ; le site l'emmène sur
-- t.me/amstc_notifs_bot?start=<jeton> ; en touchant « Démarrer », son
-- Telegram transmet ce jeton au bot, qui peut alors relier la
-- conversation au compte. Le jeton vaut 30 minutes et ne sert qu'une
-- fois : intercepté, il est déjà consommé ou périmé.
--
-- CE QUE LE MEMBRE POURRA FAIRE ensuite, en écrivant au bot :
--   « carte »       -> son numéro, sa validité
--   « cotisations » -> ses mois réglés cette année
--   « aide »        -> la liste
--
-- CE QUE LE BOT NE FERA JAMAIS : donner des informations sur QUELQU'UN
-- D'AUTRE. Toute réponse part de la conversation, jamais d'un nom saisi.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

alter table public.profiles
  add column if not exists telegram_chat_id bigint;

-- Une conversation ne peut appartenir qu'à UN membre : sans cela, deux
-- comptes rattachés au même Telegram recevraient chacun les
-- informations de l'autre.
create unique index if not exists profiles_telegram_chat_id_unique
  on public.profiles (telegram_chat_id)
  where telegram_chat_id is not null;

create table if not exists public.telegram_liaisons (
  jeton      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  cree_le    timestamptz not null default now(),
  expire_le  timestamptz not null default now() + interval '30 minutes',
  used_at    timestamptz
);

alter table public.telegram_liaisons enable row level security;
-- Aucune politique de lecture : seules les fonctions ci-dessous, en
-- security definer, y accèdent. Un membre n'a jamais besoin de lire
-- cette table - il reçoit son jeton en retour d'appel.

-- ===== 1. Le membre demande son lien =====
create or replace function public.creer_lien_telegram()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_jeton text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;

  -- Les jetons non consommés du membre sont annulés : un seul lien vaut
  -- à la fois, celui qu'il vient de demander.
  delete from public.telegram_liaisons
   where user_id = auth.uid() and used_at is null;

  -- Un UUID sans tirets : 32 caractères, 122 bits d'aléa - largement
  -- assez pour un jeton à usage unique valable 30 minutes, et sous la
  -- limite de 64 caractères que Telegram impose au paramètre « start ».
  --
  -- gen_random_uuid() est natif à PostgreSQL et donc toujours visible.
  -- gen_random_bytes() vient de pgcrypto et vit dans le schéma
  -- « extensions » : avec le search_path fixé à public - indispensable
  -- pour une fonction SECURITY DEFINER - il est introuvable. C'est
  -- exactement l'erreur rencontrée le 15/08/2026, et déjà consignée
  -- dans phase59.
  v_jeton := replace(gen_random_uuid()::text, '-', '');
  insert into public.telegram_liaisons (jeton, user_id) values (v_jeton, auth.uid());
  return v_jeton;
end;
$$;

revoke all on function public.creer_lien_telegram() from public, anon;
grant execute on function public.creer_lien_telegram() to authenticated;

-- ===== 2. Le bot consomme le lien =====
create or replace function public.lier_telegram(p_jeton text, p_chat_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_liaison public.telegram_liaisons%rowtype;
  v_nom     text;
begin
  select * into v_liaison
    from public.telegram_liaisons
   where jeton = p_jeton
   for update;

  if v_liaison.user_id is null then
    return 'Ce lien est inconnu. Demandez-en un nouveau depuis votre profil sur amstc.org.';
  end if;
  if v_liaison.used_at is not null then
    return 'Ce lien a déjà servi. Demandez-en un nouveau depuis votre profil.';
  end if;
  if now() > v_liaison.expire_le then
    return 'Ce lien a expiré (30 minutes). Demandez-en un nouveau depuis votre profil.';
  end if;

  -- La conversation était rattachée à un autre compte : on la détache,
  -- l'index unique refuserait sinon l'écriture. Cas réel du membre qui
  -- change de compte.
  update public.profiles set telegram_chat_id = null
   where telegram_chat_id = p_chat_id and id <> v_liaison.user_id;

  update public.profiles set telegram_chat_id = p_chat_id
   where id = v_liaison.user_id
   returning coalesce(first_name, full_name, '') into v_nom;

  update public.telegram_liaisons set used_at = now() where jeton = p_jeton;

  return 'Bonjour ' || coalesce(v_nom, '') || ' ! Votre compte AMSTC est rattaché. '
      || 'Écrivez « carte », « cotisations » ou « aide ».';
end;
$$;

revoke all on function public.lier_telegram(text, bigint) from public, anon, authenticated;
grant execute on function public.lier_telegram(text, bigint) to service_role;

-- ===== 3. Le membre se détache =====
create or replace function public.delier_telegram()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  update public.profiles set telegram_chat_id = null where id = auth.uid();
end;
$$;

revoke all on function public.delier_telegram() from public, anon;
grant execute on function public.delier_telegram() to authenticated;

-- ===== 4. Ce que le bot répond =====
-- La réponse est construite À PARTIR DE LA CONVERSATION, jamais d'un nom
-- saisi : impossible d'interroger le dossier de quelqu'un d'autre.
create or replace function public.infos_membre_telegram(p_chat_id bigint, p_quoi text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p      public.profiles%rowtype;
  v_annee  int := extract(year from now())::int;
  v_mois   int[];
  v_nb     int;
  v_libel  text;
begin
  select * into v_p from public.profiles where telegram_chat_id = p_chat_id;

  if v_p.id is null then
    return 'Votre Telegram n''est rattaché à aucun compte AMSTC. '
        || 'Connectez-vous sur amstc.org, onglet « Carte de membre et Cotisations », '
        || 'et touchez « Recevoir mes rappels sur Telegram ».';
  end if;

  if p_quoi = 'carte' then
    return 'Carte : ' || coalesce(v_p.legacy_card_number, 'non attribuée') || chr(10)
        || 'Membre depuis : ' || coalesce(v_p.member_since::text, '-') || chr(10)
        || 'Valide jusqu''au 31/12/' || coalesce(v_p.card_valid_until::text, '(non réglée)')
        || case when coalesce(v_p.card_valid_until, 0) < v_annee
                then chr(10) || 'Votre carte est expirée : renouvelez-la sur amstc.org.'
                else '' end;

  elsif p_quoi = 'cotisations' then
    select months_paid into v_mois
      from public.cotisations where user_id = v_p.id and year = v_annee;
    v_mois := coalesce(v_mois, '{}');
    v_nb := array_length(v_mois, 1);
    v_nb := coalesce(v_nb, 0);

    -- Noms des mois écrits en dur : to_char suit la locale de la session
    -- de base, anglaise sur cette instance - le membre recevait
    -- « January, February… ». Constaté au premier essai réel.
    select string_agg(
             (array['janvier','février','mars','avril','mai','juin','juillet',
                    'août','septembre','octobre','novembre','décembre'])[m],
             ', ' order by m)
      into v_libel from unnest(v_mois) m where m between 1 and 12;

    return 'Cotisations ' || v_annee || ' : ' || v_nb || '/12' || chr(10)
        || case when v_nb = 0 then 'Aucun mois réglé cette année.'
                else 'Réglés : ' || coalesce(v_libel, '') end
        || chr(10) || '1 000 F par mois - déclarez vos paiements sur amstc.org.';

  else
    return 'Bonjour ' || coalesce(v_p.first_name, v_p.full_name, '') || ' !' || chr(10)
        || 'Écrivez :' || chr(10)
        || '  carte - votre numéro et la validité' || chr(10)
        || '  cotisations - vos mois réglés' || chr(10)
        || 'Vous recevrez aussi les rappels de cotisation ici.';
  end if;
end;
$$;

revoke all on function public.infos_membre_telegram(bigint, text) from public, anon, authenticated;
grant execute on function public.infos_membre_telegram(bigint, text) to service_role;

-- ===== 5. Rappels de cotisation, aux membres rattachés =====
create table if not exists public.rappels_cotisation_envoyes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  annee   int not null,
  mois    int not null,
  envoye_le timestamptz not null default now(),
  primary key (user_id, annee, mois)
);

create or replace function public.envoyer_rappels_cotisations_telegram(
  p_mois int default null, p_annee int default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_m      int := coalesce(p_mois, extract(month from now())::int);
  v_a      int := coalesce(p_annee, extract(year from now())::int);
  v_membre record;
  v_n      int := 0;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  for v_membre in
    select p.id, p.telegram_chat_id, coalesce(p.first_name, p.full_name, '') as nom
      from public.profiles p
     where p.telegram_chat_id is not null
       and p.status = 'approved'
       and coalesce(p.is_active, true) is true
       -- Le mois n'est pas réglé
       and not exists (
         select 1 from public.cotisations c
          where c.user_id = p.id and c.year = v_a and v_m = any(c.months_paid))
       -- Et le rappel n'a pas déjà été envoyé
       and not exists (
         select 1 from public.rappels_cotisation_envoyes r
          where r.user_id = p.id and r.annee = v_a and r.mois = v_m)
  loop
    begin
      perform public.notify_admin('message_telegram', jsonb_build_object(
        'chat_id', v_membre.telegram_chat_id,
        'texte', 'Bonjour ' || v_membre.nom || ', votre cotisation de '
              || (array['janvier','février','mars','avril','mai','juin','juillet',
                        'août','septembre','octobre','novembre','décembre'])[v_m]
              || ' ' || v_a
              || ' (1 000 F) n''est pas encore enregistrée. '
              || 'Déclarez votre paiement sur amstc.org, onglet Carte de membre et Cotisations. Merci !'));
      insert into public.rappels_cotisation_envoyes (user_id, annee, mois)
        values (v_membre.id, v_a, v_m) on conflict do nothing;
      v_n := v_n + 1;
    exception when others then
      raise warning 'rappel cotisation à % : %', v_membre.id, sqlerrm;
    end;
  end loop;

  return v_n;
end;
$$;

revoke all on function public.envoyer_rappels_cotisations_telegram(int, int) from public, anon;
grant execute on function public.envoyer_rappels_cotisations_telegram(int, int) to authenticated;

-- ===== 6. Contrôles =====
select count(*) filter (where telegram_chat_id is not null) as membres_rattaches,
       count(*) as membres_total
  from public.profiles where status = 'approved';

-- Combien recevraient un rappel ce mois-ci, SANS rien envoyer.
select count(*) as rappels_a_envoyer
  from public.profiles p
 where p.telegram_chat_id is not null
   and p.status = 'approved'
   and coalesce(p.is_active, true) is true
   and not exists (select 1 from public.cotisations c
                    where c.user_id = p.id and c.year = extract(year from now())::int
                      and extract(month from now())::int = any(c.months_paid));
