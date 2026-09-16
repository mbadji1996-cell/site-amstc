// Menu hamburger mobile pour la barre d'onglets de l'espace membres.
// Partagé par toutes les pages membres qui portent <nav class="member-tabs">.
// Fonctionne avec assets/css/member-nav.css : ce script construit le bouton
// et le panneau depuis les onglets déjà présents dans la page, puis pose la
// classe has-mobile-nav qui active la bascule CSS sous 880px.
//
// La barre peut contenir des GROUPES (« Formation » et ses quatre espaces).
// Sur grand écran, le CSS les ouvre au survol ; ce script ajoute le clic,
// indispensable au tactile et au clavier. Dans le panneau mobile, le parent
// devient un intitulé de section et ses enfants sont décalés dessous : une
// liste à plat de treize entrées ne se lit plus.
(function () {
  var tabs = document.querySelector('.member-tabs');
  if (!tabs) return;
  var inner = tabs.querySelector('.member-tabs-inner');
  if (!inner) return;

  // ===== Grand écran : ouvrir un groupe au clic =====
  var groupes = inner.querySelectorAll('.member-groupe');
  for (var g = 0; g < groupes.length; g++) {
    (function (groupe) {
      var parent = groupe.querySelector('.member-tab-parent');
      if (!parent) return;
      var sous = groupe.querySelector('.member-sous-menu');
      // Le sous-menu est en position:fixed (voir member-nav.css) : on le
      // pose sous l'onglet au moment de l'ouvrir, et on le suit si la page
      // defile ou change de taille tant qu'il est ouvert.
      function placer() {
        if (!sous || !groupe.classList.contains('ouvert')) return;
        var r = parent.getBoundingClientRect();
        sous.style.top = Math.round(r.bottom) + 'px';
        var gauche = Math.round(r.left);
        // Ne pas sortir de l'ecran a droite.
        var largeur = sous.offsetWidth || 230;
        if (gauche + largeur > window.innerWidth - 8) gauche = Math.max(8, window.innerWidth - 8 - largeur);
        sous.style.left = gauche + 'px';
      }
      parent.addEventListener('click', function (e) {
        e.stopPropagation();
        var ouvert = groupe.classList.toggle('ouvert');
        parent.setAttribute('aria-expanded', String(ouvert));
        placer();
      });
      window.addEventListener('scroll', placer, { passive: true });
      window.addEventListener('resize', placer);
      // Un clic dans le sous-menu ne doit pas etre pris pour un clic
      // « ailleurs » qui refermerait avant que le lien ne parte.
      if (sous) sous.addEventListener('click', function (e) { e.stopPropagation(); });
    })(groupes[g]);
  }
  // Un clic ailleurs referme : sans cela le panneau reste ouvert par-dessus
  // le contenu après qu'on a changé d'avis.
  document.addEventListener('click', function () {
    for (var i = 0; i < groupes.length; i++) {
      groupes[i].classList.remove('ouvert');
      var p = groupes[i].querySelector('.member-tab-parent');
      if (p) p.setAttribute('aria-expanded', 'false');
    }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      for (var i = 0; i < groupes.length; i++) groupes[i].classList.remove('ouvert');
    }
  });

  // ===== Panneau mobile, construit depuis la barre =====
  var activeLabel = 'Menu';
  var panel = document.createElement('div');
  panel.className = 'member-nav-panel';

  var enfants = inner.children;
  if (enfants.length === 0) return;

  for (var i = 0; i < enfants.length; i++) {
    var el = enfants[i];

    if (el.classList.contains('member-groupe')) {
      var parent = el.querySelector('.member-tab-parent');
      var titre = document.createElement('p');
      titre.className = 'mn-groupe';
      titre.textContent = parent ? parent.textContent.trim() : '';
      panel.appendChild(titre);

      var liens = el.querySelectorAll('.member-sous-lien');
      for (var j = 0; j < liens.length; j++) {
        var sa = document.createElement('a');
        sa.href = liens[j].getAttribute('href');
        sa.textContent = liens[j].textContent.trim();
        sa.className = 'mn-enfant' + (liens[j].classList.contains('active') ? ' active' : '');
        if (liens[j].classList.contains('active')) activeLabel = sa.textContent;
        panel.appendChild(sa);
      }
      continue;
    }

    if (el.classList.contains('member-tab')) {
      var a = document.createElement('a');
      a.href = el.getAttribute('href');
      a.textContent = el.textContent.trim();
      if (el.classList.contains('active')) {
        a.className = 'active';
        activeLabel = a.textContent;
      }
      panel.appendChild(a);
    }
  }

  // Le bouton porte le mot « Menu » en clair, pas seulement l'icône : le ☰
  // est une convention que tout le monde ne connaît pas, et la page
  // courante affichée à sa gauche se lit comme un titre, pas comme une
  // commande. La page reste indiquée - elle situe le lecteur - mais c'est
  // desormais la partie droite, encadrée, qui ressemble à un bouton.
  var toggle = document.createElement('button');
  toggle.type = 'button';
  toggle.className = 'member-nav-toggle';
  toggle.setAttribute('aria-expanded', 'false');
  toggle.setAttribute('aria-label', 'Ouvrir le menu de navigation');
  toggle.innerHTML =
    '<span class="mn-page"></span>' +
    '<span class="mn-bouton"><span class="mn-burger" aria-hidden="true">☰</span>' +
    '<span class="mn-mot">Menu</span></span>';
  toggle.querySelector('.mn-page').textContent = activeLabel;

  var mot = toggle.querySelector('.mn-mot');
  var burger = toggle.querySelector('.mn-burger');

  toggle.addEventListener('click', function (e) {
    e.stopPropagation();
    var open = panel.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(open));
    toggle.classList.toggle('ouvert', open);
    // L'icône et le mot changent à l'ouverture : sans cela, rien n'indique
    // comment refermer le panneau une fois déplié.
    burger.textContent = open ? '✕' : '☰';
    mot.textContent = open ? 'Fermer' : 'Menu';
    toggle.setAttribute('aria-label', open ? 'Fermer le menu de navigation' : 'Ouvrir le menu de navigation');
  });

  tabs.insertBefore(toggle, inner);
  tabs.appendChild(panel);
  tabs.classList.add('has-mobile-nav');
})();


