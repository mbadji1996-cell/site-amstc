/* ============================================================
   Annonce plein écran (pop-up temporaire) — AMSTC
   Contenu géré via Decap CMS (content/popup-annonce.json). S'affiche en
   plein écran, se ferme automatiquement après une durée configurée
   (10 à 15 s) ou dès qu'on clique (fond, croix, ou bouton d'action).
   Ne s'affiche qu'une fois par session/contenu (sessionStorage) : une
   nouvelle publication depuis le CMS la fait réapparaître pour tout le
   monde, mais elle ne s'impose pas à chaque page vue de la même visite.
   ============================================================ */
(function () {
  var SEEN_KEY = "amstc-popup-annonce-seen";

  function esc(s) {
    return String(s || "").replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function buildOverlay(data, signature) {
    var overlay = document.createElement("div");
    overlay.className = "popup-annonce-overlay";

    var duree = Math.min(15, Math.max(10, Number(data.duree_secondes) || 12));

    overlay.innerHTML =
      '<div class="popup-annonce-card" role="dialog" aria-label="Annonce">' +
        '<button class="popup-annonce-close" type="button" aria-label="Fermer">✕</button>' +
        (data.image ? '<img class="popup-annonce-image" src="' + esc(data.image) + '" alt="">' : "") +
        '<div class="popup-annonce-body">' +
          (data.titre ? '<p class="popup-annonce-title">' + esc(data.titre) + "</p>" : "") +
          (data.message ? '<p class="popup-annonce-message">' + esc(data.message) + "</p>" : "") +
          (data.cta_label && data.cta_url
            ? '<a class="popup-annonce-cta" href="' + esc(data.cta_url) + '">' + esc(data.cta_label) + "</a>"
            : "") +
        "</div>" +
        '<div class="popup-annonce-timer-track"><div class="popup-annonce-timer-bar" style="animation-duration:' + duree + 's;"></div></div>' +
      "</div>";

    document.body.appendChild(overlay);

    var closed = false;
    var autoTimer = null;

    function close() {
      if (closed) return;
      closed = true;
      overlay.classList.remove("open");
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
    var cta = overlay.querySelector(".popup-annonce-cta");
    if (cta) cta.addEventListener("click", close);

    overlay.classList.add("open");
    autoTimer = setTimeout(close, duree * 1000);
  }

  function init() {
    fetch("content/popup-annonce.json")
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !data.active || (!data.titre && !data.message)) return;

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
