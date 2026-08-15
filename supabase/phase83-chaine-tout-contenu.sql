-- ============================================================
-- PHASE 83 - La chaîne annonce TOUT le nouveau contenu des membres
--
-- Étend la phase 82. Ce qui s'ajoute :
--
--   restricted_articles  toutes catégories (la phase 82 ne couvrait que
--                        la bibliothèque) : formations, réalisations,
--                        documents officiels
--   medical_lessons      leçon médicale publiée
--   member_announcements annonce aux membres
--   products             nouveau produit de la boutique
--   media_folders        album de la médiathèque publié
--
-- CE QUI EST VOLONTAIREMENT EXCLU, et pourquoi :
--
--   forum_topics    ce sont des DISCUSSIONS entre membres, souvent des
--                   questions personnelles. Les diffuser sur une chaîne
--                   publique trahirait leurs auteurs. À demander
--                   explicitement si vous le souhaitez quand même.
--   media_photos    une seule photo n'est pas un événement ; c'est
--                   l'ALBUM qui en est un. Annoncer chaque photo
--                   noierait la chaîne à chaque import.
--   product_photos  même raison.
--   quizzes         accessoires d'un cours déjà annoncé.
--
-- GARDE-FOU CONTRE L'INONDATION. L'import d'un dossier entier peut
-- insérer des dizaines de documents d'un coup - autant de messages sur
-- une chaîne de 200 abonnés. Chaque déclencheur sensible compte donc
-- les lignes créées dans la minute écoulée : au-delà de 5, il se tait
-- et le signale dans les journaux. Un import en masse ne diffuse rien ;
-- annoncez-le vous-même avec publier_sur_chaine() si vous le souhaitez.
--
-- PRÉREQUIS : phase82 (publier_sur_chaine).
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== Détecteur d'import en masse =====
create or replace function public.chaine_rafale(p_table regclass, p_seuil int default 5)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_n int;
begin
  execute format(
    'select count(*) from %s where created_at > now() - interval ''60 seconds''', p_table)
    into v_n;
  return v_n > p_seuil;
exception when others then
  -- Table sans colonne created_at, ou toute autre surprise : on ne
  -- bloque pas la diffusion pour autant.
  return false;
end;
$$;

-- ===== 1. restricted_articles : TOUTES les catégories =====
create or replace function public.chaine_bibliotheque_ajout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intitule text;
  v_lien     text;
begin
  -- Un libellé par catégorie : « Nouveau document » n'aurait aucun sens
  -- pour une formation.
  v_intitule := case new.category
    when 'bibliotheque' then 'Nouveau document'
    when 'formation'    then 'Nouvelle formation'
    when 'actualite'    then 'Nouvelle réalisation'
    when 'document'     then 'Nouveau document officiel'
    else null
  end;
  if v_intitule is null then return new; end if;

  -- Seule la bibliothèque dispose d'une page d'aperçu par document
  -- (phase 76). Les autres catégories renvoient vers leur écran.
  v_lien := case new.category
    when 'bibliotheque' then 'https://amstc.org/b/' || new.id::text || '.html'
    when 'formation'    then 'https://amstc.org/membres/formations.html'
    when 'actualite'    then 'https://amstc.org/membres/actualites.html'
    when 'document'     then 'https://amstc.org/membres/documents.html'
  end;

  if public.chaine_rafale('public.restricted_articles') then
    raise warning 'chaine : import en masse détecté, « % » non diffusé.', new.title;
    return new;
  end if;

  begin
    perform public.publier_sur_chaine(
      v_intitule || ' : ' || new.title,
      coalesce(nullif(btrim(coalesce(new.excerpt, '')), ''),
               'Disponible dans l''espace membres.'),
      v_lien);
  exception when others then
    raise warning 'chaine_bibliotheque_ajout : %', sqlerrm;
  end;
  return new;
end;
$$;

-- ===== 2. Leçon médicale publiée =====
create or replace function public.chaine_lecon_publiee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_published is not true then return new; end if;
  if tg_op = 'UPDATE' and old.is_published is true then return new; end if;

  begin
    perform public.publier_sur_chaine(
      'Nouvelle leçon : ' || new.title,
      nullif(btrim(coalesce(new.description, '')), ''),
      'https://amstc.org/c/' || new.id::text || '.html');
  exception when others then
    raise warning 'chaine_lecon_publiee : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_lecon_publiee_chaine on public.medical_lessons;
create trigger on_lecon_publiee_chaine
  after insert or update of is_published on public.medical_lessons
  for each row execute function public.chaine_lecon_publiee();

-- ===== 3. Annonce aux membres =====
create or replace function public.chaine_annonce()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active is not true then return new; end if;

  begin
    perform public.publier_sur_chaine(
      new.title,
      nullif(btrim(coalesce(new.body, '')), ''),
      'https://amstc.org/membres/index.html');
  exception when others then
    raise warning 'chaine_annonce : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_annonce_chaine on public.member_announcements;
create trigger on_annonce_chaine
  after insert on public.member_announcements
  for each row execute function public.chaine_annonce();

-- ===== 4. Nouveau produit de la boutique =====
create or replace function public.chaine_produit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_published is not true then return new; end if;
  if tg_op = 'UPDATE' and old.is_published is true then return new; end if;
  if public.chaine_rafale('public.products') then
    raise warning 'chaine : import en masse détecté, « % » non diffusé.', new.name;
    return new;
  end if;

  begin
    perform public.publier_sur_chaine(
      'Boutique : ' || new.name,
      trim(both from coalesce(nullif(btrim(coalesce(new.description, '')), '') || ' - ', '')
           || new.price_fcfa::text || ' FCFA'),
      'https://amstc.org/membres/boutique.html');
  exception when others then
    raise warning 'chaine_produit : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_produit_chaine on public.products;
create trigger on_produit_chaine
  after insert or update of is_published on public.products
  for each row execute function public.chaine_produit();

-- ===== 5. Album de la médiathèque publié =====
create or replace function public.chaine_album()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_published is not true then return new; end if;
  if tg_op = 'UPDATE' and old.is_published is true then return new; end if;

  begin
    perform public.publier_sur_chaine(
      'Médiathèque : ' || new.title,
      'Album ' || coalesce(new.year::text, '') || ' - photos disponibles dans l''espace membres.',
      'https://amstc.org/membres/mediatheque.html');
  exception when others then
    raise warning 'chaine_album : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_album_chaine on public.media_folders;
create trigger on_album_chaine
  after insert or update of is_published on public.media_folders
  for each row execute function public.chaine_album();

-- ===== 6. Contrôle =====
select c.relname as table_surveillee, t.tgname as declencheur
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and t.tgname like '%chaine%'
 order by c.relname;

-- ============================================================
-- COUPER UNE DIFFUSION, indépendamment des autres :
--
--   drop trigger if exists on_lecon_publiee_chaine on public.medical_lessons;
--   drop trigger if exists on_annonce_chaine on public.member_announcements;
--   drop trigger if exists on_produit_chaine on public.products;
--   drop trigger if exists on_album_chaine on public.media_folders;
--   drop trigger if exists on_bibliotheque_ajout_chaine on public.restricted_articles;
--   drop trigger if exists on_cours_publie_chaine on public.daara_courses;
--   drop trigger if exists on_collecte_ouverte_chaine on public.collectes;
-- ============================================================
