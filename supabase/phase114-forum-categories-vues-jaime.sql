-- ============================================================
-- PHASE 114 - Forum : catégories, vues et « J'aime »
--
-- POURQUOI. Le forum listait des sujets sans rien pour s'y retrouver :
-- pas de catégorie, donc pas de tri possible entre une question, une
-- idée et un témoignage ; pas de compteur de vues, donc rien qui dise
-- qu'un sujet est lu même sans réponse ; et aucun moyen d'approuver un
-- message sans écrire « +1 », ce qui allonge les discussions.
--
-- CE QUE FAIT CE SCRIPT.
--   1. Deux colonnes sur forum_topics : categorie et vues.
--   2. Une fonction qui compte une vue, appelée à l'ouverture d'un sujet.
--      Elle n'écrit que ce compteur : un membre ne peut pas modifier un
--      sujet qui n'est pas le sien.
--   3. Une table forum_jaime (un « J'aime » par personne et par message),
--      avec ses règles d'accès.
--   4. forum_topics_list renvoie de quoi peupler les cartes : catégorie,
--      vues, date de création, photo de l'auteur et dernier intervenant.
--
-- APRÈS : les pastilles de catégorie filtrent la liste, les cartes
-- affichent réponses et vues, et « J'aime » fonctionne sur le sujet comme
-- sur les réponses. Tant que le script n'est pas passé, le forum
-- fonctionne comme avant : les sujets sont rangés dans « Autres », les
-- vues restent à 0 et le bouton « J'aime » ne s'affiche pas.
-- ============================================================

-- ===== 1. Catégorie et vues =====
alter table public.forum_topics
  add column if not exists categorie text not null default 'autres',
  add column if not exists vues      int  not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'forum_topics_categorie_check') then
    alter table public.forum_topics
      add constraint forum_topics_categorie_check
      check (categorie in ('actualites', 'questions', 'idees', 'temoignages', 'documents', 'autres'));
  end if;
end $$;

comment on column public.forum_topics.categorie is
  'actualites, questions, idees, temoignages, documents ou autres.';
comment on column public.forum_topics.vues is
  'Nombre d''ouvertures du sujet. Incrémenté par forum_compter_vue().';

-- ===== 2. Compter une vue =====
-- SECURITY DEFINER pour n'autoriser QUE l'incrément : les politiques
-- d'écriture de forum_topics restent réservées à l'auteur et aux
-- administrateurs.
create or replace function public.forum_compter_vue(p_topic uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_approved_member() then
    raise exception 'Accès réservé aux membres approuvés.';
  end if;
  update public.forum_topics set vues = coalesce(vues, 0) + 1 where id = p_topic;
end;
$$;

grant execute on function public.forum_compter_vue(uuid) to authenticated;

-- ===== 3. Les « J'aime » =====
create table if not exists public.forum_jaime (
  id          uuid primary key default gen_random_uuid(),
  cible_type  text not null check (cible_type in ('sujet', 'reponse')),
  cible_id    uuid not null,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- Une personne, un « J'aime » par message.
create unique index if not exists forum_jaime_unicite
  on public.forum_jaime (cible_type, cible_id, user_id);
create index if not exists forum_jaime_cible
  on public.forum_jaime (cible_type, cible_id);

alter table public.forum_jaime enable row level security;

drop policy if exists "Membres lisent les jaime" on public.forum_jaime;
create policy "Membres lisent les jaime"
  on public.forum_jaime for select
  using (public.is_approved_member());

-- On ne peut aimer QUE pour soi : user_id doit être celui de l'appelant.
drop policy if exists "Membres posent leur jaime" on public.forum_jaime;
create policy "Membres posent leur jaime"
  on public.forum_jaime for insert
  with check (public.is_approved_member() and user_id = auth.uid());

drop policy if exists "Membres retirent leur jaime" on public.forum_jaime;
create policy "Membres retirent leur jaime"
  on public.forum_jaime for delete
  using (user_id = auth.uid());

-- ===== 4. La liste des sujets =====
drop function if exists public.forum_topics_list(int);

create or replace function public.forum_topics_list(p_limit int default 50)
returns table (
  id                uuid,
  title             text,
  body              text,
  categorie         text,
  vues              int,
  created_at        timestamptz,
  last_activity_at  timestamptz,
  reply_count       int,
  author_name       text,
  author_photo      text,
  dernier_auteur    text
)
language plpgsql
as $$
begin
  perform public.check_rate_limit('forum_topics_list', 30, interval '5 minutes');
  return query
    select t.id, t.title, t.body, t.categorie, t.vues, t.created_at, t.last_activity_at,
           t.reply_count, p.full_name, p.photo_url,
           -- Nom du dernier intervenant : « Réponse de … » sur la carte.
           (select pr.full_name
              from public.forum_replies r
              left join public.profiles pr on pr.id = r.author_id
             where r.topic_id = t.id
             order by r.created_at desc
             limit 1)
    from public.forum_topics t
    left join public.profiles p on p.id = t.author_id
    order by t.last_activity_at desc
    limit least(coalesce(p_limit, 50), 100);
end;
$$;

grant execute on function public.forum_topics_list(int) to authenticated;

notify pgrst, 'reload schema';

-- ===== 5. Contrôle =====
select categorie, count(*) as sujets, sum(vues) as vues
  from public.forum_topics
 group by categorie
 order by sujets desc;

select count(*) as jaime from public.forum_jaime;
