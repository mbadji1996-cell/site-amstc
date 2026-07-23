# site-amstc

## Rapport annuel des réalisations

`scripts/build-annual-report.js` agrège toutes les Réalisations d'une
année (depuis `content/actualites-index.json`) en une page de bilan prête
à imprimer ou exporter en PDF (bouton "Imprimer / Enregistrer en PDF" ->
impression navigateur, aucune dépendance requise).

**Option 1 - depuis GitHub, sans terminal (recommandé)** : onglet **Actions**
du dépôt → **Générer un bilan annuel** (menu de gauche) → bouton
**Run workflow** → saisir l'année (ex : `2025`) → **Run workflow**. Le
bilan est généré et poussé automatiquement sur `main` en quelques
secondes ; rechargez `rapports/index.html` sur le site pour le voir
apparaître.

**Option 2 - en local** :
```
node scripts/build-content-index.js   # si le contenu a changé depuis le dernier build
node scripts/build-annual-report.js 2025
```

Les deux méthodes génèrent `rapports/2025.html` et mettent à jour
`rapports/index.html`. Le script échoue avec un message clair si l'année
n'a aucune réalisation.