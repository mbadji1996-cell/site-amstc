-- ============================================================
-- PHASE 113 - Vidéos et documents dans la médiathèque
--
-- POURQUOI PAS DE FICHIERS VIDÉO CHEZ NOUS. Une vidéo de 10 minutes en
-- 1080p pèse 300 à 800 Mo. La stocker dans Supabase, c'est payer l'espace
-- ET la bande passante à chaque lecture : 50 membres qui regardent la même
-- vidéo font 15 à 40 Go de trafic sortant sur le VPS, pour une seule
-- activité. Le disque se remplit, les sauvegardes s'allongent, et une
-- lecture depuis un téléphone au Sénégal dépend alors de la liaison du
-- serveur, sans découpage adaptatif.
--
-- CE QU'ON FAIT À LA PLACE. La base ne garde qu'un LIEN : la vidéo vit sur
-- YouTube (en « non répertoriée » si elle ne doit pas être publique), et
-- c'est YouTube qui sert la lecture, adapte la qualité au réseau et paie la
-- bande passante. Même principe pour un document lourd (PDF d'un rapport)
-- hébergé sur Drive. La vignette d'une vidéo YouTube se déduit de son
-- identifiant : aucune image à stocker non plus.
--
-- CE QUE FAIT CE SCRIPT. Cinq colonnes sur media_folders, pour qu'une
-- entrée de la médiathèque soit au choix un album photo (comme
-- aujourd'hui), une vidéo ou un document.
--
-- APRÈS : l'administration propose « Album photo / Vidéo / Document » à la
-- création, et la médiathèque des membres filtre par type. Tant que ce
-- script n'est pas passé, tout continue comme avant : les entrées
-- existantes sont des albums photo.
-- ============================================================

-- ===== 1. Les colonnes =====
alter table public.media_folders
  add column if not exists media_type text not null default 'photos',
  add column if not exists media_url  text,
  add column if not exists duree      text,
  add column if not exists taille     text,
  add column if not exists date_media date;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'media_folders_media_type_check'
  ) then
    alter table public.media_folders
      add constraint media_folders_media_type_check
      check (media_type in ('photos', 'video', 'document'));
  end if;
end $$;

comment on column public.media_folders.media_type is
  'photos (album), video (lien externe) ou document (lien externe).';
comment on column public.media_folders.media_url is
  'Lien de la vidéo (YouTube) ou du document (Drive, PDF en ligne). Jamais un fichier stocké ici : voir l''en-tête de phase113.';
comment on column public.media_folders.duree is
  'Durée affichée sur la vignette d''une vidéo, au format libre (ex. 12:45).';
comment on column public.media_folders.taille is
  'Poids affiché sur la vignette d''un document (ex. 2,4 Mo).';
comment on column public.media_folders.date_media is
  'Date de l''activité montrée, affichée sur la carte. À défaut, la date de création sert.';

-- ===== 2. Contrôle =====
select column_name, data_type, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'media_folders'
   and column_name in ('media_type', 'media_url', 'duree', 'taille', 'date_media')
 order by column_name;

select media_type, count(*) as entrees
  from public.media_folders
 where parent_id is null
 group by media_type;
