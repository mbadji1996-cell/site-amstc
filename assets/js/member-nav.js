// Menu hamburger mobile pour la barre d'onglets de l'espace membres.
// Partagé par toutes les pages membres qui portent <nav class="member-tabs">.
// Fonctionne avec assets/css/member-nav.css : ce script construit le bouton
// et le panneau depuis les onglets déjà présents dans la page, puis pose la
// classe has-mobile-nav qui active la bascule CSS sous 880px.
(function () {
  var tabs = document.querySelector('.member-tabs');
  if (!tabs) return;
  var inner = tabs.querySelector('.member-tabs-inner');
  if (!inner) return;
  var links = inner.querySelectorAll('.member-tab');
  if (links.length === 0) return;

  var activeLabel = 'Menu';
  var panel = document.createElement('div');
  panel.className = 'member-nav-panel';
  for (var i = 0; i < links.length; i++) {
    var a = document.createElement('a');
    a.href = links[i].getAttribute('href');
    a.textContent = links[i].textContent.trim();
    if (links[i].classList.contains('active')) {
      a.className = 'active';
      activeLabel = a.textContent;
    }
    panel.appendChild(a);
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

  toggle.addEventListener('click', function () {
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
