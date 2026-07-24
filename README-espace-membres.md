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
Documents officiels réservés est coupé côté base de données (RLS), pas
seulement côté affichage.

La page "Formations" regroupe trois modules : Espace Daara, Enseignements
Médicaux (+ Quiz), et les formations/réalisations "Autres" (le système
"contenu réservé" générique). La restriction couvre les trois - voir aussi
`supabase/phase11-restriction-daara-medical.sql` (à exécuter après ce
script), qui étend `is_active_member()` aux tables `daara_courses`,
`daara_progress`, `medical_lessons`, `quizzes`, `quiz_questions` et
`quiz_attempts`. La Boutique et les paiements (adhésion/cotisations)
restent inchangés, gérés par `is_approved_member()`.

**Interrupteur global** : cette coupure ne s'applique que si l'admin l'a
explicitement activée. Dans `membres/cartes-admin.html`, un bouton
"Activer/Désactiver la restriction" contrôle la ligne unique de la table
`app_settings` (`restriction_cartes_active`). Tant qu'elle est désactivée
(valeur par défaut après l'exécution du script), tous les membres gardent
l'accès aux contenus réservés quelle que soit l'ancienneté de leur carte
expirée - seul le bandeau de rappel s'affiche. Ça permet de mener une
campagne de renouvellement des cartes en amont, puis d'activer la coupure
une fois la campagne terminée.

## 4sexies. Activer le Forum (discussion entre membres)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase12-forum.sql`, copiez tout son
   contenu, collez-le, cliquez **Run**

Le Forum est un espace d'échange général (questions, discussions) accessible
à tout membre approuvé, comme la Boutique : gouverné par `is_approved_member()`,
sans lien avec la validité de la carte. Liste unique de sujets sans
catégorie, triée par activité récente (un sujet remonte en tête de liste
dès qu'il reçoit une réponse, via un trigger sur `forum_replies`). Un
membre peut modifier/supprimer ses propres sujets et réponses ; un admin
peut supprimer n'importe quoi (modération), directement depuis
`membres/forum.html` et `membres/forum-sujet.html`.

## 4septies. Activer la Médiathèque (galerie photo par année / activité)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase14-mediatheque.sql`, copiez tout son
   contenu, collez-le, cliquez **Run**

La Médiathèque est organisée en Année → Dossier d'activité → Photos, avec
une photo de couverture par dossier. Accès comme la Boutique/le Forum :
tout membre approuvé (`is_approved_member()`), sans lien avec la validité
de la carte. Les photos sont stockées dans le bucket privé
`mediatheque-photos` (comme `documents-reserves`) : l'accès réel aux
fichiers est gardé par la lecture RLS de `media_folders`/`media_photos` -
le chemin d'une photo d'un dossier non publié n'est jamais renvoyé à un
membre.

Ensuite :
- Dans `membres/mediatheque-admin.html`, créez un album (année + titre),
  importez des photos par glisser-déposer ou en choisissant un dossier
  entier du disque, définissez une couverture, puis publiez l'album.
- `membres/mediatheque.html` liste les albums publiés groupés par année ;
  `membres/mediatheque-dossier.html` affiche la galerie d'un album avec
  un lightbox (clic pour agrandir, flèches du clavier pour naviguer).

Pour créer des sous-dossiers à l'intérieur d'un album (par ex. "Jour 1",
"Jour 2" dans une activité), exécutez aussi
`supabase/phase15-mediatheque-sous-dossiers.sql`. Depuis
`mediatheque-admin.html`, ouvrez un album ("Gérer les photos") puis "Nouveau
sous-dossier" - profondeur illimitée, année héritée automatiquement du
parent, publication indépendante par (sous-)dossier.

**Import de plusieurs dossiers en une fois** (glisser-déposer uniquement -
la boîte de dialogue "Choisir un dossier" du navigateur ne permet de
choisir qu'un seul dossier à la fois) :
- Sur la liste des albums : déposez un dossier "Année" (ex `2026`)
  contenant vos dossiers d'activité - chacun devient un album pour cette
  année, structure et sous-dossiers imbriqués recréés automatiquement.
  Déposer directement un ou plusieurs dossiers d'activité (sans les
  regrouper dans un dossier "Année") fonctionne aussi - l'année est
  demandée une seule fois pour tout le lot.
- Dans un album déjà ouvert : déposez plusieurs dossiers d'activité pour
  qu'ils deviennent chacun un sous-dossier, importé récursivement.

## 4octies. Activer la Bibliothèque (livres et documents consultables en ligne)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase16-bibliotheque.sql`, copiez tout son
   contenu, collez-le, cliquez **Run**

La Bibliothèque réutilise le système généraliste "contenu réservé"
(`restricted_articles` + bucket `documents-reserves`, cf. section 4quater)
avec une nouvelle catégorie `bibliotheque` : la migration ne fait qu'élargir
la contrainte `restricted_articles_category_check`, aucune nouvelle policy
RLS n'est nécessaire (la policy existante s'applique déjà à toute valeur de
`category`). Comme les Documents officiels, elle est donc gouvernée par
`is_active_member()` : accès coupé si la carte est expirée depuis plus de
2 mois.

La Bibliothèque a son propre panneau d'administration, isolé du panneau
générique "Contenu réservé" : `membres/bibliotheque-admin.html` (accessible
depuis la carte "Bibliothèque" du Centre d'administration), pour publier un
livre ou un document PDF (image de couverture facultative, fichier PDF
obligatoire). Les membres consultent la liste sur `membres/bibliotheque.html`,
accessible depuis une carte dédiée sur `membres/formations.html` : le PDF
s'affiche dans un lecteur en ligne (URL signée à courte durée de vie, barre
d'outils masquée) sans possibilité de téléchargement, comme pour les
Documents officiels. `membres/contenu-reserve-admin.html` ne gère plus que
Formation/Réalisation/Document officiel.

Le tableau de bord (`membres/index.html`) affiche aussi désormais un fil
"Activité récente" (derniers sujets du Forum, derniers albums Médiathèque
publiés, dernières Formations/Documents ajoutés), en 3-4 cartes cliquables
triées par date.

Les contenus de la Bibliothèque sont classés par section thématique
(colonne `bib_section`, cf. `supabase/phase17-bibliotheque-sections.sql`) :
Islam, Médecine, Pharmacie, Odontologie, Soins infirmiers et obstétricaux,
Entrepreneuriat, Développement personnel, Autres. Choisissez la section au
moment de publier un livre/document dans `bibliotheque-admin.html` ;
`membres/bibliotheque.html` regroupe l'affichage sous ces sections (une
section n'apparaît que si elle contient au moins un contenu publié).

## 4novies. Corriger la Boutique et activer les photos multiples (carousel)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase18-boutique-photos.sql`, copiez tout son
   contenu, collez-le, cliquez **Run**

Le formulaire admin de la Boutique utilisait des noms de colonnes qui
n'ont jamais existé (`price`, `is_active`, `total`, `delivery_address`,
`note`) au lieu des vraies colonnes créées en Phase 4D
(`price_fcfa`, `is_published`, `total_fcfa`, `shipping_address`, `notes`) :
tout enregistrement échouait avec une erreur "column not found". Corrigé
dans `membres/boutique-admin.html` et `membres/boutique.html`, sans
changement de schéma pour cette partie. La migration corrige en plus deux
points liés : la contrainte figée sur `products.category` (qui rejetait
toute catégorie hors d'une liste de 4 valeurs, alors que le champ admin est
un texte libre) est supprimée, et `products.stock` devient nullable (le
champ "laisser vide = illimité" plantait sinon, `stock` étant NOT NULL).

La migration ajoute aussi une table `product_photos` (plusieurs photos par
produit, comme `media_photos` pour la Médiathèque) et un bucket Storage
`boutique-photos` (privé, accès par URL signée, même schéma que
`mediatheque-photos`). L'ancien champ "URL de l'image" est remplacé dans
`boutique-admin.html` par un envoi de fichiers (plusieurs photos par
produit, redimensionnées côté client avant envoi, supprimables
individuellement). Côté membre, `membres/boutique.html` affiche désormais
un carousel (flèches + puces) au clic sur la photo d'un produit, pour
parcourir toutes ses vues comme sur un site marchand.

## 4decies. Corriger "The object exceeded the maximum allowed size"

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase19-storage-file-size-limits.sql`, copiez
   tout son contenu, collez-le, cliquez **Run**

Aucun des buckets créés jusqu'ici (`documents-reserves`, `mediatheque-photos`,
`boutique-photos`, `member-photos`) ne définissait `file_size_limit` :
Supabase retombait sur la limite par défaut du projet, trop basse pour un
PDF de livre/document un peu volumineux (erreur visible dans
`contenu-reserve-admin.html` / `bibliotheque-admin.html` à l'envoi du
fichier). La migration fixe une limite explicite par bucket (50 Mo pour les
documents/PDF, 10 Mo pour les photos, 5 Mo pour la photo de profil). Si
l'erreur persiste après cette migration pour un fichier plus gros que ces
limites, il faut aussi relever la limite globale du projet dans le Dashboard
Supabase (**Project Settings → Storage → Global file size limit**), qui
plafonne toute limite définie au niveau d'un bucket.

## 4undecies. Corriger l'onglet Commandes de la Boutique (relation manquante)

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase20-orders-fk-profiles.sql`, copiez tout
   son contenu, collez-le, cliquez **Run**

Le panneau `boutique-admin.html` (onglet Commandes) affichait "Aucune
commande" ou l'erreur "Could not find a relationship between 'orders' and
'user_id' in the schema cache", même quand des commandes existaient bien en
base. Cause : `orders.user_id` référençait `auth.users(id)` au lieu de
`public.profiles(id)` (contrairement à toutes les autres tables de paiement
du site), donc PostgREST ne pouvait pas résoudre l'affichage du nom/e-mail
du membre. La migration corrige la clé étrangère sans toucher aux données.

## 4duodecies. Corriger la durée de lecture des leçons Médical

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase21-medical-lessons-duration.sql`, copiez
   tout son contenu, collez-le, cliquez **Run**

Le formulaire "Nouvelle leçon" de `medical-admin.html` affichait l'erreur
"Could not find the 'duration_min' column of 'medical_lessons' in the
schema cache" à l'enregistrement. Cause : `medical_lessons` n'a jamais eu
cette colonne, contrairement à ses tables soeurs `daara_courses` et
`quizzes` qui l'ont depuis leur création (phase4-nouveaux-modules.sql) - un
oubli lors de la création de la table. La migration ajoute la colonne
manquante.

## 4terdecies. Ajouter le téléphone (WhatsApp) à l'inscription

1. Dans Supabase → **SQL Editor** → **New query**
2. Ouvrez le fichier `supabase/phase22-inscription-telephone.sql`, copiez
   tout son contenu, collez-le, cliquez **Run**

Le formulaire `membres/inscription.html` demande désormais un numéro de
téléphone (WhatsApp), obligatoire. Le trigger `handle_new_user()`
(schema.sql, Phase 1) ne recopiait que le nom complet depuis les métadonnées
d'inscription vers `profiles` : la migration le met à jour pour recopier
aussi le téléphone (la colonne `profiles.phone` existe déjà depuis Phase 4,
éditable ensuite via `profil.html`). Les mots de passe de `connexion.html`
et `inscription.html` ont aussi un bouton œil pour les afficher/masquer.

## 4quaterdecies. Notifier l'admin par e-mail (inscription, réclamation de carte, achat boutique, nouveau sujet forum)

Contrairement aux phases précédentes, cette étape ne se limite pas à coller
un fichier SQL : elle introduit une **fonction Edge Supabase** (jamais
utilisée jusqu'ici sur ce projet) et nécessite un compte chez un service
d'envoi d'e-mails. Suivez les étapes dans l'ordre.

1. **Créer un compte sur [resend.com](https://resend.com)**, puis
   Dashboard → **API Keys** → **Create API Key**. Copiez la clé (elle n'est
   affichée qu'une seule fois).
2. Tant que le domaine `amstc.org` n'est pas vérifié dans Resend
   (Domains → Add Domain → ajout d'enregistrements DNS SPF/DKIM chez votre
   registrar), les e-mails ne peuvent partir que depuis l'adresse de test
   `onboarding@resend.dev`, et **uniquement vers l'adresse e-mail de votre
   propre compte Resend** - pas vers `contact@amstc.org` ni aucune autre
   adresse. Pour tester avant la vérification du domaine, utilisez donc
   temporairement votre propre adresse comme destinataire (étape 6).
3. (Recommandé) Générez un jeton aléatoire pour servir de secret partagé -
   n'importe quel générateur de mot de passe long fera l'affaire. Notez-le,
   il sert à la fois à l'étape 6 et à l'étape 7.
4. **Déployer la fonction Edge** : Dashboard Supabase → **Edge Functions** →
   "Deploy a new function" → "Via Editor" → nommez-la exactement
   `notify-admin` → collez le contenu de
   `supabase/functions/notify-admin/index.ts` → **Deploy**.
5. Sur la page de la fonction `notify-admin`, onglet **Details** :
   désactivez le bouton **"Verify JWT"** - indispensable, sinon les appels
   du trigger SQL (via `pg_net`, qui ne fournit pas de session utilisateur)
   sont rejetés avant même d'atteindre le code.
6. Allez dans **Project Settings → Edge Functions → Secrets** (les secrets
   sont partagés par toutes les fonctions du projet) et ajoutez :
   - `RESEND_API_KEY` - la clé de l'étape 1
   - `ADMIN_NOTIFY_EMAIL` - l'adresse qui recevra les notifications (voir
     la limite de l'étape 2 tant que le domaine n'est pas vérifié)
   - `NOTIFY_ADMIN_SECRET` - le jeton de l'étape 3 (si vous l'utilisez)
   - `NOTIFY_FROM_EMAIL` - optionnel, adresse d'expédition (laissez vide
     pour garder `onboarding@resend.dev`)
7. Ouvrez `supabase/phase25-notifications-admin.sql` **dans votre éditeur
   local** (ne pas le renvoyer sur GitHub avec cette modification), et
   remplacez `REMPLACEZ_PAR_VOTRE_JETON` par la même valeur que
   `NOTIFY_ADMIN_SECRET` - c'est uniquement la copie collée dans le SQL
   Editor de Supabase qui doit contenir le vrai jeton, jamais le fichier
   du dépôt public (ou laissez `REMPLACEZ_PAR_VOTRE_JETON` tel quel dans
   les deux si vous n'utilisez pas ce contrôle).
8. Dans Supabase → **SQL Editor** → **New query**, collez le contenu du
   fichier (avec le jeton remplacé), cliquez **Run**.
9. **Testez** les 4 parcours (inscription, réclamation d'une carte, achat
   en boutique, nouveau sujet de forum) et vérifiez la réception de
   l'e-mail. En cas d'échec : Edge Functions → `notify-admin` → **Logs**
   (erreurs du code) et Resend → **Emails** (statut de livraison).

Un échec d'envoi (Resend indisponible, secret manquant...) ne bloque
jamais l'action du membre : l'inscription, la réclamation, l'achat ou le
sujet de forum sont enregistrés normalement même si la notification échoue
- seul l'e-mail à l'admin ne part pas, et l'erreur reste visible dans les
logs de la fonction Edge.

## 4quindecies. Protéger le Forum, les Enseignements Médicaux, la Bibliothèque et la Boutique contre l'aspiration en masse

**Contexte** : ces 4 pages chargent leur liste complète en une seule
requête, sans pagination côté client. N'importe quel compte membre (même
tout juste créé) peut donc appeler l'API Supabase directement et récupérer
tout le contenu en un clic, en contournant l'interface du site. Ce n'est
pas une faille RLS - "un membre approuvé peut lire le contenu publié" est
un choix voulu - mais l'absence de toute limite de volume permet de
transformer "consulter" en "aspirer tout d'un coup".

`supabase/phase26-rpc-listes-limitees.sql` ajoute 6 fonctions RPC
(`forum_topics_list`, `published_medical_lessons`, `published_quizzes`,
`bibliotheque_documents`, `published_products`,
`published_product_photos`) qui plafonnent le nombre de lignes renvoyées
côté serveur (entre 100 et 1000 lignes selon la table), indépendamment de
ce que demande le client. Les 4 pages concernées (`forum.html`,
`medical.html`, `bibliotheque.html`, `boutique.html`) ont été mises à jour
pour appeler ces fonctions au lieu d'interroger les tables directement.

Portée volontairement limitée à ces 4 pages de liste "grand public" : les
pages de détail (un sujet, une leçon, un quiz) et les panneaux d'admin
continuent d'interroger les tables directement, car ils ont besoin d'un
accès complet et ne présentent pas le même risque d'aspiration en masse.

1. Dans Supabase → **SQL Editor** → **New query**, collez le contenu de
   `supabase/phase26-rpc-listes-limitees.sql`, cliquez **Run**.
2. **Testez** les 4 pages (Forum, Enseignements Médicaux, Bibliothèque,
   Boutique) : elles doivent afficher leur contenu exactement comme avant.

**Complément recommandé (aucun code à écrire)** : dans Supabase → **Project
Settings** → **Data API**, le réglage **Max Rows** plafonne *toute* réponse
de l'API REST, y compris un appel direct sur les tables elles-mêmes (donc
même en contournant les fonctions RPC ci-dessus). Une valeur autour de
200-500 est large pour la taille actuelle de l'association tout en
bloquant un export massif en un seul appel. Pendant que vous y êtes,
désactivez aussi **"Automatically expose new tables"** : ça évite qu'une
future table soit exposée à l'API avant que ses policies RLS n'aient été
définies.

## 4sexdecies. Limiter le nombre d'appels par membre (rate limiting)

**Contexte** : la Phase 4quindecies plafonne le volume d'*un* appel
(LIMIT), mais rien n'empêche un compte d'appeler la même fonction en
boucle pour reconstituer tout le contenu au fil du temps.
`supabase/phase27-rate-limiting-rpc.sql` ajoute une limite de fréquence :
30 appels toutes les 5 minutes par membre et par fonction (Forum,
Enseignements Médicaux, Bibliothèque, Boutique) - très large pour un usage
normal (une poignée de chargements de page), mais qui bloque un script en
boucle. Au-delà, l'appel échoue avec le message "Trop de requêtes.
Réessayez dans quelques minutes." affiché directement sur la page
concernée.

Les appels autorisés sont journalisés dans une nouvelle table
`rpc_rate_limit_log`, sans aucune policy RLS créée dessus : elle est donc
inaccessible en lecture/écriture directe pour tout le monde, seule la
fonction `check_rate_limit` (SECURITY DEFINER) y touche.

1. Dans Supabase → **SQL Editor** → **New query**, collez le contenu de
   `supabase/phase27-rate-limiting-rpc.sql` (après avoir exécuté
   phase26-rpc-listes-limitees.sql), cliquez **Run**.
2. **Testez** les 4 pages : elles doivent continuer à afficher leur
   contenu normalement pour un usage courant.

## 4septdecies. Annuaire des membres (`membres/annuaire.html`)

**Contexte** : recherche/filtre par nom, ville, domaine et spécialité
parmi les membres approuvés, réservé à l'espace membres (pas de page
publique) - aucun membre n'ayant explicitement consenti à rendre son nom
et sa ville publics sur Internet.

`supabase/phase28-annuaire-membres.sql` ajoute une fonction RPC
`member_directory()` (SECURITY DEFINER, même plafond LIMIT + limite de
fréquence que les autres listes - voir Phase 4quindecies/4sexdecies)
qui n'expose qu'un sous-ensemble de colonnes de `profiles` : titre, nom,
domaine, spécialité, ville, photo, téléphone (voir Phase 4duodevicies
ci-dessous). **Jamais l'e-mail, le rôle ou le statut de carte.** Aucune
policy RLS n'est modifiée sur `profiles` - les membres continuent de ne
voir que leur propre ligne en direct, seule cette fonction dédiée expose
la liste complète.

1. Dans Supabase → **SQL Editor** → **New query**, collez le contenu de
   `supabase/phase28-annuaire-membres.sql` (après avoir exécuté
   phase27-rate-limiting-rpc.sql), cliquez **Run**.
2. **Testez** `membres/annuaire.html` : la recherche et les filtres par
   domaine doivent fonctionner, et aucun champ sensible (e-mail) ne doit
   apparaître.

## 4duodevicies. Ajoute le téléphone à l'annuaire (lien WhatsApp)

**Décision de l'association** : l'annuaire reste réservé à l'espace
membres (jamais public), donc afficher le téléphone (déjà fourni par
chaque membre à l'inscription, voir Phase 4terdecies) aux autres membres
approuvés reste raisonnable pour un annuaire professionnel interne. Le
numéro s'affiche comme un lien WhatsApp cliquable
(`supabase/phase29-annuaire-telephone.sql`), toujours sans policy RLS
supplémentaire ni changement du plafond/limite de fréquence.

1. Dans Supabase → **SQL Editor** → **New query**, collez le contenu de
   `supabase/phase29-annuaire-telephone.sql` (après avoir exécuté
   phase28-annuaire-membres.sql), cliquez **Run**.
2. **Testez** `membres/annuaire.html` : chaque fiche membre doit afficher
   un lien WhatsApp cliquable vers son numéro.

## 4undevicies. Diffusion WhatsApp aux membres

Un admin peut envoyer une alerte WhatsApp (ex : nouvelle campagne de
consultations) depuis `membres/whatsapp-admin.html`, en un clic depuis le
Centre d'administration - soit à **tous** les membres approuvés ayant
renseigné un numéro de téléphone, soit ciblée sur une audience précise :
**carte expirée** (jamais réglée ou expirée depuis une année précédente),
**carte à renouveler bientôt** (valide jusqu'au 31 décembre de l'année en
cours) ou **cotisation du mois en cours impayée** (uniquement pour les membres à
carte valide - un membre à carte expirée reçoit le rappel "carte expirée"
à la place). Comme pour la
Phase 4quaterdecies (e-mail), ceci introduit une nouvelle fonction Edge et
nécessite un compte chez un service tiers - ici la **Meta Cloud API**
(WhatsApp Business Platform), gratuite avec un quota généreux.

**Point important à comprendre avant de commencer** : une entreprise ne
peut PAS envoyer de message WhatsApp libre à quelqu'un qui ne lui a pas
écrit dans les 24h précédentes - il faut obligatoirement passer par un
**modèle de message ("template") pré-approuvé par WhatsApp**, avec une
variable pour le texte de l'annonce. La validation d'un modèle par Meta
prend généralement de quelques minutes à quelques heures.

1. **Créer un compte Meta for Developers** sur
   [developers.facebook.com](https://developers.facebook.com), créer une
   "Business App", puis ajouter le produit **WhatsApp** à l'app.
2. Dans la configuration WhatsApp de l'app, notez le **Numéro de
   téléphone de test** (ou ajoutez/vérifiez votre propre numéro
   professionnel) : vous obtenez un **Phone Number ID**.
3. Générez un **jeton d'accès permanent** (Meta Business Manager → System
   Users → créer un utilisateur système → générer un token avec la
   permission `whatsapp_business_messaging`). Le jeton temporaire fourni
   par défaut expire en 24h - utilisez un jeton permanent pour que la
   diffusion continue de fonctionner sans y retoucher chaque jour.
4. Dans **WhatsApp Manager → Modèles de messages**, créez **deux** modèles
   (Meta classe automatiquement le contenu et refuse un modèle Utilitaire
   si le texte ressemble à de la promotion - d'où la séparation en deux) :

   **a) `nouvelle_annonce`** (catégorie **Marketing**, utilisé pour
   l'audience "Tous les membres" - annonces d'événements/campagnes) :
   - Langue : Français · Type de variable : **Nom** (texte libre, pas
     "Valeur numérique")
   - Corps :
     ```
     Bonjour,

     {{message}}

     Plus d'infos sur amstc.org

     ©AMSTC
     ```
   - Exemple pour `{{message}}` : `Nouvelle campagne de consultations
     gratuites ce samedi à Ouakam, de 9h à 16h`
   - Si Meta bloque avec "La catégorie ne correspond pas" en proposant
     Marketing, acceptez sa recommandation.

   **b) `rappel_compte`** (catégorie **Utilitaire**, utilisé pour les 3
   audiences de rappel - carte expirée/à renouveler/cotisation impayée) :
   - Langue : Français · Type de variable : **Nom**
   - Corps :
     ```
     Bonjour,

     {{message}}

     Merci de régulariser votre situation sur amstc.org

     ©AMSTC
     ```
   - Exemple pour `{{message}}` : `Votre carte de membre 2025 a expiré -
     merci de la renouveler avant le 1er mars.` (un exemple qui ressemble
     à une notification de compte, pas à une annonce, aide à passer la
     catégorie Utilitaire sans blocage)

   Notez bien : le nom de la variable (`message`) doit être en minuscules
   avec des tirets bas uniquement, et ne peut pas se trouver en tout début
   ou toute fin du corps du message - Meta l'exige entouré de texte fixe.
   Soumettez les deux modèles et attendez le statut "Approuvé" pour chacun.
5. **Déployer la fonction Edge** : Dashboard Supabase → **Edge Functions**
   → "Deploy a new function" → "Via Editor" → nommez-la exactement
   `notify-members-whatsapp` → collez le contenu de
   `supabase/functions/notify-members-whatsapp/index.ts` → **Deploy**.
   Contrairement à `notify-admin`, **laissez le bouton "Verify JWT"
   activé** : cette fonction est appelée directement depuis le navigateur
   avec la session de l'admin connecté, pas depuis un trigger SQL.
6. Dans **Project Settings → Edge Functions → Secrets**, ajoutez :
   - `META_WHATSAPP_TOKEN` - le jeton permanent de l'étape 3
   - `META_PHONE_NUMBER_ID` - l'identifiant de l'étape 2
   - `META_TEMPLATE_NAME` - optionnel, si différent de `nouvelle_annonce`
   - `META_TEMPLATE_NAME_RAPPEL` - optionnel, si différent de `rappel_compte`
   - `META_TEMPLATE_LANG` - optionnel, si différent de `fr`
7. Dans Supabase → **SQL Editor** → **New query**, collez le contenu de
   `supabase/phase30-whatsapp-broadcasts.sql`, cliquez **Run**, puis faites
   de même avec `supabase/phase31-whatsapp-rappels-cibles.sql` (ajoute les
   fonctions de ciblage par audience - carte expirée/à renouveler/
   cotisation impayée).
8. **Testez** depuis `membres/whatsapp-admin.html` (Centre
   d'administration → carte "Diffusion WhatsApp") : choisissez une
   audience, le nombre de destinataires affiché doit se mettre à jour, et
   l'historique en bas de page doit se remplir après envoi (avec
   l'audience utilisée). En cas d'échec : Edge Functions →
   `notify-members-whatsapp` → **Logs**, et le détail des échecs
   individuels s'affiche aussi directement dans la page après l'envoi.

Comme pour les notifications e-mail, un échec d'envoi à un membre
n'empêche jamais l'envoi aux autres - chaque échec est simplement listé
séparément, et le nombre de succès est journalisé dans
`whatsapp_broadcasts` pour garder une trace de chaque diffusion. La
fonction Edge choisit automatiquement le bon modèle selon l'audience -
`nouvelle_annonce` pour "Tous les membres", `rappel_compte` pour les 3
audiences de rappel - seul le texte tapé dans la variable `{{message}}`
change à chaque envoi.

## 4vicies. Dupliquer une fiche & consulter l'historique des versions

Deux améliorations pour l'édition de contenu via Decap CMS (Réalisations,
Formations, Projets, Étapes) :

**Dupliquer une fiche** - déjà disponible nativement, aucune installation
nécessaire. En ouvrant une fiche existante dans `admin/index.html`, le
menu déroulant à côté du bouton d'enregistrement/publication propose une
option **"Dupliquer"** : elle crée un nouveau brouillon pré-rempli avec le
même contenu, à ajuster (nouvelle date, texte mis à jour) avant de
publier. Pratique pour les éditions annuelles récurrentes (Ndogou Social,
Gamou, JSSCI...).

**Historique des versions** (`admin/historique.html`) - panneau qui
liste l'historique Git d'une fiche (dates, messages de commit) et permet
de prévisualiser ou restaurer une ancienne version, sans passer par
GitHub directement :
1. Ouvrez d'abord `admin/index.html` et connectez-vous avec GitHub (ceci
   place un jeton dans le stockage local du navigateur).
2. Ouvrez ensuite `admin/historique.html` (accessible aussi depuis
   `membres/admin.html` → bloc "Contenu public du site" → lien
   "Historique des versions") dans le **même navigateur**.
3. Choisissez une collection puis une fiche : l'historique Git s'affiche,
   avec un bouton **"Voir"** par ancienne version (aperçu du contenu brut
   markdown/frontmatter) et un bouton **"Restaurer cette version"** qui
   crée un nouveau commit ramenant le fichier à cet état (rien n'est
   jamais réécrit dans l'historique Git existant - c'est toujours un
   commit en avant, donc réversible à son tour).

Aucune installation ni secret requis : cette page réutilise directement
le jeton GitHub déjà stocké par Decap CMS dans le navigateur au moment de
la connexion - le même mécanisme que Decap CMS utilise lui-même en
interne pour ses propres appels à l'API GitHub.

## 4unvicies. Annonces épinglées pour les membres

Permet à un administrateur de publier des annonces vues par tous les
membres à chaque connexion (ex. rappel d'événement, changement important),
sans dépendre d'un canal externe (e-mail, WhatsApp) que tout le monde ne
consulte pas forcément.

**Mise en place** : exécuter `supabase/phase32-annonces-membres.sql` dans
le SQL Editor (après `schema.sql` et `phase2-roles.sql`). Aucun secret ni
service tiers requis.

**Utilisation** :
1. Un administrateur crée une annonce depuis `membres/annonces-admin.html`
   (accessible depuis `membres/admin.html` → carte "Annonces") : titre,
   message, et une case à cocher "Épingler".
2. Au plus **3 annonces** peuvent être épinglées en même temps - la
   limite est vérifiée à la fois côté interface et côté base (un trigger
   Postgres refuse l'épinglage d'une 4e annonce).
3. Toute annonce épinglée et active s'affiche dans une fenêtre modale au
   chargement de `membres/index.html` (le tableau de bord), à **chaque**
   connexion - elle n'est jamais mémorisée comme "déjà vue", pour qu'un
   membre ne puisse pas la manquer même après plusieurs visites.
4. Désépingler, désactiver (masquer sans supprimer) ou supprimer une
   annonce se fait depuis la même page admin.

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
- Forum de discussion entre membres (sujets + réponses), sans lien avec
  la validité de la carte (voir Phase 4sexies ci-dessus)
- Médiathèque : galerie photo Année > Dossier d'activité > Photos, avec
  import par glisser-déposer ou dossier entier côté admin (voir Phase
  4septies ci-dessus)
- Notification par e-mail de l'admin à chaque inscription, réclamation de
  carte, achat en boutique ou nouveau sujet de forum, via une fonction
  Edge Supabase + Resend (voir Phase 4quaterdecies ci-dessus)
- Listes du Forum, des Enseignements Médicaux, de la Bibliothèque et de la
  Boutique plafonnées côté serveur via des fonctions RPC, contre
  l'aspiration en masse du contenu (voir Phase 4quindecies ci-dessus)
- Limite de fréquence (30 appels / 5 minutes par membre) sur ces mêmes
  fonctions RPC, contre un compte qui boucle les appels (voir Phase
  4sexdecies ci-dessus)
- Annuaire des membres, recherche/filtre par nom, ville, domaine et
  spécialité, réservé à l'espace membres (voir Phase 4septdecies
  ci-dessus)

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
