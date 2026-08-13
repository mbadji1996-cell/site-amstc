/**
 * Affichage des PDF réservés (bibliothèque, documents officiels).
 *
 * LE PROBLÈME. iOS Safari n'affiche que la PREMIÈRE PAGE d'un PDF placé
 * dans un <iframe>. WebKit le rend comme une image unique : pas de
 * défilement, pas de pages suivantes, et rien ne le signale - le lecteur
 * croit simplement que le document fait une page. Aucun réglage CSS ni
 * paramètre d'URL n'y change quoi que ce soit.
 *
 * LA PARADE. Sur ces appareils, le document s'ouvre dans un onglet, où
 * le lecteur natif d'iOS le lit correctement, toutes pages comprises.
 * Ailleurs, l'aperçu intégré est conservé - il évite de quitter la page -
 * et un lien « ouvrir dans un onglet » sert d'issue de secours aux
 * navigateurs qui liraient mal le PDF.
 */

// iPadOS se présente comme un Mac depuis iOS 13 : l'agent utilisateur ne
// suffit plus, il faut y ajouter la présence d'un écran tactile.
function lecteurSurIOS() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
}

// Android Chrome ne rend pas non plus le PDF dans le cadre : il affiche
// un bouton « Ouvrir » qui imposait un DEUXIÈME clic avant la lecture -
// constaté sur le site. Même parade que pour iOS : l'onglet.
function lecteurSansApercuIntegre() {
  return lecteurSurIOS() || /Android/i.test(navigator.userAgent);
}

/**
 * Ouvre un onglet vide AVANT l'appel réseau, quand l'appareil en aura
 * besoin.
 *
 * Safari bloque comme intempestive toute fenêtre ouverte après une
 * attente réseau : elle doit naître dans la foulée du clic. Or l'adresse
 * signée n'est connue qu'après. On réserve donc l'onglet tout de suite,
 * et on l'envoie sur le document une fois l'adresse obtenue.
 */
function lecteurPreouvrirOnglet() {
  return lecteurSansApercuIntegre() ? window.open('', '_blank') : null;
}

function lecteurEchapper(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * Remplit la zone d'affichage d'un document.
 *
 * @param viewer      l'élément qui reçoit l'aperçu
 * @param url         l'adresse signée du PDF
 * @param onglet      l'onglet réservé par lecteurPreouvrirOnglet(), ou null
 * @param classeNote  la classe CSS du texte sous l'aperçu
 */
function lecteurAfficherPdf(viewer, url, onglet, classeNote) {
  const u = lecteurEchapper(url);
  const note = classeNote || 'lecteur-note';

  if (lecteurSansApercuIntegre()) {
    if (onglet) {
      onglet.location = url;
      viewer.innerHTML = `<p class="${note}">Le document s'ouvre dans un nouvel onglet.
        Sur téléphone et tablette, il se lit dans le lecteur de l'appareil.</p>`;
    } else {
      // Onglet bloqué malgré la réservation : on donne le lien à toucher
      // plutôt que de laisser la personne devant une zone vide.
      viewer.innerHTML = `<p class="${note}">
        <a href="${u}" target="_blank" rel="noopener"><strong>Ouvrir le document</strong></a><br>
        Sur téléphone et tablette, le document se lit dans le lecteur de l'appareil.</p>`;
    }
    viewer.style.display = '';
    return;
  }

  viewer.innerHTML = `
    <iframe src="${u}#toolbar=0&amp;navpanes=0" title="Document"></iframe>
    <p class="${note}">Aperçu en lecture seule -
      <a href="${u}" target="_blank" rel="noopener">ouvrir dans un onglet</a></p>`;
  viewer.style.display = '';
}
