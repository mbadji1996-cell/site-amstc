-- ============================================================
-- PHASE 104 - Boîte de réception WhatsApp
--
-- LE BESOIN. Depuis la phase du webhook, un membre qui écrit au numéro
-- de l'association est repris dans le salon Telegram, et
-- l'administrateur lui répond de là. Ça marche, mais rien n'est gardé :
-- le message traverse la fonction et disparaît. Impossible de relire un
-- échange d'il y a trois jours, de savoir qui a déjà répondu, ni de
-- travailler à plusieurs. C'est le rôle d'une boîte de réception, et il
-- lui faut d'abord une mémoire.
--
-- UNE SEULE TABLE, LES DEUX SENS. Entrants et sortants dans la même
-- table, distingués par « sens » : un fil de conversation est
-- exactement cette table filtrée sur un numéro et triée par date. Deux
-- tables auraient obligé à fusionner deux tris à chaque affichage.
--
-- LE NUMÉRO EST LA CLÉ, PAS LE MEMBRE. Beaucoup d'écrivants ne sont pas
-- (encore) des membres inscrits : quelqu'un du registre qui n'a jamais
-- réclamé sa carte, un parent, un inconnu. Rattacher la conversation à
-- un profil aurait perdu ces messages-là. Le profil est donc retrouvé À
-- LA LECTURE, par le téléphone normalisé (phase 78) - de sorte qu'une
-- inscription ultérieure rattache d'un coup tout l'historique passé.
--
-- CE QUI N'EST PAS ICI, DÉLIBÉRÉMENT. Aucune table « conversations » :
-- elle devrait être tenue à jour à chaque message, et divergerait tôt
-- ou tard des messages eux-mêmes. La liste des conversations est
-- calculée, pas stockée.
--
-- LES INSERTIONS VIENNENT DES FONCTIONS EDGE, en clé service_role, qui
-- contourne RLS - aucune policy d'écriture n'est donc nécessaire, et
-- c'est voulu : un administrateur ne doit pas pouvoir fabriquer un
-- message entrant.
--
-- PRÉREQUIS : phase 2 (is_admin), phase 78 (telephone_cle).
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

create table if not exists public.whatsapp_messages (
  id            uuid primary key default gen_random_uuid(),
  -- Chiffres seuls, format international sans « + » : « 221771234567 ».
  -- C'est la forme que Meta emploie, et celle que la fonction d'envoi
  -- attend - normaliser ici évite une conversion à chaque bout.
  telephone     text not null,
  sens          text not null check (sens in ('entrant', 'sortant')),
  texte         text not null default '',
  -- « text », « image », « audio »... Le contenu des médias n'est pas
  -- téléchargé : « texte » porte alors un résumé lisible.
  type_message  text not null default 'text',
  -- Identifiant Meta du message entrant. Meta RÉESSAIE un webhook qui
  -- n'a pas répondu 200 : sans cette clé unique, un même message
  -- apparaîtrait deux fois dans le fil.
  wa_message_id text,
  -- Le nom du profil WhatsApp, tel que le correspondant l'a choisi.
  -- Sert quand aucun membre ne correspond au numéro.
  nom_affiche   text,
  envoye_par    uuid references public.profiles(id) on delete set null,
  envoye_par_nom text,
  -- « telegram » ou « espace-membres » : les deux voies coexistent, et
  -- savoir d'où part une réponse aide à comprendre un échange.
  via           text,
  lu_le         timestamptz,
  cree_le       timestamptz not null default now()
);

-- Index NON partiel, à dessein : c'est la cible du « ON CONFLICT » que
-- le webhook emploie pour ignorer un doublon, et Postgres ne sait pas
-- viser un index partiel depuis PostgREST. Les sortants, qui n'ont pas
-- d'identifiant Meta, y entrent avec la valeur nulle - et deux valeurs
-- nulles ne sont pas considérées comme égales.
create unique index if not exists whatsapp_messages_wa_id
  on public.whatsapp_messages (wa_message_id);

create index if not exists whatsapp_messages_fil
  on public.whatsapp_messages (telephone, cree_le desc);

create index if not exists whatsapp_messages_non_lus
  on public.whatsapp_messages (telephone)
  where sens = 'entrant' and lu_le is null;

alter table public.whatsapp_messages enable row level security;

drop policy if exists "Admins can view whatsapp messages" on public.whatsapp_messages;
create policy "Admins can view whatsapp messages"
  on public.whatsapp_messages for select
  using (public.is_admin());

