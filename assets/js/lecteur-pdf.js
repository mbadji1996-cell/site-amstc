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

  // ===== Aperçu intégré, précédé d'une barre de progression =====
  //
  // Un gros document laissait un écran noir sans le moindre signe le
  // temps du téléchargement. Le fichier est donc téléchargé PAR LA PAGE,
  // qui en voit passer les octets et peut afficher où en est le
  // chargement ; l'aperçu s'ouvre ensuite sur la copie locale, d'un
  // coup. En cas d'échec du téléchargement suivi (réseau, CORS), on
  // retombe sur le chargement direct d'origine plutôt que de priver de
  // lecture.
  viewer.innerHTML = `
    <div class="lecteur-attente" style="padding:48px 24px; text-align:center;">
      <div style="height:8px; max-width:420px; margin:0 auto; border-radius:99px;
                  background:rgba(127,127,127,0.18); overflow:hidden;">
        <div class="lecteur-barre-avancee" style="height:100%; width:0%; border-radius:99px;
             background:#F8B718; transition:width .25s ease;"></div>
      </div>
      <p class="${note}" style="margin-top:12px;">Chargement du document…
        <span class="lecteur-avancee-texte">0 %</span></p>
    </div>`;
  viewer.style.display = '';

  const barre = viewer.querySelector('.lecteur-barre-avancee');
  const texte = viewer.querySelector('.lecteur-avancee-texte');

  (async () => {
    let source = url;
    try {
      const reponse = await fetch(url);
      if (!reponse.ok || !reponse.body) throw new Error('telechargement refuse');
      const total = Number(reponse.headers.get('Content-Length')) || 0;
      const flux = reponse.body.getReader();
      const morceaux = [];
      let recu = 0;
      for (;;) {
        const { done, value } = await flux.read();
        if (done) break;
        // Document fermé pendant le chargement : on arrête de tirer des
        // octets pour rien.
        if (!barre.isConnected) { flux.cancel(); return; }
        morceaux.push(value);
        recu += value.length;
        if (total) {
          const pct = Math.min(100, Math.round((recu / total) * 100));
          barre.style.width = pct + '%';
          texte.textContent = pct + ' %';
        } else {
          // Taille inconnue : la barre avance en se tassant, le texte
          // donne les mégaoctets reçus - mieux qu'une barre figée.
          barre.style.width = Math.round((recu / (recu + 10 * 1048576)) * 100) + '%';
          texte.textContent = (recu / 1048576).toFixed(1) + ' Mo';
        }
      }
      // L'adresse locale ne périme pas, contrairement à l'adresse signée
      // (120 s) : l'onglet ouvert plus tard marchera encore.
      source = URL.createObjectURL(new Blob(morceaux, { type: 'application/pdf' }));
    } catch (e) {
      source = url;
    }
    // On ne remplace QUE le bloc d'attente : les pages ajoutent leur
    // barre de titre par-dessus l'aperçu, et réécrire tout le contenu
    // du visionneur l'aurait emportée - plus aucun moyen de fermer.
    const attente = viewer.querySelector('.lecteur-attente');
    if (!attente) {
      if (source !== url) URL.revokeObjectURL(source);
      return;
    }
    const s = lecteurEchapper(source);
    attente.insertAdjacentHTML('beforebegin', `
      <iframe src="${s}#toolbar=0&amp;navpanes=0" title="Document"></iframe>
      <p class="${note}">Aperçu en lecture seule -
        <a href="${s}" target="_blank" rel="noopener">ouvrir dans un onglet</a></p>`);
    attente.remove();
  })();
}
