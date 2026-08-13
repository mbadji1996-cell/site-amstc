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
  return lecteurSurIOS() ? window.open('', '_blank') : null;
}

function lecteurEchapper(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// La bibliothèque n'accueille plus seulement des PDF : un Word, un
// tableur ou une image doivent s'ouvrir eux aussi. L'extension du chemin
// stocké suffit à décider - le type MIME renvoyé par le stockage est
// souvent « application/octet-stream » et ne dirait rien.
function lecteurExtension(chemin) {
  const nom = String(chemin == null ? '' : chemin).split(/[?#]/)[0];
  const point = nom.lastIndexOf('.');
  return point === -1 ? '' : nom.slice(point + 1).toLowerCase();
}

function lecteurEstImage(chemin) {
  return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'avif'].indexOf(lecteurExtension(chemin)) !== -1;
}

/**
 * Formats qu'aucun navigateur ne sait afficher.
 *
 * La liste est POSITIVE, et non « tout ce qui n'est pas un PDF » : un
 * chemin d'origine inconnue - extension absente, format inattendu -
 * garde ainsi l'aperçu intégré, le comportement qui existait avant
 * l'ouverture aux autres formats. Se tromper doit ramener à l'ancien
 * fonctionnement, jamais en dévier.
 */
function lecteurSansApercu(chemin) {
  return ['doc', 'docx', 'odt', 'rtf',
          'xls', 'xlsx', 'ods', 'csv',
          'ppt', 'pptx', 'odp',
          'epub'].indexOf(lecteurExtension(chemin)) !== -1;
}

/**
 * Remplit la zone d'affichage d'un document.
 *
 * @param viewer      l'élément qui reçoit l'aperçu
 * @param url         l'adresse signée du document
 * @param onglet      l'onglet réservé par lecteurPreouvrirOnglet(), ou null
 * @param classeNote  la classe CSS du texte sous l'aperçu
 * @param chemin      le chemin du fichier, pour reconnaître son format
 */
function lecteurAfficherPdf(viewer, url, onglet, classeNote, chemin) {
  const u = lecteurEchapper(url);
  const note = classeNote || 'lecteur-note';

  // Une image s'affiche telle quelle : la passer par un <iframe> la
  // montrerait sur fond blanc, sans mise à l'échelle.
  if (lecteurEstImage(chemin)) {
    if (onglet) onglet.close();
    viewer.innerHTML = `
      <img src="${u}" alt="" style="width:100%;height:auto;display:block;">
      <p class="${note}"><a href="${u}" target="_blank" rel="noopener">ouvrir dans un onglet</a></p>`;
    viewer.style.display = '';
    return;
  }

  // Un Word, un tableur ou une présentation ne s'affiche dans aucun
  // navigateur : proposer un aperçu vide ferait croire à une panne. On
  // donne le lien, qui ouvre ou télécharge selon l'appareil.
  if (lecteurSansApercu(chemin)) {
    if (onglet) { onglet.location = url; }
    viewer.innerHTML = `<p class="${note}">
      <a href="${u}" target="_blank" rel="noopener"><strong>Ouvrir le document</strong></a><br>
      Ce format ne s'affiche pas dans le navigateur : il s'ouvre dans l'application
      de votre appareil.</p>`;
    viewer.style.display = '';
    return;
  }

  if (lecteurSurIOS()) {
    if (onglet) {
      onglet.location = url;
      viewer.innerHTML = `<p class="${note}">Le document s'ouvre dans un nouvel onglet.
        Sur iPhone et iPad, un aperçu intégré n'afficherait que la première page.</p>`;
    } else {
      // Onglet bloqué malgré la réservation : on donne le lien à toucher
      // plutôt que de laisser la personne devant une zone vide.
      viewer.innerHTML = `<p class="${note}">
        <a href="${u}" target="_blank" rel="noopener"><strong>Ouvrir le document</strong></a><br>
        Sur iPhone et iPad, un aperçu intégré n'afficherait que la première page.</p>`;
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
