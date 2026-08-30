/* ============================================================
   Annonce plein écran (pop-up temporaire) - AMSTC
   Contenu géré via Decap CMS (content/popup-annonce.json). S'affiche en
   plein écran, se ferme automatiquement après une durée configurée
   (1 s à 5 min) ou dès qu'on clique (fond, croix, ou bouton OK).
   Ne s'affiche qu'une fois par session/contenu (sessionStorage) : une
   nouvelle publication depuis le CMS la fait réapparaître pour tout le
   monde, mais elle ne s'impose pas à chaque page vue de la même visite.
   ============================================================ */
(function () {
  var SEEN_KEY = "amstc-popup-annonce-seen";
  var savedScrollY = 0;

  function lockBackgroundScroll() {
    savedScrollY = window.scrollY || window.pageYOffset || 0;
    document.body.style.position = "fixed";
    document.body.style.top = -savedScrollY + "px";
    document.body.style.left = "0";
    document.body.style.right = "0";
    document.body.style.width = "100%";
  }

  function unlockBackgroundScroll() {
    document.body.style.position = "";
    document.body.style.top = "";
    document.body.style.left = "";
    document.body.style.right = "";
    document.body.style.width = "";
    window.scrollTo(0, savedScrollY);
  }

  function esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function buildOverlay(data, signature) {
    var overlay = document.createElement("div");
    overlay.className = "popup-annonce-overlay" + (data.plein_ecran ? " fullscreen" : "");

    var duree = Math.min(300, Math.max(1, Number(data.duree_secondes) || 12));

    // Un lien vers le site lui-meme - la page de don, par exemple - ne
    // doit pas ouvrir un onglet : l'annonce resterait affichee dans
    // l'onglet d'origine, et reapparaitrait dans le nouveau. Seules les
    // adresses exterieures s'ouvrent a cote.
    var estExterne = false;
    if (data.cta_url) {
      try {
        estExterne = new URL(data.cta_url, location.href).origin !== location.origin;
      } catch (e) { estExterne = /^https?:\/\//i.test(data.cta_url); }
    }
    var cible = estExterne ? ' target="_blank" rel="noopener"' : '';
    var hasBodyContent = !!(data.titre || data.message || (data.cta_label && data.cta_url));
    var okLabel = data.texte_fermeture || "OK";

    overlay.innerHTML =
      '<div class="popup-annonce-card" role="dialog" aria-label="Annonce">' +
        '<button class="popup-annonce-close" type="button" aria-label="Fermer">✕</button>' +
        '<div class="popup-annonce-scroll">' +
          (data.image ? '<img class="popup-annonce-image" src="' + esc(data.image) + '" alt="' + esc(data.titre || "Annonce") + '">' : "") +
          (hasBodyContent
            ? '<div class="popup-annonce-body">' +
                (data.titre ? '<p class="popup-annonce-title">' + esc(data.titre) + "</p>" : "") +
                (data.message ? '<p class="popup-annonce-message">' + esc(data.message) + "</p>" : "") +
                (data.cta_label && data.cta_url
                  ? '<div class="popup-annonce-actions"><a class="popup-annonce-cta" href="' + esc(data.cta_url) + '"' + cible + '>' + esc(data.cta_label) + "</a></div>"
                  : "") +
              "</div>"
            : "") +
        "</div>" +
        '<div class="popup-annonce-footer">' +
          '<div class="popup-annonce-timer-track"><div class="popup-annonce-timer-bar" style="animation-duration:' + duree + 's;"></div></div>' +
          '<div class="popup-annonce-footer-actions"><button class="popup-annonce-ok" type="button">' + esc(okLabel) + "</button></div>" +
        "</div>" +
      "</div>";

    document.body.appendChild(overlay);

    var closed = false;
    var autoTimer = null;

    function close() {
      if (closed) return;
      closed = true;
      overlay.classList.remove("open");
      unlockBackgroundScroll();
      if (autoTimer) clearTimeout(autoTimer);
      try { sessionStorage.setItem(SEEN_KEY, signature); } catch (e) {}
      setTimeout(function () {
        if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
      }, 300);
    }

    overlay.addEventListener("click", function (e) {
      if (e.target === overlay) close();
    });
    overlay.querySelector(".popup-annonce-close").addEventListener("click", close);
    overlay.querySelector(".popup-annonce-ok").addEventListener("click", close);

    // Cliquer l'action PRINCIPALE, c'est avoir vu l'annonce. Sans cet
    // appel, close() n'etait jamais execute par ce chemin et la signature
    // n'entrait pas dans sessionStorage : l'annonce revenait a la page
    // suivante. sessionStorage.setItem s'execute avant que la navigation
    // ne parte, l'ordre est donc sur, y compris pour un lien interne.
    var cta = overlay.querySelector(".popup-annonce-cta");
    if (cta) cta.addEventListener("click", close);

    lockBackgroundScroll();
    overlay.classList.add("open");
    autoTimer = setTimeout(close, duree * 1000);
  }

  function init() {
    fetch("content/popup-annonce.json")
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !data.active || (!data.titre && !data.message && !data.image)) return;

        var signature = JSON.stringify(data);
        var alreadySeen = false;
        try { alreadySeen = sessionStorage.getItem(SEEN_KEY) === signature; } catch (e) {}
        if (alreadySeen) return;

        buildOverlay(data, signature);
      })
      .catch(function () {});
  }

  document.addEventListener("DOMContentLoaded", init);
})();
