/* ============================================================
   Lecture d'une fiche : sommaire et articles proches
   ------------------------------------------------------------
   Deux aides communes aux pages article.html et formation.html :

     lectureSommaire(corps, cible)
        construit le sommaire a partir des titres du texte, et
        souligne celui qu'on est en train de lire.

     lectureProches({fichier, slug, categorie, page, cible, libelles})
        propose trois fiches voisines, de la meme categorie quand il
        y en a, sinon les plus recentes.

   Les deux s'effacent quand il n'y a rien a montrer : un sommaire
   d'un seul titre, ou une liste vide, n'apprend rien.
   ============================================================ */
(function () {
  function ech(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function sansAccent(s) {
    return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  }

  function identifiant(texte, pris) {
    var base = sansAccent(texte).replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'section';
    var id = base, n = 2;
    while (pris[id]) { id = base + '-' + n; n++; }
    pris[id] = true;
    return id;
  }

  function lectureSommaire(corps, cible) {
    if (!corps || !cible) return false;
    // Un contenu importe apporte deja son propre sommaire : on ne lui en
    // superpose pas un second.
    if (corps.querySelector('.html-importe nav a[href^="#"]')) { cible.style.display = 'none'; return false; }
    var titres = [].slice.call(corps.querySelectorAll('h2, h3'));
    if (titres.length < 2) { cible.style.display = 'none'; return false; }

    var pris = {};
    var liens = titres.map(function (t) {
      if (!t.id) t.id = identifiant(t.textContent, pris); else pris[t.id] = true;
      return '<a href="#' + ech(t.id) + '" class="' + (t.tagName === 'H3' ? 'niveau-3' : 'niveau-2') + '" data-cible="' + ech(t.id) + '">'
        + '<span class="lc-som-num"></span><span>' + ech(t.textContent.trim()) + '</span></a>';
    }).join('');

    var zone = cible.querySelector('.lc-som');
    if (!zone) return false;
    zone.innerHTML = liens;
    // Les numeros ne comptent que les grands titres : un sous-titre suit
    // le sien, il n'ouvre pas une nouvelle partie.
    var n = 0;
    [].forEach.call(zone.querySelectorAll('a'), function (a) {
      if (a.classList.contains('niveau-3')) return;
      n++;
      a.querySelector('.lc-som-num').textContent = String(n);
    });
    cible.style.display = '';

    // Le titre en cours de lecture est souligne.
    if (window.IntersectionObserver) {
      var vus = {};
      var obs = new IntersectionObserver(function (entrees) {
        entrees.forEach(function (e) { vus[e.target.id] = e.isIntersecting; });
        var courant = titres.filter(function (t) { return vus[t.id]; })[0];
        [].forEach.call(zone.querySelectorAll('a'), function (a) {
          a.classList.toggle('actif', !!courant && a.dataset.cible === courant.id);
        });
      }, { rootMargin: '-90px 0px -70% 0px' });
      titres.forEach(function (t) { obs.observe(t); });
    }
    return true;
  }

  function dateCourte(d) {
    if (!d) return '';
    var date = new Date(d);
    if (isNaN(date)) return '';
    return date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
  }

  function lectureProches(options) {
    var cible = options.cible;
    if (!cible) return;
    fetch(options.fichier)
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (liste) {
        var autres = (liste || []).filter(function (a) { return a.slug !== options.slug; });
        var memeType = options.categorie
          ? autres.filter(function (a) { return a.categorie === options.categorie; })
          : [];
        // De la meme categorie d'abord, completees par les plus recentes.
        var choix = memeType.concat(autres.filter(function (a) { return memeType.indexOf(a) === -1; })).slice(0, 3);
        if (!choix.length) { cible.style.display = 'none'; return; }
        var zone = cible.querySelector('.lc-proches');
        zone.innerHTML = choix.map(function (a) {
          return '<a class="lc-proche" href="' + ech(options.page) + '?slug=' + encodeURIComponent(a.slug) + '">'
            + '<span class="lc-proche-vignette">'
            + (a.image ? '<img src="' + ech(a.image) + '" alt="" loading="lazy">' : '<i class="ti ti-photo"></i>')
            + '</span><span><span class="lc-proche-titre">' + ech(a.title || 'Sans titre') + '</span>'
            + '<span class="lc-proche-date"><i class="ti ti-calendar" aria-hidden="true"></i> '
            + ech(dateCourte(a.date)) + '</span></span></a>';
        }).join('');
        cible.style.display = '';
      })
      .catch(function () { cible.style.display = 'none'; });
  }

  window.lectureSommaire = lectureSommaire;
  window.lectureProches = lectureProches;
})();

