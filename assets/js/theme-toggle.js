/* ============================================================
   Bascule mode clair/sombre — AMSTC
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