// ===== Barre laterale de l'espace membre (>= 1024 px) =====
// Construite a partir des memes onglets : aucune page n'a eu a changer.
// Les icones sont en SVG plutot qu'en police Tabler, que onze pages
// membres ne chargent pas.
(function () {
  var tabs = document.querySelector('.member-tabs');
  if (!tabs) return;
  var inner = tabs.querySelector('.member-tabs-inner');
  if (!inner || inner.children.length === 0) return;

  // L'icone est choisie sur la destination et non sur l'intitule : les
  // liens sont identiques d'une page a l'autre, les libelles non.
  var ICONES = {
    '': 'M4 11.2 12 4l8 7.2V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z',
    'index': 'M4 11.2 12 4l8 7.2V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z',
    'profil': 'M3 6.5h18v11H3zM7 10.5h4M7 13.5h6M16.5 9.5h2M16.5 12.5h2',
    'formations': 'M2.5 9 12 4.5 21.5 9 12 13.5zM6.5 11.2V16c0 1.2 2.5 2.4 5.5 2.4s5.5-1.2 5.5-2.4v-4.8',
    'daara': 'M2.5 9 12 4.5 21.5 9 12 13.5zM6.5 11.2V16c0 1.2 2.5 2.4 5.5 2.4s5.5-1.2 5.5-2.4v-4.8',
    'actualites': 'M4 20V11M10 20V4M16 20v-6M3 20h18',
    'documents': 'M6.5 3h7l4.5 4.5V21h-11.5zM13.5 3v4.5H18',
    'boutique': 'M6 7.5h12L19 21H5zM9.2 7.5V5.6a2.8 2.8 0 0 1 5.6 0v1.9',
    'collectes': 'M12 20.5s-7.5-4.6-7.5-9.4A4.1 4.1 0 0 1 12 8.6a4.1 4.1 0 0 1 7.5 2.5c0 4.8-7.5 9.4-7.5 9.4z',
    'forum': 'M4 5h16v10.5H9.5L4 19.5zM8 9h8M8 12h5',
    'annuaire': 'M5 3.5h14v17H5zM5 8H3M5 12H3M5 16H3M12 11.2a2.1 2.1 0 1 0 0-4.2 2.1 2.1 0 0 0 0 4.2zM8.6 17a3.4 3.4 0 0 1 6.8 0',
    'mediatheque': 'M3.5 5.5h17v13h-17zM3.5 15l4.5-4 3.5 3 3-2.5 6 5M15.5 9.6a1.2 1.2 0 1 0 0-2.4 1.2 1.2 0 0 0 0 2.4z',
    'admin': 'M12 3.5 19.5 6v5.6c0 4.2-3.1 7.4-7.5 8.9-4.4-1.5-7.5-4.7-7.5-8.9V6z',
    'bibliotheque': 'M2.5 9 12 4.5 21.5 9 12 13.5zM6.5 11.2V16c0 1.2 2.5 2.4 5.5 2.4s5.5-1.2 5.5-2.4v-4.8',
    'medical': 'M2.5 9 12 4.5 21.5 9 12 13.5zM6.5 11.2V16c0 1.2 2.5 2.4 5.5 2.4s5.5-1.2 5.5-2.4v-4.8'
  };
  var ICONE_DEFAUT = 'M4 6h16M4 12h16M4 18h16';

  function cle(href) {
    var h = String(href || '').split('?')[0].split('#')[0];
    h = h.replace(/\/$/, '');
    h = h.split('/').pop() || '';
    return h.replace(/\.html$/, '');
  }
  function icone(href) {
    var d = ICONES[cle(href)] || ICONE_DEFAUT;
    var svg = '<svg viewBox="0 0 24 24" aria-hidden="true">';
    var morceaux = d.split('M');
    for (var i = 1; i < morceaux.length; i++) svg += '<path d="M' + morceaux[i] + '"/>';
    return '<span class="ms-ic">' + svg + '</span>';
  }

  var rail = document.createElement('aside');
  rail.className = 'ms-rail';
  rail.setAttribute('aria-label', "Navigation de l'espace membre");

  var premier = inner.querySelector('.member-tab');
  var marque = document.createElement('a');
  marque.className = 'ms-marque';
  marque.href = premier ? premier.getAttribute('href') : './';
  // logo-mark-sm.png est la version en largeur (marque a gauche, texte a
  // droite, rapport 2,81) ; logo-horizontal-sm.png, malgre son nom, est
  // la version carree empilee.
  marque.innerHTML = '<img src="../assets/logo-mark-sm.png" alt="AMSTC">';
  rail.appendChild(marque);

  var liste = document.createElement('nav');
  liste.className = 'ms-liens';

  var elements = inner.children;
  for (var i = 0; i < elements.length; i++) {
    var el = elements[i];

    if (el.classList.contains('member-groupe')) {
      var parent = el.querySelector('.member-tab-parent');
      if (!parent) continue;
      var groupe = document.createElement('div');
      groupe.className = 'ms-groupe';
      var bouton = document.createElement('button');
      bouton.type = 'button';
      bouton.className = 'ms-lien ms-parent';
      bouton.setAttribute('aria-expanded', 'false');
      var libelle = (parent.textContent || '').trim();
      var sousLiens = el.querySelectorAll('.member-sous-lien');
      var premierSous = sousLiens.length ? sousLiens[0].getAttribute('href') : '';
      bouton.innerHTML = icone(premierSous) + '<span class="ms-texte"></span><span class="ms-chev" aria-hidden="true"></span>';
      bouton.querySelector('.ms-texte').textContent = libelle;

      var sous = document.createElement('div');
      sous.className = 'ms-sous';
      var actifDedans = false;
      for (var j = 0; j < sousLiens.length; j++) {
        var sa = document.createElement('a');
        sa.className = 'ms-sous-lien';
        sa.href = sousLiens[j].getAttribute('href');
        sa.textContent = (sousLiens[j].textContent || '').trim();
        if (sousLiens[j].classList.contains('active')) { sa.classList.add('active'); actifDedans = true; }
        sous.appendChild(sa);
      }
      // Le groupe s'ouvre de lui-meme quand on est sur une de ses pages :
      // sinon la barre laterale n'indiquerait plus ou l'on se trouve.
      if (actifDedans || parent.classList.contains('active')) {
        groupe.classList.add('ouvert');
        bouton.setAttribute('aria-expanded', 'true');
      }
      bouton.addEventListener('click', function (g, b) {
        return function () {
          var ouvert = g.classList.toggle('ouvert');
          b.setAttribute('aria-expanded', String(ouvert));
        };
      }(groupe, bouton));

      groupe.appendChild(bouton);
      groupe.appendChild(sous);
      liste.appendChild(groupe);
      continue;
    }

    if (el.classList.contains('member-tab')) {
      var a = document.createElement('a');
      a.className = 'ms-lien' + (el.classList.contains('active') ? ' active' : '');
      a.href = el.getAttribute('href');
      a.innerHTML = icone(a.getAttribute('href')) + '<span class="ms-texte"></span>';
      a.querySelector('.ms-texte').textContent = (el.textContent || '').trim();
      if (el.classList.contains('active')) a.setAttribute('aria-current', 'page');
      liste.appendChild(a);
    }
  }

  rail.appendChild(liste);
  document.body.appendChild(rail);
  document.documentElement.classList.add('a-rail');
})();


