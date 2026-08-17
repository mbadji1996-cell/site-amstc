# Configurer l'interface d'administration (amstc.org/admin)

Vous avez déjà Cloudflare pour le DNS - on va aussi l'utiliser pour l'authentification, pas besoin d'ouvrir de compte Vercel.

Le nom du dépôt (`mbadji1996-cell/site-amstc`) est déjà renseigné dans tous les fichiers - passez directement à l'étape 1.

## 1. Créer une application OAuth sur GitHub

1. Allez sur [github.com/settings/developers](https://github.com/settings/developers) → **OAuth Apps** → **New OAuth App**
2. Remplissez :
   - **Application name** : AMSTC Admin
   - **Homepage URL** : `https://amstc.org`
   - **Authorization callback URL** : laissez temporairement `https://amstc.org` (on la corrigera à l'étape 3)
3. **Register application**
4. Notez le **Client ID**, puis cliquez **Generate a new client secret** et notez le **Client Secret** (il ne sera plus jamais affiché en entier)

## 2. Déployer le proxy d'authentification sur Cloudflare Workers

1. Allez sur [github.com/sterlingwes/decap-proxy](https://github.com/sterlingwes/decap-proxy) et cliquez **Fork** (en haut à droite) pour le copier sur votre propre compte GitHub
2. Dans le tableau de bord Cloudflare → **Compute (Workers)** → **Workers & Pages** → **Create** → **Import a repository**
3. Connectez votre compte GitHub si demandé, puis sélectionnez le dépôt `decap-proxy` que vous venez de forker
4. Laissez les réglages par défaut et cliquez **Deploy**
5. Une fois déployé, notez l'URL du Worker (ex. `https://decap-proxy.VOTRE-SOUS-DOMAINE.workers.dev`)
6. Dans les réglages du Worker → **Settings → Variables and Secrets**, ajoutez deux secrets :
   - `GITHUB_OAUTH_ID` = le Client ID noté à l'étape 1
   - `GITHUB_OAUTH_SECRET` = le Client Secret noté à l'étape 1
7. Redéployez le Worker si demandé pour que les secrets prennent effet

## 3. Finaliser l'application OAuth GitHub

Retournez dans **Settings → Developer settings → OAuth Apps → AMSTC Admin**, et changez :
- **Authorization callback URL** : `https://decap-proxy.VOTRE-SOUS-DOMAINE.workers.dev/callback`

## 4. Mettre à jour `admin/config.yml`

Remplacez la ligne `base_url` par l'URL de votre Worker (sans `/callback`) :

```yaml
base_url: https://decap-proxy.VOTRE-SOUS-DOMAINE.workers.dev
auth_endpoint: auth
```

## 5. Pousser les fichiers sur GitHub

Ajoutez au dépôt (en plus de ce qui existe déjà) :
- `admin/index.html`
- `admin/config.yml`
- `content/home.json`
- `content/actualites/2026-07-13-bienvenue-sur-notre-nouveau-site.md`
- `actualites.html`
- `article.html`
- `index.html` (mis à jour)

## 6. Tester

Allez sur `https://amstc.org/admin`, cliquez **Login with GitHub**, autorisez l'application. Vous devriez arriver sur l'interface d'édition avec deux sections : **Page d'accueil** (textes) et **Actualités** (articles).

## Ce qui est déjà éditable

- Accroche, titre et sous-titre du hero
- Les deux paragraphes de la section "Notre mission"
- Publication/édition/suppression d'articles dans "Actualités", affichés automatiquement sur la page d'accueil (3 derniers) et sur `actualites.html`

## Importer un fichier HTML complet

Un article, une formation, un projet ou une étape peut être publié à partir d'une **page HTML rédigée ailleurs** - avec sa mise en page, ses encadrés, ses tableaux et ses images encodées. Ouvrez `admin/importer.html` (bouton « Importer un fichier HTML » dans la barre de Decap, ou lien depuis le Centre d'administration), déposez le fichier, vérifiez l'aperçu, publiez.

Ce que fait l'import (`assets/js/import-html.js`) :

- **titre et résumé** proposés depuis `<title>` et le premier paragraphe ;
- **style conservé mais confiné** : les règles du fichier ne s'appliquent qu'au contenu importé, jamais à la barre du site ni au pied de page ; les polices externes (`@import`, `@font-face`) sont écartées ;
- **scripts, iframes, formulaires et gestionnaires `on…` retirés** - rien du fichier n'est exécuté ;
- **images encodées extraites** en fichiers dans `assets/uploads/importes/<slug>/`, la première pouvant servir de couverture. Les images en chemin relatif sont signalées : elles ne s'afficheraient pas.

La fiche est déposée dans le dépôt comme n'importe quelle fiche Decap et se retouche ensuite dans l'administration (le corps y apparaît en HTML). Côté espace membres, les cours du Daara et les leçons médicales ont le même bouton dans leur formulaire, avec dépôt des images dans le bucket `couvertures/importes/`.

## Limite à connaître

Les listes d'articles (page d'accueil + actualites.html) utilisent l'API publique de GitHub pour lister les fichiers, sans authentification. Elle est limitée à 60 requêtes/heure par visiteur - largement suffisant pour un site associatif, mais à garder en tête si le trafic grossit beaucoup. Si besoin plus tard, on pourra passer par une build statique (Eleventy/Hugo) qui génère les pages à l'avance.

## Donner accès au CMS à d'autres personnes

Aucune configuration à changer : la connexion à amstc.org/admin passe par
GitHub, donc toute personne invitée sur le dépôt peut se connecter au CMS
avec son propre compte et publier directement. Chaque personne est
indépendante ; l'administrateur garde la supervision par l'historique
(chaque publication porte le nom de son auteur) et peut retirer un accès
à tout moment.

### Inviter une personne

1. La personne se crée un compte gratuit sur [github.com](https://github.com/signup)
   (elle n'a besoin de rien d'autre - elle ne touchera jamais à GitHub directement).
2. Vous, sur GitHub : dépôt `site-amstc` → **Settings** → **Collaborators**
   → **Add people** → son nom d'utilisateur ou son e-mail → rôle **Write**.
3. Elle reçoit un e-mail d'invitation et clique **Accept**.
4. Elle va sur **amstc.org/admin** → **Se connecter avec GitHub** → autorise
   l'application AMSTC Admin → elle peut créer et publier ses articles.

### Retirer un accès

Dépôt `site-amstc` → **Settings** → **Collaborators** → **Remove** en face
de son nom. Effet immédiat : sa prochaine action dans le CMS sera refusée.

### Suivre qui a publié quoi

- [github.com/mbadji1996-cell/site-amstc/commits/main](https://github.com/mbadji1996-cell/site-amstc/commits/main) :
  chaque publication est un commit signé du nom de son auteur.
- Pour annuler une publication : ouvrez le commit fautif → **Revert**, ou
  demandez à l'assistant de le faire.

### Limite à connaître

Le rôle **Write** donne accès en écriture à TOUT le dépôt, pas seulement
aux contenus du CMS : une personne invitée pourrait techniquement modifier
le code du site en passant par GitHub directement. Avec une petite équipe
de confiance c'est le compromis normal ; n'invitez que des personnes à qui
vous confieriez le site. Si un jour il faut un vrai cloisonnement (les
rédacteurs proposent, vous validez), le CMS a un mode « editorial
workflow » qui transforme leurs publications en brouillons à approuver -
demandez à l'assistant de l'activer.
