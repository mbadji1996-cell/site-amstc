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

  var toggle = document.createElement('button');
  toggle.type = 'button';
  toggle.className = 'member-nav-toggle';
  toggle.setAttribute('aria-expanded', 'false');
  toggle.innerHTML = '<span></span><span class="mn-burger" aria-hidden="true">☰</span>';
  toggle.firstChild.textContent = activeLabel;

  toggle.addEventListener('click', function () {
    var open = panel.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(open));
  });

  tabs.insertBefore(toggle, inner);
  tabs.appendChild(panel);
  tabs.classList.add('has-mobile-nav');
})();