// ===== Barre du haut de l'espace membre, commune a toutes les pages =====
// Recherche des espaces, annonces epinglees, identite et deconnexion. Le
// <header> existe deja sur les 43 pages : on le remplit, rien a changer
// dans leur HTML.
(function () {
  // Deux structures d'entete coexistent : .header-inner (la plupart des
  // pages) et .header-wrap (onze pages). Sans la seconde, ces pages
  // n'avaient jamais recu la barre commune.
  var entete = document.querySelector('header .header-inner, header .header-wrap');
  var onglets = document.querySelector('.member-tabs .member-tabs-inner');
  if (!entete || !onglets) return;

  function ech(t) {
    return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function sansAccent(t) {
    return String(t || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }

  // ---- Destinations : les memes que la navigation, sous-menus compris ----
  var destinations = [];
  onglets.querySelectorAll('.member-tab[href], .member-sous-lien[href]').forEach(function (a) {
    destinations.push({ libelle: (a.textContent || '').trim(), href: a.getAttribute('href') });
  });

  var barre = document.createElement('div');
  barre.className = 'ms-barre';
  barre.innerHTML =
    '<form class="ms-recherche" role="search" onsubmit="return false;">'
    + '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>'
    + '<input type="search" id="rechercheEspaces" autocomplete="off" role="combobox"'
    + ' aria-expanded="false" aria-autocomplete="list" aria-controls="msSuggestions"'
    + ' placeholder="Rechercher un espace\u2026" aria-label="Rechercher un espace">'
    + '<div class="ms-suggestions" id="msSuggestions" role="listbox"></div>'
    + '</form>'
    + '<div class="ms-outils">'
    + '<button type="button" class="ms-cloche" id="clocheBtn" aria-label="Annonces">'
    + '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 9a6 6 0 1 0-12 0c0 5-2 6.5-2 6.5h16S18 14 18 9z"/>'
    + '<path d="M13.7 19a2 2 0 0 1-3.4 0"/></svg><span class="ms-point" id="clochePoint"></span></button>'
    + '<span class="ms-membre"><span class="ms-avatar" id="avatarEl">?</span>'
    + '<span class="ms-nom" id="membreNom">Membre</span></span>'
    + '</div>';
  entete.appendChild(barre);

  // Le bouton de deconnexion existait deja : il rejoint le groupe de droite
  // plutot que d'etre reconstruit - il porte ses propres ecouteurs.
  var outils = barre.querySelector('.ms-outils');
  var deco = entete.querySelector('.signout-btn');
  if (deco) outils.appendChild(deco);

  // ---- Recherche : propose les destinations, Entree ouvre la premiere ----
  var champ = barre.querySelector('#rechercheEspaces');
  var liste = barre.querySelector('#msSuggestions');
  var vise = -1;

  function fermer() {
    liste.classList.remove('ouvert');
    champ.setAttribute('aria-expanded', 'false');
    vise = -1;
  }
  function resultats() {
    var q = sansAccent(champ.value).trim();
    if (q === '') return [];
    return destinations.filter(function (d) { return sansAccent(d.libelle).indexOf(q) !== -1; });
  }
  function dessiner() {
    var trouves = resultats();
    if (champ.value.trim() === '') { fermer(); return; }
    liste.innerHTML = trouves.length
      ? trouves.map(function (d) {
          return '<a class="ms-suggestion" role="option" href="' + ech(d.href) + '">' + ech(d.libelle) + '</a>';
        }).join('')
      : '<p class="ms-suggestion-vide">Aucun espace ne correspond.</p>';
    liste.classList.add('ouvert');
    champ.setAttribute('aria-expanded', 'true');
    vise = -1;
  }
  function deplacer(pas) {
    var items = liste.querySelectorAll('.ms-suggestion');
    if (items.length === 0) return;
    if (vise >= 0) items[vise].classList.remove('vise');
    vise = (vise + pas + items.length) % items.length;
    items[vise].classList.add('vise');
    items[vise].scrollIntoView({ block: 'nearest' });
  }
  // ---- Page qui a sa propre recherche : la barre du haut la remplace ----
  // Un seul champ par page. Le champ de la page reste dans le document (son
  // filtre le lit) mais disparait ; la saisie du haut y est recopiee.
  var champsPage = document.querySelectorAll('[data-recherche-page]');
  var champPage = champsPage.length === 1 ? champsPage[0] : null;
  if (champPage) {
    var aide = champPage.getAttribute('placeholder') || 'Rechercher\u2026';
    champ.setAttribute('placeholder', aide);
    champ.setAttribute('aria-label', champPage.getAttribute('aria-label') || aide);
    champ.removeAttribute('role');
    champ.removeAttribute('aria-expanded');
    champ.removeAttribute('aria-autocomplete');
    champ.removeAttribute('aria-controls');
    (champPage.closest('[data-recherche-cacher]') || champPage).classList.add('ms-recherche-reprise');
    var transmettre = function () {
      champPage.value = champ.value;
      champPage.dispatchEvent(new Event('input', { bubbles: true }));
      champPage.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
    };
    champ.addEventListener('input', transmettre);
    // Le type « search » offre une croix d'effacement : elle declenche
    // « search » et pas toujours « input ».
    champ.addEventListener('search', transmettre);
    champ.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') e.preventDefault();
      if (e.key === 'Escape') { champ.value = ''; transmettre(); }
    });
  } else {
  champ.addEventListener('input', dessiner);
  champ.addEventListener('focus', function () { if (champ.value.trim() !== '') dessiner(); });
  champ.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowDown') { e.preventDefault(); deplacer(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); deplacer(-1); }
    else if (e.key === 'Escape') { fermer(); }
    else if (e.key === 'Enter') {
      var items = liste.querySelectorAll('.ms-suggestion');
      var cible = vise >= 0 ? items[vise] : items[0];
      if (cible) { e.preventDefault(); window.location.href = cible.getAttribute('href'); }
    }
  });
  }
  document.addEventListener('click', function (e) {
    if (!barre.contains(e.target)) fermer();
  });

  // ---- Identite : publiee par supabase-client.js une fois la session sure ----
  function poserMembre(profil) {
    if (!profil) return;
    var nom = profil.full_name || [profil.first_name, profil.last_name].filter(Boolean).join(' ')
      || profil.email || 'Membre';
    var prenom = profil.first_name || nom.split(' ')[0];
    var elNom = document.getElementById('membreNom');
    var elAvatar = document.getElementById('avatarEl');
    if (elNom) elNom.textContent = prenom;
    if (elAvatar && !elAvatar.dataset.rempli) {
      elAvatar.dataset.rempli = '1';
      elAvatar.textContent = nom.split(' ').map(function (p) { return p[0]; })
        .filter(Boolean).slice(0, 2).join('').toUpperCase();
    }
  }
  if (window.profilMembre) poserMembre(window.profilMembre);
  window.addEventListener('membre-pret', function (e) { poserMembre(e.detail); });

  // ---- Annonces epinglees ----
  var voile = document.createElement('div');
  voile.className = 'ms-annonces';
  voile.id = 'msAnnonces';
  voile.innerHTML =
    '<div class="ms-annonces-boite">'
    + '<div class="ms-annonces-tete">'
    + '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10.5v3a1.5 1.5 0 0 0 1.5 1.5H8l6 4V6.5l-6 4H5.5A1.5 1.5 0 0 0 4 12z"/>'
    + '<path d="M17.5 9.2a4 4 0 0 1 0 5.6"/></svg>'
    + '<p class="ms-annonces-titre">Annonces</p></div>'
    + '<div class="ms-annonces-corps" id="msAnnoncesCorps"></div>'
    + '<div class="ms-annonces-pied"><button type="button" class="ms-annonces-ok" id="msAnnoncesOk">Ok</button></div>'
    + '</div>';
  document.body.appendChild(voile);

  var corps = voile.querySelector('#msAnnoncesCorps');
  var point = barre.querySelector('#clochePoint');
  var signatureVue = '';
  var defilY = 0;

  function bloquer() {
    defilY = window.scrollY || 0;
    document.body.style.position = 'fixed';
    document.body.style.top = -defilY + 'px';
    document.body.style.left = '0';
    document.body.style.right = '0';
    document.body.style.width = '100%';
  }
  function debloquer() {
    document.body.style.position = '';
    document.body.style.top = '';
    document.body.style.left = '';
    document.body.style.right = '';
    document.body.style.width = '';
    window.scrollTo(0, defilY);
  }
  function ouvrir() {
    if (!corps.innerHTML.trim()) {
      corps.innerHTML = '<div class="ms-annonce"><p class="ms-annonce-texte">Aucune annonce pour le moment.</p></div>';
    }
    point.classList.remove('visible');
    bloquer();
    voile.classList.add('ouvert');
  }
  function fermerAnnonces() {
    if (signatureVue) { try { sessionStorage.setItem('amstc-ann-seen', signatureVue); } catch (e) {} }
    voile.classList.remove('ouvert');
    debloquer();
  }
  barre.querySelector('#clocheBtn').addEventListener('click', ouvrir);
  voile.querySelector('#msAnnoncesOk').addEventListener('click', fermerAnnonces);
  voile.addEventListener('click', function (e) { if (e.target === voile) fermerAnnonces(); });

  // Les annonces deja fermees ne rouvrent pas d'elles-memes, mais la cloche
  // doit pouvoir les rappeler : on prepare le contenu dans tous les cas.
  (async function () {
    if (typeof supabaseClient === 'undefined') return;
    try {
      var r = await supabaseClient.from('member_announcements')
        .select('id,title,body,image_path').eq('is_pinned', true).eq('is_active', true)
        .order('created_at', { ascending: false });
      var data = r && r.data;
      if (r && r.error) return;
      if (!data || data.length === 0) return;

      var signature = data.map(function (a) { return a.id; }).sort().join(',');
      signatureVue = signature;
      var dejaVues = false;
      try { dejaVues = sessionStorage.getItem('amstc-ann-seen') === signature; } catch (e) {}

      var chemins = data.map(function (a) { return a.image_path; }).filter(Boolean);
      var urls = {};
      if (chemins.length > 0) {
        var s = await supabaseClient.storage.from('annonce-photos').createSignedUrls(chemins, 3600);
        (s && s.data ? s.data : []).forEach(function (x) { if (x.signedUrl) urls[x.path] = x.signedUrl; });
      }
      corps.innerHTML = data.map(function (a) {
        return '<div class="ms-annonce">'
          + (a.image_path && urls[a.image_path] ? '<img src="' + ech(urls[a.image_path]) + '" alt="">' : '')
          + (a.title ? '<p class="ms-annonce-titre">' + ech(a.title) + '</p>' : '')
          + (a.body ? '<p class="ms-annonce-texte">' + ech(a.body) + '</p>' : '')
          + '</div>';
      }).join('');
      point.classList.add('visible');
      if (!dejaVues) { bloquer(); voile.classList.add('ouvert'); }
    } catch (e) { /* l'absence d'annonces ne doit rien bloquer */ }
  })();
})();
