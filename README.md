# site-amstc

## Rapport annuel des réalisations

`scripts/build-annual-report.js` agrège toutes les Réalisations d'une
année (depuis `content/actualites-index.json`) en une page de bilan prête
à imprimer ou exporter en PDF (bouton "Imprimer / Enregistrer en PDF" ->
impression navigateur, aucune dépendance requise).

```
node scripts/build-content-index.js   # si le contenu a changé depuis le dernier build
node scripts/build-annual-report.js 2025
```

Génère `rapports/2025.html`. Le script échoue avec un message clair si
l'année n'a aucune réalisation.