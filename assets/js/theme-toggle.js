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
    // TOUS les exemplaires : il y en a deux sur les pages qui ont un
    // menu - l'entree de menu et l'icone d'entete.
    var mots = document.querySelectorAll(".menu-extra-theme .menu-extra-mot");
    for (var i = 0; i < mots.length; i++) {
      mots[i].textContent = theme === "dark" ? "Mode clair" : "Mode sombre";
    }
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
    poserOutil(fabriquerEntree, "a-menu-theme");
  }

  function fabriquerEntree() {
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
    return e;
  }

  // Sous 880 px, le bouton flottant cede la place a une entree de menu
  // (voir dark-mode.css). Deux menus existent : celui du site public
  // (#navLinks) et celui de l'espace membres (.member-nav-panel). Le
  // second est construit par member-nav.js, qui peut passer APRES nous -
  // d'ou l'observation du DOM plutot qu'un simple querySelector.
  // A DEFAUT DE MENU, l'entete. 28 pages n'ont ni la barre du site public
  // ni les onglets de l'espace membres ; 23 d'entre elles ont un <header>,
  // ou le theme et la recherche tiennent en icones, en haut a droite.
  //
  // POSITION ABSOLUE, et non un enfant de la rangee. Le premier essai
  // rendait flexbox le conteneur interieur de l'entete : cela marche quand
  // il ne porte qu'un logo, mais les bilans annuels y empilent logo,
  // sur-titre, titre et sous-titre - tout s'est retrouve sur une ligne et
  // la page debordait a 375 px. Poser la barre par-dessus ne touche a
  // aucune mise en page.
  //
  // Un entete qui porte deja un bouton a droite (la boite WhatsApp) lui
  // reserve sa place : la barre se decale vers la gauche.
  function barreEntete() {
    var entete = document.querySelector("header");
    // Cinq pages n ont pas d entete du tout : mentions legales, CGU, 404
    // et le guide. On se rabat sur leur conteneur de tete, avec une
    // variante CLAIRE - ces pages n ont pas le bandeau vert, et des icones
    // blanches y seraient invisibles.
    var clair = false;
    if (!entete) {
      entete = document.querySelector(".box, .shell, body > .wrap, main > .wrap");
      clair = true;
    }
    if (!entete) return null;
    var barre = entete.querySelector(".outils-entete");
    if (barre) return barre;
    barre = document.createElement("div");
    barre.className = "outils-entete" + (clair ? " outils-clair" : "");
    if (getComputedStyle(entete).position === "static") entete.style.position = "relative";
    // Largeur a reserver pour ce qui occupe deja le bord droit.
    var occupe = 0;
    var bord = entete.getBoundingClientRect().right;
    var controles = entete.querySelectorAll("a, button");
    for (var i = 0; i < controles.length; i++) {
      var r = controles[i].getBoundingClientRect();
      // Un CONTROLE, pas un bloc : le logo de certaines pages est un lien
      // qui occupe toute la largeur, et son bord droit touche celui de
      // l entete sans rien occuper a droite. Sans la borne de largeur, la
      // barre etait repoussee hors de l ecran (constate sur /don).
      if (r.width && r.width < 160 && bord - r.right < 90) occupe = Math.max(occupe, bord - r.left);
    }
    if (occupe) barre.style.right = (occupe + 12) + "px";
    entete.appendChild(barre);
    entete.classList.add("a-outils-entete");
    return barre;
  }

  // DEUX EMPLACEMENTS, pas un. Sur telephone, un menu est le bon endroit
  // pour un reglage ; sur ordinateur, le menu est une rangee horizontale
  // de rubriques, ou une bascule de theme detonnerait - l'entete convient
  // mieux. Les pages qui ont un menu recoivent donc les DEUX, et le CSS
  // montre l'un ou l'autre selon la largeur.
  //
  // « fabrique » et non un element tout fait : il en faut un par
  // emplacement, un noeud ne pouvant etre a deux endroits a la fois.
  //
  // Le marqueur autorise le CSS a masquer le bouton flottant. Il n'est
  // pose qu'une fois un exemplaire REELLEMENT en place : la page du CMS
  // n'offre aucun ancrage, et l'y masquer sur la seule foi de la largeur
  // rendrait la fonction inatteignable.
  function poserOutil(fabrique, marqueur) {
    var barre = barreEntete();
    if (barre) {
      barre.appendChild(fabrique());
      document.documentElement.classList.add(marqueur);
    }

    function poserDansMenu() {
      var menu = document.querySelector("#navLinks, .member-nav-panel");
      if (!menu) return false;
      menu.appendChild(fabrique());
      // L'entete devient un COMPLEMENT : le menu le releve sous 880 px.
      if (barre) barre.classList.add("outils-complement");
      document.documentElement.classList.add(marqueur);
      return true;
    }
    if (poserDansMenu()) return;
    // Le panneau de l'espace membres est construit par member-nav.js, qui
    // peut passer APRES nous - d'ou l'observation plutot qu'un simple
    // querySelector.
    if (!window.MutationObserver) return;
    var obs = new MutationObserver(function () { if (poserDansMenu()) obs.disconnect(); });
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
