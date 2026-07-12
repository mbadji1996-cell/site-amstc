# Déploiement du site AMSTC sur GitHub Pages

## Fichiers
- `index.html` — page d'accueil complète
- `assets/logo-horizontal.png`, `assets/logo-mark.png` — logos officiels AMSTC
- `CNAME` — requis par GitHub Pages pour pointer amstc.org vers le site

Gardez la structure de dossiers telle quelle (assets/ à côté de index.html).

## Étapes
1. Placez `index.html`, `CNAME` et le dossier `assets/` à la racine du dépôt GitHub.
2. Settings > Pages : activez GitHub Pages sur la branche concernée.
3. Chez le registrar du domaine : CNAME `www` → `<compte>.github.io`, ou 4 enregistrements A vers 185.199.108.153 / .109.153 / .110.153 / .111.153.
4. Ajoutez `amstc.org` comme domaine personnalisé dans Settings > Pages, puis activez "Enforce HTTPS".

## Contenu déjà intégré (à partir de vos documents)
- Logos officiels et palette de couleurs réelle (#17763B, #06441C, #F8B718, #AA7B11)
- Mission reprise des Articles 5 et 6 des statuts (objet et objectifs)
- Moyens d'action repris de l'Article 7 des statuts
- Symbolique de l'emblème (Article 4 des statuts)
- Frise historique 2014–2024 basée sur l'historique de l'association
- Liste des membres fondateurs
- Organisation du Bureau Exécutif et des commissions (Article 31)
- Numéro de récépissé de déclaration (022909/MISP/DGAT/DLPL/DAPA) et siège social (Sacré Cœur 3, Villa N°9867, Dakar)

## Encore à compléter avant mise en ligne
- Téléphone de contact et liens réseaux sociaux (marqués `[à compléter]`)
- Pages légales `confidentialite.html` et `cgu.html` (à adapter depuis celles de la PWA)
- Éventuellement : ajouter des visuels de terrain (sans photo identifiable de mineur sans autorisation)

## Volontairement omis
Les numéros de téléphone personnels des membres du Bureau Exécutif (présents dans vos anciens documents internes) n'ont pas été publiés sur le site public. Si vous souhaitez un moyen de contact direct, je recommande une adresse e-mail ou un numéro dédié à l'association plutôt que les lignes personnelles des membres.
