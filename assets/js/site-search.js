/* ============================================================
   Recherche globale — AMSTC
   Bouton flottant + fenêtre modale, créés dynamiquement (aucune page
   n'a besoin d'ajouter de markup, seulement de charger ce script).
   Recherche côté client dans les index déjà publiés (réalisations,
   formations, projets) : pas de service tiers, pas de dépendance.
   ============================================================ */
(function () {
  var SOURCES = [
    { file: "content/actualites-index.json", type: "Réalisation", page: "article.html" },
    { file: "content/formations-index.json", type: "Formation", page: "formation.html" },
    { file: "content/projets-index.json", type: "Projet", page: "projet.html" }
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
    return String(s || "").replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function formatDate(d) {
    if (!d) return "";
    return new Date(d).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" });
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

    var input = overlay.querySelector(".site-search-input");
    var results = overlay.querySelector(".site-search-results");
    var closeBtn = overlay.querySelector(".site-search-close");

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
            '<span class="site-search-result-date">' + formatDate(m.date) + "</span>" +
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
})();
