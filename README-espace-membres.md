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

## Ce qui est couvert pour l'instant (Phase 1)

- Inscription publique, avec validation manuelle par un administrateur
  avant tout accès
- Connexion, déconnexion, mot de passe oublié / réinitialisation
- Un espace membre minimal (page d'accueil réservée aux comptes
  approuvés)
- Une page d'administration pour approuver ou refuser les inscriptions

## Ce qui n'est pas encore fait

- La distinction fine entre **Administrateur** et **Super Administrateur**
  (droits de nomination/révocation des admins) - prévue pour une prochaine
  étape
- La création de comptes utilisateurs directement par un administrateur
  (pour l'instant, seule l'inscription publique existe)
- L'option Public / Réservé aux membres sur les articles de la rubrique
  Formation
