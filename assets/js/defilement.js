/* ============================================================
   Défilement rapide - AMSTC
   Deux flèches flottantes, au-dessus du bouton de thème : remonter tout
   en haut, descendre tout en bas. Sur des cours de dix-huit sections ou
   des listes de membres, le pouce fatigue avant la fin.

   Elles n'apparaissent que si la page est assez longue pour en avoir
   besoin (plus d'un écran et demi), et chacune se cache quand elle ne
   sert à rien : « haut » disparaît en haut de page, « bas » en bas.
   Créées ici, sans markup à ajouter : une page n'a qu'à charger ce
   script (comme theme-toggle.js). Le style vit dans dark-mode.css, déjà
   chargé partout, pour suivre le thème.
   ============================================================ */
(function () {
  if (document.getElementById("amstc-defilement")) return;

  function reduit() {
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
  function aller(y) {
    window.scrollTo({ top: y, behavior: reduit() ? "auto" : "smooth" });
  }
  function hauteurPage() {
    var d = document.documentElement, b = document.body;
    return Math.max(d.scrollHeight, b ? b.scrollHeight : 0);
  }

  var boite = document.createElement("div");
  boite.id = "amstc-defilement";
  boite.className = "defilement";
  boite.setAttribute("aria-hidden", "true");

  var haut = document.createElement("button");
  haut.type = "button";
  haut.className = "defilement-btn defilement-haut";
  haut.setAttribute("aria-label", "Remonter tout en haut");
  haut.title = "Tout en haut";
  haut.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V6"/><path d="M6 12l6-6 6 6"/><path d="M5 3h14"/></svg>';
  haut.addEventListener("click", function () { aller(0); });

  var bas = document.createElement("button");
  bas.type = "button";
  bas.className = "defilement-btn defilement-bas";
  bas.setAttribute("aria-label", "Descendre tout en bas");
  bas.title = "Tout en bas";
  bas.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v13"/><path d="M6 12l6 6 6-6"/><path d="M5 21h14"/></svg>';
  bas.addEventListener("click", function () { aller(hauteurPage()); });

  boite.appendChild(haut);
  boite.appendChild(bas);

  // Le coin bas-droit est partagé : bouton de thème partout, bouton de
  // recherche sur le site public. Les flèches se posent AU-DESSUS du plus
  // haut des deux, mesuré - une valeur fixe les faisait chevaucher la
  // recherche. Recalculé au redimensionnement et quand un bouton apparaît
  // après nous (les deux se créent par script).
  function caler() {
    var haut = 0;
    var autres = document.querySelectorAll(".theme-toggle-btn, .site-search-btn");
    for (var i = 0; i < autres.length; i++) {
      var r = autres[i].getBoundingClientRect();
      if (r.width && r.height) haut = Math.max(haut, window.innerHeight - r.top);
    }
    var ecart = window.innerWidth <= 480 ? 16 : 18;   // mesure a l ecran : 12 net une fois la boite posee
    var marge = window.innerWidth <= 480 ? 14 : 20;
    boite.style.bottom = (haut ? haut + ecart : marge) + "px";
  }
  function poser() {
    if (!document.body) return;
    document.body.appendChild(boite);
    caler();
    majEtat();
    // Les autres boutons flottants peuvent se poser après nous : on
    // recale une ou deux fois, puis à chaque redimensionnement.
    setTimeout(caler, 300); setTimeout(caler, 1500);
    window.addEventListener("resize", caler);
  }

  var tick = false;
  function majEtat() {
    var y = window.scrollY || document.documentElement.scrollTop || 0;
    var h = hauteurPage(), v = window.innerHeight;
    var longue = h > v * 1.5;
    boite.classList.toggle("visible", longue);
    boite.setAttribute("aria-hidden", longue ? "false" : "true");
    haut.classList.toggle("inutile", y < 200);
    bas.classList.toggle("inutile", y + v >= h - 200);
    tick = false;
  }
  function planifier() {
    if (tick) return;
    tick = true;
    (window.requestAnimationFrame || setTimeout)(majEtat);
  }
  window.addEventListener("scroll", planifier, { passive: true });
  window.addEventListener("resize", planifier);
  // Le contenu arrive souvent APRÈS le chargement (cours, listes) : la
  // page grandit sans défiler. On réévalue quand le DOM bouge.
  if (window.MutationObserver) {
    new MutationObserver(planifier).observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.body) poser(); else document.addEventListener("DOMContentLoaded", poser);
})();
