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

  function poser() {
    if (!document.body) return;
    document.body.appendChild(boite);
    // Le bouton de thème, s'il existe, est déjà en bas à droite : on lui
    // laisse sa place et on se met juste au-dessus. S'il manque, on
    // prend le coin.
    var theme = document.querySelector(".theme-toggle-btn");
    if (!theme) boite.classList.add("defilement-seul");
    majEtat();
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
