/* ============================================================
   Bascule mode clair/sombre - AMSTC
   Le choix de l'utilisateur est mémorisé (localStorage) ; tant qu'il
   n'a rien choisi explicitement, le thème suit les réglages système.
   Le bouton flottant est créé dynamiquement ici : aucune page n'a
   besoin d'ajouter de markup, seulement de charger ce script.
   ============================================================ */
(function () {
  var STORAGE_KEY = "amstc-theme";

  function getStoredTheme() {
    try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }

  function systemPrefersDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  function applyTheme(theme, persist) {
    document.documentElement.setAttribute("data-theme", theme);
    if (persist) {
      try { localStorage.setItem(STORAGE_KEY, theme); } catch (e) {}
    }
    var btn = document.querySelector(".theme-toggle-btn");
    if (btn) btn.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
    // L'entree de menu annonce l'action, pas l'etat : en clair elle
    // propose « Mode sombre ».
    var mot = document.querySelector(".menu-extra-theme .menu-extra-mot");
    if (mot) mot.textContent = theme === "dark" ? "Mode clair" : "Mode sombre";
  }

  function currentTheme() {
    return document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
  }

  function createToggleButton() {
    if (document.querySelector(".theme-toggle-btn")) return;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "theme-toggle-btn";
    btn.setAttribute("aria-label", "Basculer entre mode clair et mode sombre");
    btn.setAttribute("aria-pressed", currentTheme() === "dark" ? "true" : "false");
    btn.innerHTML =
      '<svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>' +
      '<svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z"/></svg>';
    btn.addEventListener("click", function () {
      applyTheme(currentTheme() === "dark" ? "light" : "dark", true);
    });
    document.body.appendChild(btn);
    creerEntreeMenu();
  }

  function creerEntreeMenu() {
    if (document.querySelector(".menu-extra-theme")) return;
    var e = document.createElement("button");
    e.type = "button";
    e.className = "menu-extra menu-extra-theme";
    // Une icone de contraste, lisible dans les deux themes - plutot que
    // le couple soleil/lune du bouton flottant, dont l'affichage depend
    // de regles propres a ce bouton.
    e.innerHTML =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 3a9 9 0 0 0 0 18Z" fill="currentColor"/></svg>'
      + '<span class="menu-extra-mot">' + (currentTheme() === "dark" ? "Mode clair" : "Mode sombre") + '</span>';
    e.addEventListener("click", function () {
      applyTheme(currentTheme() === "dark" ? "light" : "dark", true);
    });
    poserDansMenu(e, "a-menu-theme");
  }

  // Sous 880 px, le bouton flottant cede la place a une entree de menu
  // (voir dark-mode.css). Deux menus existent : celui du site public
  // (#navLinks) et celui de l'espace membres (.member-nav-panel). Le
  // second est construit par member-nav.js, qui peut passer APRES nous -
  // d'ou l'observation du DOM plutot qu'un simple querySelector.
  function poserDansMenu(el, marqueur) {
    function essayer() {
      var c = document.querySelector("#navLinks, .member-nav-panel");
      if (!c) return false;
      c.appendChild(el);
      // Le marqueur autorise le CSS a masquer le bouton flottant. Il
      // n'est pose qu'ICI, une fois l'entree REELLEMENT en place :
      // 28 des 71 pages n'ont aucun menu, et masquer le bouton sur la
      // seule foi de la largeur d'ecran y rendrait la fonction
      // inatteignable.
      document.documentElement.classList.add(marqueur);
      return true;
    }
    if (essayer()) return;
    if (!window.MutationObserver) return;
    var obs = new MutationObserver(function () { if (essayer()) obs.disconnect(); });
    obs.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(function () { obs.disconnect(); }, 5000);
  }

  // Le thème initial est déjà posé par le script anti-flash inline
  // dans <head> ; on s'assure juste qu'il existe (page sans ce script).
  if (!document.documentElement.getAttribute("data-theme")) {
    applyTheme(getStoredTheme() || (systemPrefersDark() ? "dark" : "light"), false);
  }

  if (document.body) {
    createToggleButton();
  } else {
    document.addEventListener("DOMContentLoaded", createToggleButton);
  }

  // Suit les changements système tant que rien n'a été choisi à la main.
  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
      if (!getStoredTheme()) applyTheme(e.matches ? "dark" : "light", false);
    });
  }
})();
