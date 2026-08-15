-- ============================================================
-- PHASE 82 - Publication automatique sur la chaîne Telegram
--
-- LA CHAÎNE EST PUBLIQUE (@AMSTC, ~200 abonnés). Tout ce qui part par
-- ici est lu par ses abonnés et par quiconque l'ouvre. Ce script ne
-- diffuse donc QUE des titres et des résumés déjà destinés à être
-- publics - jamais un nom de membre, un montant ou une référence de
-- paiement. Les notifications d'administration continuent d'aller
-- exclusivement dans votre conversation privée avec le bot.
--
-- CE QUI EST DIFFUSÉ, et pourquoi :
--
--   1. Un cours du Daara publié       -> il a déjà une page publique /c/
--   2. Un document ajouté à la
--      bibliothèque                   -> il a déjà une page publique /b/
--   3. Une collecte ouverte           -> c'est un appel à participer
--
-- Le CONTENU reste réservé aux membres dans les trois cas : la chaîne
-- annonce l'existence et le titre, le lien mène à l'espace membres.
--
-- CHAQUE DIFFUSION EST INDÉPENDANTE. Pour en couper une, il suffit de
-- supprimer son déclencheur - la commande est donnée en fin de fichier.
--
-- PRÉREQUIS : phase25 (notify_admin), et la variable d'environnement
-- TELEGRAM_CHANNEL_ID côté Coolify. Sans elle, la fonction Edge répond
-- « 503 » et rien n'est publié - sans casser quoi que ce soit.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. Publier un message sur la chaîne =====
-- Utilisable à la main pour une annonce libre :
--   select public.publier_sur_chaine('Titre', 'Le texte.', 'https://amstc.org/...');
create or replace function public.publier_sur_chaine(
  p_titre text,
  p_texte text default null,
  p_lien  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Appel manuel : réservé aux administrateurs. Les déclencheurs
  -- ci-dessous s'exécutent sans utilisateur connecté (auth.uid() nul)
  -- et ne sont donc pas concernés par ce contrôle.
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Accès refusé.';
  end if;

  if btrim(coalesce(p_titre, '')) = '' then
    raise exception 'Le titre est obligatoire.';
  end if;

  perform public.notify_admin('publication_chaine', jsonb_build_object(
    'titre', btrim(p_titre),
    'texte', nullif(btrim(coalesce(p_texte, '')), ''),
    'lien',  nullif(btrim(coalesce(p_lien, '')), '')
  ));
end;
$$;

revoke all on function public.publier_sur_chaine(text, text, text) from public, anon;
grant execute on function public.publier_sur_chaine(text, text, text) to authenticated;

-- ===== 2. Un cours du Daara publié =====
create or replace function public.chaine_cours_publie()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Uniquement au PASSAGE à publié : une correction de texte sur un
  -- cours déjà publié ne doit pas le réannoncer.
  if new.is_published is not true then return new; end if;
  if tg_op = 'UPDATE' and old.is_published is true then return new; end if;

  begin
    perform public.publier_sur_chaine(
      'Nouveau cours : ' || new.title,
      nullif(btrim(coalesce(new.description, '')), ''),
      'https://amstc.org/c/' || new.id::text || '.html'
    );
  exception when others then
    -- Une diffusion en panne ne doit jamais empêcher la publication du
    -- cours : le déclencheur vit dans la transaction de l'administrateur.
    raise warning 'chaine_cours_publie : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_cours_publie_chaine on public.daara_courses;
create trigger on_cours_publie_chaine
  after insert or update of is_published on public.daara_courses
  for each row execute function public.chaine_cours_publie();

-- ===== 3. Un document ajouté à la bibliothèque =====
create or replace function public.chaine_bibliotheque_ajout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.category is distinct from 'bibliotheque' then return new; end if;

  begin
    perform public.publier_sur_chaine(
      'Nouveau document : ' || new.title,
      coalesce(nullif(btrim(coalesce(new.excerpt, '')), ''),
               'Disponible dans la bibliothèque de l''espace membres.'),
      'https://amstc.org/b/' || new.id::text || '.html'
    );
  exception when others then
    raise warning 'chaine_bibliotheque_ajout : %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_bibliotheque_ajout_chaine on public.restricted_articles;
create trigger on_bibliotheque_ajout_chaine
  after insert on public.restricted_articles
  for each row execute function public.chaine_bibliotheque_ajout();

-- ===== 4. Une collecte ouverte =====
-- Le bloc est conditionnel : la table n'existe que si la phase 55 a été
-- exécutée.
do $$
begin
  if to_regclass('public.collectes') is null then
    raise notice 'collectes absente (phase55 non exécutée) : déclencheur ignoré.';
    return;
  end if;

  execute $f$
    create or replace function public.chaine_collecte_ouverte()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    begin
      if new.is_open is not true then return new; end if;
      if tg_op = 'UPDATE' and old.is_open is true then return new; end if;

      begin
        perform public.publier_sur_chaine(
          'Nouvelle collecte : ' || new.titre,
          nullif(btrim(coalesce(new.description, '')), ''),
          'https://amstc.org/membres/collectes.html'
        );
      exception when others then
        raise warning 'chaine_collecte_ouverte : %', sqlerrm;
      end;
      return new;
    end;
    $body$;
  $f$;

  execute 'drop trigger if exists on_collecte_ouverte_chaine on public.collectes';
  execute 'create trigger on_collecte_ouverte_chaine
             after insert or update of is_open on public.collectes
             for each row execute function public.chaine_collecte_ouverte()';
end $$;

-- ===== 5. Contrôle : les déclencheurs de diffusion en place =====
select c.relname as table_surveillee, t.tgname as declencheur
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and t.tgname like '%chaine%'
 order by c.relname;

-- ============================================================
-- ESSAI - à lancer QUAND VOUS ÊTES PRÊT, il publie pour de bon :
--
--   select public.publier_sur_chaine(
--     'Essai', 'Message de contrôle, à supprimer.', null);
--
-- Vérifiez qu'il apparaît sur la chaîne, puis supprimez-le.
--
-- ============================================================
-- COUPER UNE DIFFUSION - chacune indépendamment :
--
--   drop trigger if exists on_cours_publie_chaine on public.daara_courses;
--   drop trigger if exists on_bibliotheque_ajout_chaine on public.restricted_articles;
--   drop trigger if exists on_collecte_ouverte_chaine on public.collectes;
--
-- Les couper toutes laisse publier_sur_chaine() utilisable à la main.
-- ============================================================
