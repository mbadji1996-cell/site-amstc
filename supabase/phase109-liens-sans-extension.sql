-- ============================================================
-- PHASE 109 - Les liens envoyés par la base perdent leur « .html »
--
-- POURQUOI ICI AUSSI. Les adresses du site ne portent plus d'extension.
-- Mais une partie des liens que reçoivent les membres n'est pas écrite
-- dans le site : elle est écrite dans la BASE, par les fonctions qui
-- composent les messages WhatsApp, Telegram et les annonces de la
-- chaîne. Corriger les pages sans corriger celles-ci laisserait un
-- « membres/profil.html » dans le message le plus lu de tous - celui
-- qui rappelle à quelqu'un de renouveler sa carte.
--
-- COMMENT. On ne réécrit PAS les fonctions à la main depuis les
-- fichiers de phase : plusieurs ont été redéfinies depuis (phase 88,
-- puis 89, puis 97 pour texte_whatsapp_membre), et recopier une version
-- périmée effacerait des corrections. On demande donc à Postgres la
-- définition RÉELLEMENT en place, on y remplace les adresses, et on la
-- réexécute. Ce qui est en base reste la référence.
--
-- DEUX FORMES D'ÉCRITURE, parce que les liens se composent de deux
-- façons dans ces fonctions :
--   'https://amstc.org/membres/profil.html?open=validity'   (un seul texte)
--   'https://amstc.org/c/' || new.id::text || '.html'       (concaténé)
-- La seconde n'est pas atteinte par un remplacement sur l'adresse : le
-- « .html » y est un morceau séparé. D'où les deux passes.
--
-- SANS EFFET SUR LES LIENS DÉJÀ ENVOYÉS : les anciens messages portent
-- encore « .html », et ces adresses continuent de répondre - GitHub
-- Pages sert les deux formes. Rien ne casse derrière nous.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > Run.
-- Ré-exécutable sans danger : la seconde exécution ne trouve plus rien
-- à changer et ne touche à aucune fonction.
-- ============================================================

do $$
declare
  r        record;
  src      text;
  modifie  text;
  n        int := 0;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.prokind = 'f'
       -- On vise les LIENS, pas le mot « .html ». Certaines fonctions le
       -- portent dans un commentaire (« recopié de validation.html ») :
       -- les réécrire ne changerait rien et brouillerait le contrôle.
       -- « api.amstc.org » n'est pas concerné : aucun lien en « .html ».
       and (pg_get_functiondef(p.oid) ~ 'https://amstc\.org/[A-Za-z0-9_/.~-]*\.html'
         or pg_get_functiondef(p.oid) ~ '\|\|\s*''\.html''')
  loop
    src := pg_get_functiondef(r.oid);

    -- 1. L'adresse écrite d'un seul tenant. On s'arrête au premier
    --    caractère qui ne peut pas appartenir à un chemin, ce qui
    --    préserve la requête : « profil.html?open=validity » devient
    --    « profil?open=validity ».
    modifie := regexp_replace(
      src,
      '(https://amstc\.org/[A-Za-z0-9_/.~-]*?)\.html',
      '\1', 'g');

    -- 2. L'extension ajoutée par concaténation, après un identifiant :
    --    « || '.html' » disparaît en entier, opérateur compris.
    modifie := regexp_replace(modifie, '\s*\|\|\s*''\.html''', '', 'g');

    -- 3. « index » ne se demande pas : le dossier suffit. Un simple
    --    remplacement de texte, sans expression - c'est la seule adresse
    --    de ce genre composée en base, et elle mérite d'être nommée.
    modifie := replace(modifie,
      'https://amstc.org/membres/index', 'https://amstc.org/membres/');

    if modifie is distinct from src then
      execute modifie;
      n := n + 1;
      raise notice 'phase 109 : % réécrite', r.proname;
    end if;
  end loop;

  raise notice 'phase 109 : % fonction(s) mise(s) à jour.', n;
end $$;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTRÔLES - rien n'est créé, rien n'est supprimé
-- ============================================================
-- a) Plus aucune fonction ne compose une adresse du site en « .html ».
--    Le résultat attendu est VIDE. (Même condition que la boucle : on
--    cherche des liens, pas le mot « .html » dans un commentaire.)
select p.proname
  from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and p.prokind = 'f'
   and (pg_get_functiondef(p.oid) ~ 'https://amstc\.org/[A-Za-z0-9_/.~-]*\.html'
     or pg_get_functiondef(p.oid) ~ '\|\|\s*''\.html''')
 order by 1;

-- b) Le message de rappel de carte, tel qu'un membre le recevra. Le
--    lien doit s'y lire « https://amstc.org/membres/profil?open=validity ».
--    (Cette fonction ne lit rien et n'écrit rien : elle compose un texte.)
select public.texte_whatsapp_membre(
         (select id from public.profiles where status = 'approved' limit 1),
         'carte_expiree')
    as apercu_message;
