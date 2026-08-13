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
 *   await partagerFiche('c', idDuCours, 'Titre');   // écrans d'administration
 *   await partageDeclencherConstruction();          // idem, admins seulement
 */

/**
 * Demande la construction immédiate des pages d'aperçu, sans attendre le
 * passage horaire.
 *
 * Les cours et les leçons vivent dans Supabase : aucune publication ne
 * déclenche de mise en ligne, et leur page d'aperçu n'est fabriquée qu'à
 * heure fixe. Cette fonction raccourcit l'attente à environ une minute.
 *
 * Réservée aux administrateurs, le contrôle étant fait par la fonction
 * serveur - le jeton GitHub ne peut pas descendre dans le navigateur.
 *
 * Renvoie { ok, message } à afficher, ou null quand il n'y a rien à dire
 * (visiteur non connecté, fonction non déployée, jeton non configuré) :
 * dans tous ces cas le passage horaire fait le travail, et une erreur
 * technique n'apprendrait rien à l'administration.
 */
async function partageDeclencherConstruction() {
  try {
    if (typeof supabaseClient === 'undefined' || typeof SUPABASE_URL === 'undefined') return null;
    const { data } = await supabaseClient.auth.getSession();
    const session = data && data.session;
    if (!session) return null;

    const reponse = await fetch(SUPABASE_URL + '/functions/v1/declencher-apercus', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + session.access_token,
        'Content-Type': 'application/json',
      },
    });
    const corps = await reponse.json().catch(() => ({}));
    if (reponse.ok && corps.ok) return { ok: true, message: corps.message };
    // 403 (pas admin), 501 (jeton absent), 404 (fonction non déployée) :
    // rien d'actionnable pour la personne devant l'écran.
    return null;
  } catch (e) {
    return null;
  }
}

// valeurExplicite sert aux écrans qui listent PLUSIEURS fiches : là,
// l'identifiant ne peut pas venir de la barre d'adresse, chaque ligne
// ayant la sienne.
function partageAdresse(prefixe, cle, valeurExplicite) {
  const valeur = (valeurExplicite !== undefined && valeurExplicite !== null && valeurExplicite !== '')
    ? String(valeurExplicite)
    : new URLSearchParams(location.search).get(cle);
  if (!valeur) return null;
  return location.origin + '/' + prefixe + '/' + encodeURIComponent(valeur) + '.html';
}

/**
 * La page d'aperçu existe-t-elle déjà ? Les fiches Supabase (cours,
 * leçons) n'ont leur page /c/<id>.html qu'après le passage horaire de
 * génération : partager avant, c'est envoyer un lien sans titre. En cas
 * de doute (réseau, environnement de test), on ne bloque pas le partage.
 */
async function partageDisponible(adresse) {
  try {
    const r = await fetch(adresse, { method: 'HEAD', cache: 'no-store' });
    return r.ok;
  } catch (e) {
    return true;
  }
}

/**
 * Partage une adresse : menu natif du téléphone si disponible, sinon
 * copie dans le presse-papiers.
 * Renvoie 'partage', 'annule', 'copie', ou l'adresse elle-même quand ni
 * l'un ni l'autre n'est possible (page non sécurisée, navigateur ancien).
 */
async function partagerAdresse(adresse, titre) {
  // Sur téléphone, le menu natif propose directement WhatsApp : c'est le
  // chemin le plus court vers l'usage réel. navigator.share exige un
  // contexte sécurisé et un geste de l'utilisateur - d'où l'appel ici.
  if (navigator.share) {
    try {
      await navigator.share({ title: titre, url: adresse });
      return 'partage';
    } catch (e) {
      if (e && e.name === 'AbortError') return 'annule';
      // Tout autre échec bascule sur la copie ci-dessous.
    }
  }
  try {
    await navigator.clipboard.writeText(adresse);
    return 'copie';
  } catch (e) {
    return adresse;
  }
}

/** Partage une fiche dont on connaît déjà l'identifiant. */
async function partagerFiche(prefixe, valeur, titre) {
  const adresse = partageAdresse(prefixe, null, valeur);
  if (!adresse) return null;
  return partagerAdresse(adresse, titre || document.title);
}

// Styles portés par ce fichier plutôt que par une feuille du site : le
// bouton apparaît sur des pages publiques et sur des pages membres, qui
// ne partagent pas les mêmes styles.
function partageStyles() {
  if (document.getElementById('partage-styles')) return;
  const s = document.createElement('style');
  s.id = 'partage-styles';
  s.textContent =
    // Le bouton est en tête de fiche : il respire au-dessous, pour ne pas
    // se coller au premier paragraphe.
    '.partage-zone{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:16px 0 26px;}' +
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
    // Page d'aperçu pas encore générée : le dire vaut mieux que de
    // laisser partir un lien dont l'aperçu n'affichera aucun titre.
    if (!(await partageDisponible(adresse))) {
      message.textContent = "L'aperçu de partage est en préparation : réessayez dans une heure.";
      setTimeout(() => { message.textContent = ''; }, 6000);
      return;
    }
    const etat = await partagerAdresse(adresse, titre);
    // Partage natif abouti ou annulé par l'utilisateur : rien à dire.
    if (etat === 'partage' || etat === 'annule') return;
    // Presse-papiers indisponible : on montre l'adresse pour que la
    // personne la copie elle-même.
    message.textContent = etat === 'copie' ? 'Lien copié' : etat;
    setTimeout(() => { message.textContent = ''; }, 4000);
  });

  zone.appendChild(bouton);
  zone.appendChild(message);
}
