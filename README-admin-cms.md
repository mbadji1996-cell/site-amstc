# Configurer l'interface d'administration (amstc.org/admin)

Vous avez déjà Cloudflare pour le DNS — on va aussi l'utiliser pour l'authentification, pas besoin d'ouvrir de compte Vercel.

Le nom du dépôt (`mbadji1996-cell/site-amstc`) est déjà renseigné dans tous les fichiers — passez directement à l'étape 1.

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

## Limite à connaître

Les listes d'articles (page d'accueil + actualites.html) utilisent l'API publique de GitHub pour lister les fichiers, sans authentification. Elle est limitée à 60 requêtes/heure par visiteur — largement suffisant pour un site associatif, mais à garder en tête si le trafic grossit beaucoup. Si besoin plus tard, on pourra passer par une build statique (Eleventy/Hugo) qui génère les pages à l'avance.
