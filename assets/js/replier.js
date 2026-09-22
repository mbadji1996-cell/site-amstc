/* ============================================================
   Blocs repliés sur téléphone
   ------------------------------------------------------------
   Une page d'administration aligne des chiffres, des outils et
   des filtres : sur un téléphone, cela fait deux ou trois écrans
   avant la première ligne utile. Chaque bloc marqué
   « data-replier » reçoit un bouton qui l'ouvre à la demande.

     <div class="ma-chiffres" data-replier="Chiffres"> … </div>

   Sur grand écran, le bouton reste caché par le CSS (.ma-replier
   n'apparaît que sous 760 px) et les blocs s'affichent comme
   avant : rien ne change pour l'ordinateur.
   ============================================================ */
(function () {
  var blocs = document.querySelectorAll('[data-replier]');
  if (!blocs.length) return;

  var FLECHE = '<svg class="ic ma-replier-fleche" viewBox="0 0 24 24" fill="none" stroke="currentColor"'
    + ' stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>';

  [].forEach.call(blocs, function (bloc) {
    var libelle = bloc.getAttribute('data-replier') || 'Afficher';
    var icone = bloc.getAttribute('data-replier-icone') || '';

    var bouton = document.createElement('button');
    bouton.type = 'button';
    bouton.className = 'ma-replier';
    bouton.setAttribute('aria-expanded', 'false');
    bouton.innerHTML = icone + '<span class="ma-replier-texte">' + libelle + '</span>' + FLECHE;
    bloc.parentNode.insertBefore(bouton, bloc);
    bloc.classList.add('ma-replie');

    bouton.addEventListener('click', function () {
      var ouvert = bloc.classList.toggle('ma-replie');
      // La classe CACHE le bloc : ouvert = classe absente.
      bouton.setAttribute('aria-expanded', String(!ouvert));
    });

    // Choisir une valeur referme le bloc : sur telephone, la liste
    // reprend aussitot toute la place.
    bloc.addEventListener('change', function () {
      if (window.innerWidth > 760) return;
      bloc.classList.add('ma-replie');
      bouton.setAttribute('aria-expanded', 'false');
    });
  });
})();