/* ============================================================
   Gabarit d'une fiche : bandeau, texte, colonne de droite
   Utilise par article.html et formation.html, pour que les deux
   pages s'ouvrent de la meme facon.
   ============================================================ */
(function () {
  function ech(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // o = { badge, badgeIcone, retourHref, retourTexte, date, titre, intro,
  //       chips:[{icone, texte, or}], image, videoId, avant, corps,
  //       titreProches, lienProches, lienProchesTexte }
  function lectureGabarit(o) {
    var chips = (o.chips || []).filter(function (c) { return c && c.texte; }).map(function (c) {
      return '<span class="lc-chip' + (c.or ? ' lc-chip-or' : '') + '">'
        + '<i class="ti ' + ech(c.icone || 'ti-tag') + '" aria-hidden="true"></i> ' + ech(c.texte) + '</span>';
    }).join('');

    return ''
      + '<section class="lc-hero"><div class="wrap lc-hero-in">'
      + '<div class="lc-hero-texte">'
      + (o.retourHref ? '<a class="lc-retour" href="' + ech(o.retourHref) + '">'
          + '<i class="ti ti-arrow-left" aria-hidden="true"></i> ' + ech(o.retourTexte || 'Retour') + '</a>' : '')
      + '<p><span class="lc-badge"><i class="ti ' + ech(o.badgeIcone || 'ti-news') + '" aria-hidden="true"></i> '
      + ech(o.badge || '') + '</span></p>'
      + (o.date ? '<p class="lc-date"><i class="ti ti-calendar" aria-hidden="true"></i> ' + o.date + '</p>' : '')
      + '<h1>' + ech(o.titre || '') + '</h1>'
      + (o.intro ? '<p class="lc-intro">' + ech(o.intro) + '</p>' : '')
      + (chips ? '<div class="lc-chips">' + chips + '</div>' : '')
      + '<div id="partageZone" class="partage-zone"></div>'
      + '</div>'
      + (o.image ? '<figure class="lc-hero-photo"><img src="' + ech(o.image) + '" alt=""></figure>' : '')
      + '</div></section>'

      + '<div class="wrap lc-corps">'
      + '<article class="lc-texte">'
      + (o.videoId ? '<div class="video-embed"><iframe src="https://www.youtube.com/embed/' + ech(o.videoId)
          + '" title="Vidéo YouTube" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"'
          + ' allowfullscreen></iframe></div>' : '')
      + (o.avant || '')
      + (o.corps === null || o.corps === undefined ? '' : '<div id="body">' + o.corps + '</div>')
      + '</article>'
      + '<aside class="lc-aside">'
      + '<details class="lc-carte" id="lcSommaire" open style="display:none;">'
      + '<summary class="lc-carte-tete"><span class="lc-carte-ic" aria-hidden="true"><i class="ti ti-list-numbers"></i></span>'
      + '<span class="lc-carte-titre">Sommaire</span></summary><div class="lc-som"></div></details>'
      + '<div class="lc-carte" id="lcProches" style="display:none;">'
      + '<div class="lc-carte-tete"><span class="lc-carte-ic" aria-hidden="true"><i class="ti ti-stack-2"></i></span>'
      + '<span class="lc-carte-titre">' + ech(o.titreProches || 'À lire aussi') + '</span>'
      + (o.lienProches ? '<a class="lc-carte-lien" href="' + ech(o.lienProches) + '">'
          + ech(o.lienProchesTexte || 'Voir tout') + '</a>' : '')
      + '</div><div class="lc-proches"></div></div>'
      + '</aside></div>';
  }

  window.lectureGabarit = lectureGabarit;
})();
