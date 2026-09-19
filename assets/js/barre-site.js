/* ============================================================
   Barre de navigation du site public
   ------------------------------------------------------------
   La même barre que sur la page d'accueil, sur toutes les pages
   publiques. Chaque page pose, à l'endroit voulu :

     <header class="barre-site" id="barreSite"></header>
     <script src="assets/js/barre-site.js"></script>

   Le script est SYNCHRONE, et c'est voulu : il remplit la barre
   pendant la lecture de la page, avant theme-toggle.js et
   site-search.js (chargés en defer), qui y ajoutent ensuite le
   thème et la recherche comme sur l'accueil.

   Les deux menus déroulants suivent le CMS (content/navigation.json,
   « Navigation, Liens & pied de page ») : ce qui y est modifié
   change la barre de l'accueil ET celle des autres pages.
   ============================================================ */
(function () {
  var barre = document.getElementById('barreSite');
  if (!barre) return;

  // Racine du site, déduite de l'adresse du script : la barre marche
  // aussi bien depuis /don que depuis /membres/connexion ou /rapports/.
  var script = document.currentScript;
  var racine = script && script.src
    ? script.src.replace(/assets\/js\/barre-site\.js(\?.*)?$/, '')
    : '/';

  // Un lien du CMS : « #ancre » vise une section de l'accueil, « page »
  // une page du site, « https://… » reste tel quel.
  function lien(href) {
    href = String(href || '');
    if (/^(https?:|mailto:|tel:)/i.test(href)) return href;
    if (href.charAt(0) === '#') return racine + href;
    return racine + href.replace(/^\.?\//, '');
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // Repli : la même liste que l'accueil, si le fichier n'arrive pas.
  var DECOUVRIR = [
    { label: 'Qui sommes-nous ?', href: '#qui-sommes-nous' },
    { label: 'Nos actions', href: '#nos-actions' },
    { label: 'Historique', href: '#historique' }
  ];
  var ACTIVITES = [
    { label: 'Réalisations', href: 'actualites' },
    { label: 'Formation', href: 'formations' },
    { label: 'Projets', href: 'projets' },
    { label: 'Agenda', href: 'agenda' },
    { label: 'Demander une campagne', href: 'demande-campagne' }
  ];

  // La page courante, pour la marquer dans les menus.
  function nomDePage(url) {
    var a = document.createElement('a');
    a.href = url;
    return a.pathname.replace(/\.html$/, '').replace(/\/index$/, '/').replace(/\/$/, '/');
  }
  var ici = nomDePage(window.location.href);

  function liens(items) {
    return items.map(function (i) {
      var h = lien(i.href);
      var courant = h.indexOf('#') === -1 && nomDePage(h) === ici;
      return '<a href="' + esc(h) + '"' + (courant ? ' aria-current="page"' : '') + '>' + esc(i.label) + '</a>';
    }).join('');
  }

  function menu(titre, id, items) {
    return '<div class="nav-dropdown">'
      + '<button class="nav-dropdown-trigger" type="button" aria-haspopup="true" aria-expanded="false">'
      + esc(titre) + ' <span class="chevron" aria-hidden="true"></span></button>'
      + '<div class="nav-dropdown-menu" id="' + id + '">' + liens(items) + '</div></div>';
  }

  barre.innerHTML =
    '<div class="bs-wrap">'
    + '<a href="' + esc(racine) + '" class="bs-logo"><img src="' + esc(racine) + 'assets/logo-horizontal-sm.png" alt="AMSTC - Association Médico-Sociale des Talibés Cheikh"></a>'
    + '<nav class="nav-links" id="navLinks">'
    + menu("Découvrir l'AMSTC", 'nav-menu-decouvrir', DECOUVRIR)
    + menu('Nos activités', 'nav-menu-activites', ACTIVITES)
    + '<a href="https://consultations-amstc.org" target="_blank" rel="noopener">Espace consultation</a>'
    + '<a href="' + esc(racine) + 'membres/connexion"' + (ici === nomDePage(racine + 'membres/connexion') ? ' aria-current="page"' : '') + '>Se connecter</a>'
    + '<a href="' + esc(racine) + '#contact">Contact</a>'
    + '</nav>'
    + '<div class="bs-actions">'
    + '<a href="' + esc(racine) + 'don" class="bs-don">Faire un don</a>'
    + '<button class="menu-toggle" id="menuToggle" type="button" aria-label="Ouvrir le menu" aria-expanded="false" aria-controls="navLinks">'
    + '<span></span><span></span><span></span></button>'
    + '</div></div>';

  // ===== Menus du CMS =====
  fetch(racine + 'content/navigation.json?t=' + Date.now())
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (d) {
      if (!d) return;
      [['nav-menu-decouvrir', d.nav_decouvrir], ['nav-menu-activites', d.nav_activites]].forEach(function (p) {
        if (Array.isArray(p[1]) && p[1].length) document.getElementById(p[0]).innerHTML = liens(p[1]);
      });
      brancherLiens();
    })
    .catch(function () { /* le repli reste affiché */ });

  // ===== Comportement : le même que sur l'accueil =====
  var toggle = document.getElementById('menuToggle');
  var panneau = document.getElementById('navLinks');
  var POINT_DE_RUPTURE = 1180;
  function surOrdinateur() { return window.innerWidth > POINT_DE_RUPTURE; }

  function fermerMenus() {
    var ouverts = barre.querySelectorAll('.nav-dropdown.open');
    for (var i = 0; i < ouverts.length; i++) {
      ouverts[i].classList.remove('open');
      ouverts[i].querySelector('.nav-dropdown-trigger').setAttribute('aria-expanded', 'false');
    }
  }

  var defilementGarde = 0;
  function bloquerDefilement() {
    defilementGarde = window.scrollY;
    document.body.style.position = 'fixed';
    document.body.style.top = '-' + defilementGarde + 'px';
    document.body.style.width = '100%';
  }
  function libererDefilement() {
    if (document.body.style.position !== 'fixed') return;
    document.body.style.position = '';
    document.body.style.top = '';
    document.body.style.width = '';
    window.scrollTo(0, defilementGarde);
  }
  function fermerPanneau() {
    panneau.classList.remove('open');
    toggle.setAttribute('aria-expanded', 'false');
    fermerMenus();
    libererDefilement();
  }

  toggle.addEventListener('click', function () {
    var ouvert = panneau.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(ouvert));
    fermerMenus();
    if (ouvert) bloquerDefilement(); else libererDefilement();
  });

  // Un clic sur un lien ferme le panneau (les liens sont reconstruits
  // quand le CMS arrive : on rebranche).
  function brancherLiens() {
    var a = panneau.querySelectorAll('a');
    for (var i = 0; i < a.length; i++) {
      if (a[i].dataset.branche) continue;
      a[i].dataset.branche = '1';
      a[i].addEventListener('click', fermerPanneau);
    }
  }
  brancherLiens();

  var minuterie = null;
  function ouvrirMenu(dd) {
    clearTimeout(minuterie);
    var ouverts = barre.querySelectorAll('.nav-dropdown.open');
    for (var i = 0; i < ouverts.length; i++) {
      if (ouverts[i] !== dd) {
        ouverts[i].classList.remove('open');
        ouverts[i].querySelector('.nav-dropdown-trigger').setAttribute('aria-expanded', 'false');
      }
    }
    dd.classList.add('open');
    dd.querySelector('.nav-dropdown-trigger').setAttribute('aria-expanded', 'true');
  }
  var menus = barre.querySelectorAll('.nav-dropdown');
  for (var m = 0; m < menus.length; m++) {
    (function (dd) {
      var declencheur = dd.querySelector('.nav-dropdown-trigger');
      dd.addEventListener('mouseenter', function () { if (surOrdinateur()) ouvrirMenu(dd); });
      dd.addEventListener('mouseleave', function () {
        if (!surOrdinateur()) return;
        clearTimeout(minuterie);
        minuterie = setTimeout(function () {
          dd.classList.remove('open');
          declencheur.setAttribute('aria-expanded', 'false');
        }, 200);
      });
      declencheur.addEventListener('focus', function () { if (surOrdinateur()) ouvrirMenu(dd); });
      declencheur.addEventListener('click', function (e) {
        e.stopPropagation();
        if (surOrdinateur()) { ouvrirMenu(dd); return; }
        var ouvert = dd.classList.contains('open');
        fermerMenus();
        dd.classList.toggle('open', !ouvert);
        declencheur.setAttribute('aria-expanded', String(!ouvert));
      });
    })(menus[m]);
  }
  document.addEventListener('click', fermerMenus);
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    fermerMenus();
    if (panneau.classList.contains('open')) fermerPanneau();
  });
  // Repasser en grand écran avec le panneau ouvert laisserait la page
  // bloquée.
  window.addEventListener('resize', function () {
    if (surOrdinateur() && panneau.classList.contains('open')) fermerPanneau();
  });
})();
