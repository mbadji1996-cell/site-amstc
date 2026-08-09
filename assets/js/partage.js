/**
 * Bouton « Partager » commun aux fiches (articles, formations, cours…).
 *
 * POURQUOI un lien différent de celui de la barre d'adresse. Les fiches
 * sont servies par des pages paramétrées (`article.html?slug=…`) : sur un
 * hébergement statique, toutes ces adresses renvoient le même fichier, et
 * le robot de WhatsApp - qui n'exécute pas JavaScript - y lit toujours le
 * même titre générique. Une page d'aperçu est donc pré-générée pour
 * chaque fiche (voir scripts/build-pages-partage.js) ; c'est elle qu'il
 * faut partager pour que le titre exact apparaisse.
 *
 * Usage :
 *   partageInit({ conteneur: 'partageZone', prefixe: 'a', cle: 'slug' });
 *   partageInit({ conteneur: 'partageZone', prefixe: 'c', cle: 'id' });
 */

function partageAdresse(prefixe, cle) {
  const valeur = new URLSearchParams(location.search).get(cle);
  if (!valeur) return null;
  return location.origin + '/' + prefixe + '/' + encodeURIComponent(valeur) + '.html';
}

// Styles portés par ce fichier plutôt que par une feuille du site : le
// bouton apparaît sur des pages publiques et sur des pages membres, qui
// ne partagent pas les mêmes styles.
function partageStyles() {
  if (document.getElementById('partage-styles')) return;
  const s = document.createElement('style');
  s.id = 'partage-styles';
  s.textContent =
    '.partage-zone{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:28px 0 8px;}' +
    '.btn-partage{display:inline-flex;align-items:center;gap:8px;font-family:inherit;font-weight:600;' +
    'font-size:0.88rem;padding:10px 20px;border-radius:999px;cursor:pointer;' +
    'background:transparent;color:#17763B;border:1.5px solid rgba(6,68,28,0.2);transition:border-color .18s;}' +
    '.btn-partage:hover{border-color:#17763B;}' +
    '.partage-msg{font-family:ui-monospace,monospace;font-size:0.76rem;color:#8A9E8F;word-break:break-all;}';
  document.head.appendChild(s);
}

function partageInit(options) {
  const zone = document.getElementById(options.conteneur);
  if (!zone) return;
  partageStyles();
  const adresse = partageAdresse(options.prefixe, options.cle);
  if (!adresse) return;

  const bouton = document.createElement('button');
  bouton.type = 'button';
  bouton.className = 'btn-partage';
  bouton.innerHTML = '<i class="ti ti-share"></i> Partager';

  const message = document.createElement('span');
  message.className = 'partage-msg';
  message.setAttribute('role', 'status');

  bouton.addEventListener('click', async () => {
    const titre = document.title.replace(/\s*-\s*AMSTC.*$/, '').trim();

    // Sur téléphone, le menu natif propose directement WhatsApp : c'est le
    // chemin le plus court vers l'usage réel. navigator.share exige un
    // contexte sécurisé et un geste de l'utilisateur - d'où l'appel ici.
    if (navigator.share) {
      try {
        await navigator.share({ title: titre, url: adresse });
        return;
      } catch (e) {
        // Partage annulé par l'utilisateur : ne rien afficher.
        if (e && e.name === 'AbortError') return;
        // Tout autre échec bascule sur la copie ci-dessous.
      }
    }

    try {
      await navigator.clipboard.writeText(adresse);
      message.textContent = 'Lien copié';
    } catch (e) {
      // clipboard indisponible (page non sécurisée, navigateur ancien) :
      // on montre le lien pour que la personne le copie elle-même.
      message.textContent = adresse;
    }
    setTimeout(() => { message.textContent = ''; }, 4000);
  });

  zone.appendChild(bouton);
  zone.appendChild(message);
}
