/* ============================================================
   Recherche globale - AMSTC
   Bouton flottant + fenêtre modale, créés dynamiquement (aucune page
   n'a besoin d'ajouter de markup, seulement de charger ce script).
   Recherche côté client dans les index déjà publiés (réalisations,
   formations, projets) : pas de service tiers, pas de dépendance.
   ============================================================ */
(function () {
  var SOURCES = [
    { file: "content/actualites-index.json", type: "Réalisation", page: "article" },
    { file: "content/formations-index.json", type: "Formation", page: "formation" },
    { file: "content/projets-index.json", type: "Projet", page: "projet" }
  ];

  var allItems = null;
  var loadPromise = null;

  function loadIndex() {
    if (loadPromise) return loadPromise;
    loadPromise = Promise.all(
      SOURCES.map(function (s) {
        return fetch(s.file)
          .then(function (r) { return r.ok ? r.json() : []; })
          .catch(function () { return []; })
          .then(function (items) {
            return items.map(function (it) {
              return Object.assign({}, it, { __type: s.type, __page: s.page });
            });
          });
      })
    ).then(function (arrays) {
      allItems = arrays.reduce(function (a, b) { return a.concat(b); }, []);
      return allItems;
    });
    return loadPromise;
  }

  function normalize(s) {
    return String(s || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  }

  function esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Délègue à assets/js/date-periode.js (chargé avant ce script) pour afficher
  // "du ... au ..." sur les fiches qui définissent une période. Repli sur une
  // date simple si le helper n'est pas présent sur la page.
  function formatDate(item) {
    if (!item) return "";
    if (typeof self.formatDatePeriode === "function") return self.formatDatePeriode(item);
    var d = item.date || item;
    return d ? new Date(d).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" }) : "";
  }

  function createUI() {
    if (document.querySelector(".site-search-btn")) return;

    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "site-search-btn";
    btn.setAttribute("aria-label", "Rechercher sur le site");
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>';

    var overlay = document.createElement("div");
    overlay.className = "site-search-overlay";
    overlay.innerHTML =
      '<div class="site-search-panel" role="dialog" aria-modal="true" aria-label="Recherche">' +
        '<div class="site-search-input-row">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>' +
          '<input type="text" class="site-search-input" placeholder="Rechercher une réalisation, une formation, un projet…" autocomplete="off">' +
          '<button type="button" class="site-search-close" aria-label="Fermer la recherche">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6L6 18M6 6l12 12"/></svg>' +
          "</button>" +
        "</div>" +
        '<div class="site-search-results"></div>' +
      "</div>";

    document.body.appendChild(btn);
    document.body.appendChild(overlay);

    // Entree de menu : sous 880 px, elle remplace le bouton flottant.
    var entree = document.createElement("button");
    entree.type = "button";
    entree.className = "menu-extra menu-extra-recherche";
    entree.innerHTML =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>'
      + '<span class="menu-extra-mot">Rechercher</span>';
    poserDansMenu(entree, "a-menu-recherche");

    var input = overlay.querySelector(".site-search-input");
    var results = overlay.querySelector(".site-search-results");
    var closeBtn = overlay.querySelector(".site-search-close");

    entree.addEventListener("click", function () {
      // Le menu se referme derriere nous : la recherche prend tout
      // l'ecran, et deux couches ouvertes l'une sur l'autre piegeraient
      // la touche « retour ».
      var menu = document.getElementById("navLinks");
      if (menu) menu.classList.remove("open");
      var panneau = document.querySelector(".member-nav-panel.open");
      if (panneau) panneau.classList.remove("open");
      open();
    });

    function open() {
      overlay.classList.add("open");
      document.body.style.overflow = "hidden";
      render(input.value);
      loadIndex().then(function () { render(input.value); });
      setTimeout(function () { input.focus(); }, 50);
    }
    function close() {
      overlay.classList.remove("open");
      document.body.style.overflow = "";
    }

    function render(query) {
      var q = normalize(query.trim());
      if (!q) {
        results.innerHTML = '<p class="site-search-hint">Commencez à taper pour rechercher…</p>';
        return;
      }
      if (!allItems) {
        results.innerHTML = '<p class="site-search-hint">Chargement…</p>';
        return;
      }
      var matches = allItems.filter(function (it) {
        var haystack = normalize([it.title, it.excerpt].filter(Boolean).join(" "));
        return haystack.indexOf(q) !== -1;
      }).slice(0, 12);

      if (matches.length === 0) {
        results.innerHTML = '<p class="site-search-hint">Aucun résultat pour « ' + esc(query) + " ».</p>";
        return;
      }

      results.innerHTML = matches.map(function (m) {
        return (
          '<a class="site-search-result" href="' + m.__page + "?slug=" + encodeURIComponent(m.slug) + '">' +
            '<span class="site-search-result-type">' + esc(m.__type) + "</span>" +
            '<span class="site-search-result-title">' + esc(m.title) + "</span>" +
            '<span class="site-search-result-date">' + formatDate(m) + "</span>" +
          "</a>"
        );
      }).join("");
    }

    btn.addEventListener("click", open);
    closeBtn.addEventListener("click", close);
    overlay.addEventListener("click", function (e) { if (e.target === overlay) close(); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && overlay.classList.contains("open")) close();
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        overlay.classList.contains("open") ? close() : open();
      }
    });
    input.addEventListener("input", function () { render(input.value); });
  }

  if (document.body) {
    createUI();
  } else {
    document.addEventListener("DOMContentLoaded", createUI);
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

  function poserDansMenu(el, marqueur) {
    function essayer() {
      var c = document.querySelector("#navLinks, .member-nav-panel") || barreEntete();
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

})();
