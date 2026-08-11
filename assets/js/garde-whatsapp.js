/**
 * Garde-fou WhatsApp des écrans d'administration.
 *
 * POURQUOI. WhatsApp restreint un compte qui ouvre beaucoup de nouvelles
 * conversations en peu de temps vers des numéros qui ne l'ont pas dans
 * leurs contacts - c'est arrivé à l'association le 11 août 2026 (24 h de
 * blocage). Ce script compte les conversations ouvertes depuis le site et
 * demande confirmation au-delà d'un seuil prudent.
 *
 * CE QUI EST COMPTÉ : les numéros DISTINCTS ouverts aujourd'hui, depuis ce
 * navigateur. Rouvrir la conversation d'un même membre ne compte qu'une
 * fois - le risque vient des nouvelles conversations, pas des allers-
 * retours dans une discussion existante. Le compteur est local : il suit
 * l'administrateur (dont le téléphone porte le compte WhatsApp), pas le
 * site.
 *
 * USAGE. Les liens <a href="https://wa.me/…"> sont interceptés tout
 * seuls. Les ouvertures par window.open passent par :
 *   if (!gardeWhatsAppAutorise(numeroOuUrl)) return;   // AVANT window.open
 * L'appel est synchrone : window.open reste rattaché au clic, condition
 * pour ne pas être bloqué comme fenêtre intempestive sur mobile.
 */

// Au-delà de ce nombre de nouvelles conversations dans la journée, chaque
// ouverture supplémentaire demande confirmation. Volontairement sous les
// ~20 où les restrictions ont été observées.
var GARDE_WA_SEUIL = 15;

function gardeWhatsAppEtat() {
  var jour = new Date().toISOString().slice(0, 10);
  var etat = null;
  try { etat = JSON.parse(localStorage.getItem('amstc-garde-wa') || 'null'); } catch (e) { /* stockage indisponible */ }
  if (!etat || etat.jour !== jour || !Array.isArray(etat.numeros)) etat = { jour: jour, numeros: [] };
  return etat;
}

function gardeWhatsAppCompte() {
  return gardeWhatsAppEtat().numeros.length;
}

/**
 * À appeler avant toute ouverture de conversation. Renvoie false si
 * l'administrateur renonce ; enregistre le numéro et met le badge à jour
 * sinon.
 */
function gardeWhatsAppAutorise(numeroOuUrl) {
  var digits = String(numeroOuUrl || '').replace(/^https?:\/\/wa\.me\//i, '').split('?')[0].replace(/\D/g, '');
  if (!digits) return true; // rien d'exploitable : ne pas bloquer
  var etat = gardeWhatsAppEtat();
  var deja = etat.numeros.indexOf(digits) !== -1;

  if (!deja && etat.numeros.length >= GARDE_WA_SEUIL) {
    var ok = confirm(
      'Vous avez déjà ouvert ' + etat.numeros.length + ' conversations WhatsApp différentes aujourd\'hui.\n\n'
      + 'Au-delà de ' + GARDE_WA_SEUIL + ' nouvelles conversations par jour, WhatsApp peut restreindre '
      + 'votre compte pour 24 h ou plus - c\'est déjà arrivé à l\'association.\n\n'
      + 'Ouvrir quand même cette conversation ?'
    );
    if (!ok) return false;
  }

  if (!deja) {
    etat.numeros.push(digits);
    try { localStorage.setItem('amstc-garde-wa', JSON.stringify(etat)); } catch (e) { /* stockage indisponible */ }
  }
  gardeWhatsAppBadge();
  return true;
}

// Badge fixe en bas à gauche (le bouton de thème occupe la droite).
// Absent tant qu'aucune conversation n'a été ouverte : il n'a rien à dire.
function gardeWhatsAppBadge() {
  var n = gardeWhatsAppCompte();
  var el = document.getElementById('gardeWaBadge');
  if (n === 0) { if (el) el.remove(); return; }
  if (!el) {
    el = document.createElement('div');
    el.id = 'gardeWaBadge';
    el.style.cssText = 'position:fixed;left:14px;bottom:14px;z-index:998;'
      + 'font-family:ui-monospace,monospace;font-size:0.72rem;font-weight:600;'
      + 'padding:7px 13px;border-radius:999px;border:1.5px solid;pointer-events:none;';
    document.body.appendChild(el);
  }
  var couleurs = n >= GARDE_WA_SEUIL
    ? ['#FDEEEE', '#B23B3B']            // seuil atteint : rouge
    : n >= 10
      ? ['#FEF6E4', '#8A6D1F']          // on approche : orange
      : ['#ECEFE3', '#3B6D11'];         // rythme sûr : vert discret
  el.style.background = couleurs[0];
  el.style.color = couleurs[1];
  el.style.borderColor = couleurs[1];
  el.textContent = 'WhatsApp aujourd\'hui : ' + n + (n >= GARDE_WA_SEUIL ? ' ⚠' : '') + ' / ' + GARDE_WA_SEUIL;
  el.title = 'Conversations WhatsApp distinctes ouvertes aujourd\'hui depuis ce navigateur. '
    + 'Au-delà de ' + GARDE_WA_SEUIL + ' par jour, WhatsApp peut restreindre votre compte.';
}

// Les liens wa.me directs (lignes de membres, boutons « Prévenir par
// WhatsApp »…) passent par le même garde-fou, sans modifier chaque page.
// Phase de capture : le refus doit empêcher la navigation.
document.addEventListener('click', function (e) {
  var a = e.target && e.target.closest ? e.target.closest('a[href*="wa.me/"]') : null;
  if (!a) return;
  if (!gardeWhatsAppAutorise(a.getAttribute('href'))) {
    e.preventDefault();
    e.stopPropagation();
  }
}, true);

// Badge au chargement : un administrateur qui revient sur la page voit où
// il en est de sa journée.
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', gardeWhatsAppBadge);
} else {
  gardeWhatsAppBadge();
}
