# Configurer l'Espace Membres (amstc.org/membres)

L'Espace Membres a besoin d'un vrai compte utilisateur et d'une base de
données (mots de passe, statut d'approbation, etc.), ce que le site
statique actuel ne peut pas gérer seul. On utilise **Supabase** pour ça :
un service gratuit qui fournit l'authentification et la base de données
Postgres, sans que vous ayez à héberger quoi que ce soit.

Le code des pages (`membres/*.html`) est déjà prêt. Il ne manque que la
connexion à votre projet Supabase - suivez les étapes ci-dessous.

## 1. Créer un projet Supabase

1. Allez sur [supabase.com](https://supabase.com) et créez un compte
   (vous pouvez vous inscrire avec GitHub)
2. Cliquez **New project**
3. Choisissez un nom (ex. `amstc`), un mot de passe pour la base de
   données (à conserver de côté, vous n'en aurez normalement plus besoin
   au quotidien) et une région proche (ex. `Europe West`)
4. Cliquez **Create new project** et patientez quelques minutes pendant
   le provisionnement

## 2. Créer les tables et les règles de sécurité

1. Dans le tableau de bord du projet, ouvrez **SQL Editor** (menu de
   gauche) → **New query**
2. Ouvrez le fichier `supabase/schema.sql` (fourni dans ce dépôt), copiez
   tout son contenu, collez-le dans l'éditeur SQL
3. Cliquez **Run**

Cela crée la table `profiles` (une ligne par compte : nom, e-mail, rôle,
statut d'approbation) et les règles qui empêchent un utilisateur de lire
ou modifier les comptes des autres.

## 3. Récupérer l'URL et la clé du projet

1. Dans le tableau de bord → **Project Settings** (icône engrenage) →
   **API**
2. Notez :
   - **Project URL** (ex. `https://abcdefgh.supabase.co`)
   - **anon public key** (une longue chaîne de caractères)

Ces deux valeurs sont conçues pour être visibles côté navigateur - la
sécurité ne repose pas sur leur confidentialité, mais sur les règles
mises en place à l'étape 2. Transmettez-les-moi, je les intègre dans
`assets/js/supabase-client.js` à la place de `VOTRE-PROJET` et
`VOTRE_CLE_ANON`.

## 4. Créer le premier compte administrateur

Une fois qu'une première personne s'est inscrite via
`membres/inscription.html`, il faut promouvoir manuellement son compte en
administrateur (pour qu'elle puisse ensuite approuver les suivants depuis
`membres/validation.html`) :

1. Dans Supabase → **SQL Editor** → **New query**
2. Exécutez (en remplaçant l'e-mail) :

```sql
update public.profiles
set role = 'admin', status = 'approved'
where email = 'son-email@exemple.com';
```

Les inscriptions suivantes pourront être approuvées directement depuis
`membres/validation.html`, sans repasser par le SQL Editor.

## 4bis. Activer la Phase 2 (rôles Administrateur / Super Administrateur)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase2-roles.sql` (fourni dans ce dépôt),
   copiez tout son contenu, collez-le, cliquez **Run**
3. Promouvez votre compte admin existant en Super Administrateur (en
   remplaçant l'e-mail) :

```sql
update public.profiles
set role = 'super_admin'
where email = 'votre-email@exemple.com';
```

À partir de là, sur `membres/validation.html` :
- **Administrateur et Super Administrateur** peuvent approuver/refuser les
  inscriptions, activer/désactiver un compte, et envoyer un lien de
  réinitialisation de mot de passe
- **Seul le Super Administrateur** voit la section "Droits d'administration"
  pour nommer ou révoquer des administrateurs

## 4ter. Activer la Phase 3 (contenu réservé aux membres : Formation + Réalisations)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase3-restricted-formations.sql`, copiez
   tout son contenu, collez-le, cliquez **Run**
3. Ouvrez ensuite `supabase/phase3b-generalize-restricted-content.sql`
   (généralise le système à la fois à Formation et à Réalisations),
   copiez-collez, cliquez **Run**

Ça crée une table séparée pour le contenu réservé, volontairement **hors
du dépôt Git public** (contrairement aux articles Formation/Réalisations
habituels publiés via le CMS, qui restent lisibles par n'importe qui
dans l'historique GitHub). C'est la seule façon d'avoir un contenu
vraiment privé sur ce site.

Ensuite :
- `membres/contenu-reserve-admin.html` (visible aux administrateurs
  depuis `membres/index.html`) permet de publier/modifier/supprimer du
  contenu réservé : type (Formation ou Réalisation), titre, résumé,
  contenu en Markdown, image de couverture, vidéo YouTube
- Pour tout membre approuvé, `membres/formations.html` et
  `membres/actualites.html` listent **à la fois** les articles publics
  habituels et les contenus réservés, en un seul endroit (avec un badge
  "🔒 Réservé aux membres" sur ces derniers pour les distinguer)
- Sur les pages publiques `formations.html` et `actualites.html`, ces
  articles réservés apparaissent aussi, mais en aperçu verrouillé (titre
  et résumé visibles par tous, contenu complet chargé uniquement après
  connexion et vérification côté serveur)

**Limite à connaître** : il n'y a pas d'envoi de fichier configuré pour
l'image de couverture - il faut coller l'URL d'une image déjà en ligne
(par exemple une image déjà publiée via le CMS habituel, dont vous
pouvez copier l'adresse).

## 4quater. Activer les documents officiels réservés (Statuts, Règlement intérieur, rapports...)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase3c-documents-officiels.sql`, copiez
   tout son contenu, collez-le, cliquez **Run**

Contrairement aux formations/réalisations réservées (texte + image),
les documents officiels sont de vrais fichiers PDF. Ce script crée en
plus un espace de stockage Supabase **privé** (`documents-reserves`) :
personne ne peut deviner ou partager une URL directe vers un fichier -
l'accès se fait uniquement via un lien signé, généré à la demande,
après vérification que la personne connectée est bien un membre
approuvé.

Ensuite :
- Dans `membres/contenu-reserve-admin.html`, choisissez le type
  "Document officiel", donnez un titre/résumé, et envoyez le PDF
  (Statuts, Règlement intérieur, rapport annuel, PV d'AG...)
- `membres/documents.html` liste ces documents pour tout membre
  approuvé, avec un bouton "Télécharger" qui génère un lien valable
  une minute

## 4quinquies. Activer la restriction d'accès pour cartes expirées (2 mois de grâce)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase10-restriction-cartes-expirees.sql`,
   copiez tout son contenu, collez-le, cliquez **Run**
   (nécessite d'avoir déjà exécuté `phase3`, `phase3b`, `phase3c` et
   `phase7-validite-cotisations.sql`)

La validité de la carte d'un membre (`profiles.card_valid_until`, une
année) suit la convention : une carte valable jusqu'en année N expire le
1er janvier N+1. Un membre dispose alors d'un délai de grâce de 2 mois
(jusqu'au 1er mars N+1) pendant lequel un bandeau de rappel s'affiche sur
le tableau de bord et sur les pages de contenu réservé, mais l'accès reste
ouvert. Passé le 1er mars N+1, l'accès aux Formations, Réalisations et
Documents officiels réservés (le système "contenu réservé" - pas l'Espace
Daara, ni les Enseignements Médicaux/Quiz, ni la Boutique) est coupé
côté base de données (RLS), pas seulement côté affichage.

**Interrupteur global** : cette coupure ne s'applique que si l'admin l'a
explicitement activée. Dans `membres/cartes-admin.html`, un bouton
"Activer/Désactiver la restriction" contrôle la ligne unique de la table
`app_settings` (`restriction_cartes_active`). Tant qu'elle est désactivée
(valeur par défaut après l'exécution du script), tous les membres gardent
l'accès aux contenus réservés quelle que soit l'ancienneté de leur carte
expirée - seul le bandeau de rappel s'affiche. Ça permet de mener une
campagne de renouvellement des cartes en amont, puis d'activer la coupure
une fois la campagne terminée.

## 5. Configurer l'e-mail d'expédition (optionnel pour démarrer)

Supabase envoie déjà les e-mails de confirmation d'inscription et de
réinitialisation de mot de passe avec une adresse par défaut, suffisante
pour tester. Si vous voulez que ces e-mails partent de `contact@amstc.org`
plus tard, ce sera à configurer dans **Project Settings → Auth → SMTP
Settings** - pas nécessaire pour la mise en route.

## 6. Tester

Une fois l'URL et la clé intégrées :
1. Allez sur `amstc.org/membres/inscription.html`, créez un compte de
   test
2. Vérifiez dans Supabase → **Table Editor → profiles** qu'une ligne est
   apparue avec `status = pending`
3. Essayez de vous connecter avant validation : un message d'attente doit
   s'afficher, pas d'accès à l'espace membre
4. Approuvez le compte (via l'étape 4 ci-dessus pour le tout premier
   compte, ou via `membres/validation.html` une fois un admin en place)
5. Reconnectez-vous : vous devez accéder à `membres/index.html`
6. Testez "mot de passe oublié" de bout en bout

## Ce qui est couvert pour l'instant (Phases 1, 2 et 3)

- Inscription publique, avec validation manuelle par un administrateur
  avant tout accès
- Connexion, déconnexion, mot de passe oublié / réinitialisation
- Un espace membre minimal (page d'accueil réservée aux comptes
  approuvés)
- Une page de gestion des membres (`membres/validation.html`) :
  approbation/refus des inscriptions, activation/désactivation d'un
  compte, envoi d'un lien de réinitialisation de mot de passe
- Distinction **Administrateur** / **Super Administrateur** : seul le
  Super Administrateur peut nommer ou révoquer des administrateurs (un
  simple administrateur ne peut ni créer d'autres admins, ni modifier les
  droits d'administration - vérifié côté base de données, pas seulement
  côté affichage)
- Formations et Réalisations réservées aux membres, stockées hors du
  dépôt Git public (voir Phase 3 ci-dessus), avec aperçu public
  verrouillé sur les pages publiques correspondantes
- Documents officiels réservés (Statuts, Règlement intérieur, rapports,
  PV d'AG...), sous forme de vrais fichiers PDF stockés dans un espace
  privé, accessibles uniquement via un lien signé temporaire pour les
  membres approuvés
- Restriction d'accès aux contenus réservés (Formations, Réalisations,
  Documents officiels) pour les membres dont la carte est expirée depuis
  plus de 2 mois, avec un délai de grâce et un bandeau de rappel de
  renouvellement (voir Phase 4quinquies ci-dessus)

## Limite connue : création de comptes par un administrateur

Le cahier des charges initial prévoyait qu'un administrateur puisse
"créer des comptes utilisateurs" directement. Ce n'est **pas
implémenté**, et ne peut pas l'être de façon sûre avec l'architecture
actuelle (site statique + clé publique Supabase) : créer un compte sans
mot de passe fourni par la personne elle-même nécessite la clé
"service_role" de Supabase, une clé à tous les droits qui ne doit
**jamais** être placée dans du code accessible depuis un navigateur (elle
permettrait à n'importe quel visiteur de prendre le contrôle de tous les
comptes). Faire ça correctement demanderait un vrai serveur applicatif,
ce qui sortirait du cadre d'un site 100% statique.

En pratique, ça ne change pas grand-chose au fonctionnement : la personne
s'inscrit elle-même via `membres/inscription.html` (comme aujourd'hui),
puis un administrateur ou Super Administrateur l'approuve depuis
`membres/validation.html`.

## Ce qui n'est pas encore fait

- Aucune fonctionnalité prévue en attente pour l'instant (Phases 1, 2 et
  3 toutes en place)