-- ============================================================
-- LA LISTE DES CONVERSATIONS
--
-- Une ligne par numéro : le dernier message, le nombre de non-lus, et
-- l'heure à laquelle la fenêtre de réponse libre se ferme. Cette
-- dernière colonne n'est pas un confort : passé 24 heures depuis le
-- dernier message du correspondant, Meta refuse toute réponse hors
-- modèle (erreur 131047). L'afficher évite d'écrire pour rien.
-- ============================================================
create or replace function public.whatsapp_conversations()
returns table(
  telephone       text,
  nom             text,
  est_membre      boolean,
  dernier_texte   text,
  dernier_sens    text,
  dernier_le      timestamptz,
  fenetre_jusqu_a timestamptz,
  non_lus         int,
  total           int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;

  return query
  with dernier as (
    select distinct on (m.telephone)
           m.telephone as tel, m.texte as txt, m.sens as sns, m.cree_le as le
      from public.whatsapp_messages m
     order by m.telephone, m.cree_le desc
  ),
  agrege as (
    select m.telephone as tel,
           max(m.cree_le) filter (where m.sens = 'entrant') as dernier_entrant,
           count(*) filter (where m.sens = 'entrant' and m.lu_le is null)::int as nb_non_lus,
           count(*)::int as nb_total,
           -- Le nom WhatsApp le plus récemment vu : un correspondant
           -- peut le changer, et l'ancien ne doit pas l'emporter.
           (array_agg(m.nom_affiche order by m.cree_le desc)
              filter (where m.nom_affiche is not null and m.nom_affiche <> ''))[1] as nom_wa
      from public.whatsapp_messages m
     group by m.telephone
  )
  select d.tel,
         coalesce(p.full_name, a.nom_wa, '+' || d.tel),
         (p.id is not null),
         d.txt, d.sns, d.le,
         a.dernier_entrant + interval '24 hours',
         a.nb_non_lus, a.nb_total
    from dernier d
    join agrege a on a.tel = d.tel
    -- Le rattachement au membre se fait ici, jamais à l'insertion :
    -- quelqu'un qui s'inscrit demain doit voir ses messages d'hier
    -- porter son nom.
    left join lateral (
      select pr.id, pr.full_name
        from public.profiles pr
       where public.telephone_cle(pr.phone) = public.telephone_cle(d.tel)
       order by pr.created_at asc
       limit 1
    ) p on true
   order by d.le desc;
end;
$$;

-- ============================================================
-- LE FIL D'UNE CONVERSATION
--
-- Les derniers messages d'un numéro, rendus dans l'ordre de lecture.
-- La limite porte sur les PLUS RÉCENTS, puis le tri est remis à
-- l'endroit : demander « les 200 derniers » et recevoir les 200
-- premiers serait exactement l'inverse du besoin.
-- ============================================================
create or replace function public.whatsapp_fil(
  p_telephone text,
  p_limite int default 300
)
returns table(
  id             uuid,
  sens           text,
  texte          text,
  type_message   text,
  envoye_par_nom text,
  via            text,
  cree_le        timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tel text := regexp_replace(coalesce(p_telephone, ''), '\D', '', 'g');
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;
  if v_tel = '' then
    return;
  end if;

  return query
  select t.id, t.sens, t.texte, t.type_message, t.envoye_par_nom, t.via, t.cree_le
    from (
      select m.*
        from public.whatsapp_messages m
       where m.telephone = v_tel
       order by m.cree_le desc
       limit greatest(1, least(coalesce(p_limite, 300), 1000))
    ) t
   order by t.cree_le asc;
end;
$$;

-- ============================================================
-- MARQUER UNE CONVERSATION COMME LUE
--
-- Rend le nombre de messages effectivement marqués, pour que l'appelant
-- sache s'il a changé quelque chose sans relire la liste entière.
-- ============================================================
create or replace function public.whatsapp_marquer_lu(p_telephone text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tel text := regexp_replace(coalesce(p_telephone, ''), '\D', '', 'g');
  v_nb int;
begin
  if not public.is_admin() then
    raise exception 'Réservé aux administrateurs';
  end if;
  if v_tel = '' then
    return 0;
  end if;

  update public.whatsapp_messages
     set lu_le = now()
   where telephone = v_tel
     and sens = 'entrant'
     and lu_le is null;

  get diagnostics v_nb = row_count;
  return v_nb;
end;
$$;

-- ============================================================
-- LE COMPTEUR DE NON-LUS
--
-- Une seule valeur, pour la pastille du tableau de bord : charger la
-- liste complète des conversations pour n'en afficher qu'un chiffre
-- serait coûteux sur chaque page d'administration.
-- ============================================================
create or replace function public.whatsapp_non_lus()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nb int;
begin
  if not public.is_admin() then
    return 0;
  end if;
  select count(*)::int into v_nb
    from public.whatsapp_messages
   where sens = 'entrant' and lu_le is null;
  return coalesce(v_nb, 0);
end;
$$;

revoke all on function public.whatsapp_conversations() from public, anon;
revoke all on function public.whatsapp_fil(text, int) from public, anon;
revoke all on function public.whatsapp_marquer_lu(text) from public, anon;
revoke all on function public.whatsapp_non_lus() from public, anon;

grant execute on function public.whatsapp_conversations() to authenticated;
grant execute on function public.whatsapp_fil(text, int) to authenticated;
grant execute on function public.whatsapp_marquer_lu(text) to authenticated;
grant execute on function public.whatsapp_non_lus() to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - rien n'est envoyé, rien n'est modifié
--
-- ILS N'APPELLENT PAS LES FONCTIONS CI-DESSUS, ET C'EST VOULU. Toutes
-- passent par is_admin(), qui lit auth.uid() : dans l'éditeur SQL il
-- n'y a pas de session, auth.uid() vaut NULL, et l'appel échouerait sur
-- « Réservé aux administrateurs » - en emportant au passage la création
-- de la table, puisque l'éditeur exécute le fichier d'un bloc. Ces
-- fonctions se vérifient depuis la page, connecté.
-- ============================================================
-- a) La table existe. Elle est vide au premier passage, et se remplira
--    dès que whatsapp-webhook sera redéployé.
select count(*) as messages_enregistres from public.whatsapp_messages;

-- b) Les quatre fonctions sont bien en place, avec leurs paramètres.
select p.proname as fonction,
       pg_get_function_identity_arguments(p.oid) as parametres
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('whatsapp_conversations', 'whatsapp_fil',
                     'whatsapp_marquer_lu', 'whatsapp_non_lus')
 order by p.proname;

-- c) Le rattachement au membre, éprouvé sans dépendre des messages : un
--    numéro au format Meta (« 221 » + neuf chiffres) doit retrouver le
--    profil correspondant. Le compte attendu est celui des membres
--    ayant un téléphone exploitable.
select count(*) as profils_rattachables
  from public.profiles p
 where p.phone is not null
   and length(public.telephone_cle(p.phone)) = 9;
