/* ============================================================
   Pastilles de filtre repliées sur téléphone
   ------------------------------------------------------------
   Dix-sept activités font dix-sept pastilles : sur un téléphone,
   elles remplissaient tout l'écran avant la première carte. Un
   bouton les remplace, qui porte le filtre en cours et ouvre la
   liste à la demande ; choisir referme.

   Sur grand écran, rien ne change : le bouton reste caché et les
   pastilles s'affichent sur une rangée.
   ============================================================ */
(function () {
  var zone = document.querySelector('.rl-cats');
  if (!zone || !zone.parentElement) return;

  var bouton = document.createElement('button');
  bouton.type = 'button';
  bouton.className = 'rl-filtre-bouton';
  bouton.setAttribute('aria-expanded', 'false');
  bouton.innerHTML =
    '<i class="ti ti-filter" aria-hidden="true"></i>'
    + '<span class="rl-filtre-texte">Filtrer</span>'
    + '<i class="ti ti-chevron-down rl-filtre-chevron" aria-hidden="true"></i>';
  zone.parentElement.insertBefore(bouton, zone);

  function majTexte() {
    var actif = zone.querySelector('.rl-cat.actif');
    bouton.querySelector('.rl-filtre-texte').textContent =
      actif ? actif.textContent.trim() : 'Filtrer';
  }

  bouton.addEventListener('click', function () {
    var ouvert = zone.classList.toggle('ouvert');
    bouton.setAttribute('aria-expanded', String(ouvert));
  });

  // Les pastilles sont reconstruites par la page : on ecoute le
  // conteneur, pas chaque bouton.
  zone.addEventListener('click', function (e) {
    if (!e.target.closest('.rl-cat')) return;
    zone.classList.remove('ouvert');
    bouton.setAttribute('aria-expanded', 'false');
    setTimeout(majTexte, 0);
  });

  if (window.MutationObserver) {
    new MutationObserver(majTexte).observe(zone, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['class'],
    });
  }
  majTexte();
})();
