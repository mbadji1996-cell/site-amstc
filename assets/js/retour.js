/**
 * Liens « ← Retour » : revenir à la page PRÉCÉDENTE.
 *
 * Chaque page écrit sa cible de retour en dur - souvent le tableau de
 * bord. Résultat : depuis l'annuaire on ouvre un profil, on touche
 * « retour », et l'on atterrit sur le tableau de bord au lieu de
 * l'annuaire. Quand on est ARRIVÉ d'une autre page du site, le retour
 * refait donc le chemin inverse, comme le bouton du navigateur.
 *
 * La cible écrite en dur reste l'issue de secours : arrivée directe
 * (favori, lien partagé dans WhatsApp), rechargement de la page, ou
 * venue de l'écran de connexion - y retourner n'aurait aucun sens, il
 * renverrait aussitôt ici.
 */
document.addEventListener('click', function (e) {
  var lien = e.target && e.target.closest ? e.target.closest('a.back') : null;
  if (!lien) return;
  if (!document.referrer || history.length < 2) return;
  try {
    var origine = new URL(document.referrer);
    if (origine.origin !== location.origin) return;
    if (/connexion|inscription|mot-de-passe/.test(origine.pathname)) return;
    if (origine.pathname === location.pathname) return;
  } catch (err) { return; }
  e.preventDefault();
  history.back();
});
