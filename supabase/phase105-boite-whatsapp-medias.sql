-- ============================================================
-- PHASE 105 - Images et messages vocaux dans la boîte WhatsApp
--
-- LE BESOIN. Depuis la phase 104, un message-image ou un message vocal
-- reçu s'affiche comme « [une image] » ou « [un message vocal] » -
-- utile pour savoir qu'il faut aller voir, inutile pour voir ou
-- écouter. Cette phase télécharge le fichier et le rend consultable
-- dans la boîte.
--
-- UN BUCKET PRIVÉ, MÊME MODÈLE QUE « documents-reserves » (phase 3c).
-- Personne ne peut deviner ni partager une URL directe : l'accès passe
-- par une URL SIGNÉE, générée à la demande pour un administrateur
-- connecté, valable quelques minutes. Seule la lecture est ouverte aux
-- administrateurs ; l'écriture reste réservée à la clé service_role -
-- c'est le webhook, jamais le navigateur, qui y dépose un fichier.
--
-- LE CHEMIN DE STOCKAGE est « <téléphone>/<identifiant Meta du
-- message> », sans extension : Supabase Storage sert le fichier avec
-- le type MIME posé à l'écriture (media_mime), qui commande à lui seul
-- comment le navigateur l'interprète - l'extension du nom n'a aucun
-- rôle là-dedans.
--
-- CE QUI N'EST PAS FAIT ICI. La fonction Edge whatsapp-webhook doit
-- être REDÉPLOYÉE : elle seule sait aller chercher le fichier chez
-- Meta et le déposer ici. Sans ce redéploiement, cette phase ne change
-- rien de visible - la table est prête, mais personne n'y écrit encore.
--
-- PRÉREQUIS : phase 104.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('whatsapp-medias', 'whatsapp-medias', false)
on conflict (id) do nothing;

drop policy if exists "Admins can read whatsapp medias" on storage.objects;
create policy "Admins can read whatsapp medias"
  on storage.objects for select
  using (bucket_id = 'whatsapp-medias' and public.is_admin());

-- Aucune policy INSERT / UPDATE / DELETE pour les utilisateurs
-- authentifiés : seule la clé service_role, qui contourne RLS, écrit
-- ici. Un administrateur connecté ne doit pas pouvoir y déposer un
-- fichier depuis le navigateur.

alter table public.whatsapp_messages add column if not exists media_path text;
alter table public.whatsapp_messages add column if not exists media_mime text;

-- « returns table » change de forme : create or replace function ne le
-- permet pas, il faut supprimer la fonction avant de la recréer (déjà
-- fait ainsi en phase60 pour la même raison).
drop function if exists public.whatsapp_fil(text, int);

create function public.whatsapp_fil(
  p_telephone text,
  p_limite int default 300
)
returns table(
  id             uuid,
  sens           text,
  texte          text,
  type_message   text,
  media_path     text,
  media_mime     text,
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
  select t.id, t.sens, t.texte, t.type_message, t.media_path, t.media_mime,
         t.envoye_par_nom, t.via, t.cree_le
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

revoke all on function public.whatsapp_fil(text, int) from public, anon;
grant execute on function public.whatsapp_fil(text, int) to authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - rien n'est envoyé, rien n'est modifié
--
-- Comme en phase 104, ils n'appellent pas whatsapp_fil : elle passe par
-- is_admin(), qui lit auth.uid(), inexistant dans l'éditeur SQL - son
-- appel échouerait ici et emporterait tout le fichier avec lui. Elle se
-- vérifie depuis la page, connecté.
-- ============================================================
-- a) Le bucket existe, et il est privé.
select id, public from storage.buckets where id = 'whatsapp-medias';

-- b) Les deux colonnes sont en place.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'whatsapp_messages'
   and column_name in ('media_path', 'media_mime');

-- c) La fonction a bien la nouvelle forme, avec ses neuf colonnes.
select p.proname, pg_get_function_result(p.oid) as forme
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'whatsapp_fil';
