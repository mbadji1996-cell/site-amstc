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
      parent.addEventListener('click', function (e) {
        e.stopPropagation();
        var ouvert = groupe.classList.toggle('ouvert');
        parent.setAttribute('aria-expanded', String(ouvert));
      });
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
