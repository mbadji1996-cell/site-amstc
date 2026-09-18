/* ============================================================
   Bandeaux de l'espace membres : textes et photo depuis le CMS
   ------------------------------------------------------------
   Chaque page pose son bandeau en HTML - ce qui s'affiche tout de
   suite, et ce qui reste si le fichier de contenu n'arrive pas -
   puis ce script y applique ce qui a été écrit dans le CMS
   (content/espace-membre-bandeaux.json).

   Convention, dans la page :
     <section class="bm" data-bandeau="daara">
       ...
       <h1 data-bandeau-champ="titre">Espace Daara</h1>
       <p data-bandeau-champ="soustitre">…</p>
       <p data-bandeau-champ="texte">…</p>
       <a data-bandeau-champ="bouton" href="…">…</a>
       <div class="bm-photo" data-bandeau-champ="image" style="display:none;">
         <img alt=""></div>
     </section>

   La photo : celle de la page si le CMS en donne une, sinon celle
   de l'espace membres (content/espace-membre.json), pour qu'un
   bandeau ne reste pas nu quand personne n'a encore choisi d'image.
   ============================================================ */
(function () {
  var bandeau = document.querySelector('[data-bandeau]');
  if (!bandeau) return;
  var cle = bandeau.getAttribute('data-bandeau');

  function champ(nom) {
    return bandeau.querySelector('[data-bandeau-champ="' + nom + '"]');
  }

  function poserTexte(nom, valeur) {
    var el = champ(nom);
    if (!el || !valeur) return;
    // Le bouton garde son icône : seul son libellé change.
    var texte = el.querySelector('.bm-bouton-texte');
    (texte || el).textContent = valeur;
  }

  function poserPhoto(url) {
    var zone = champ('image');
    if (!zone || !url) return;
    var img = zone.querySelector('img');
    if (!img) return;
    img.src = url;
    zone.style.display = '';
  }

  function lire(adresse) {
    return fetch(adresse + '?t=' + Date.now())
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }

  Promise.all([
    lire('../content/espace-membre-bandeaux.json'),
    lire('../content/espace-membre.json'),
  ]).then(function (parts) {
    var tout = parts[0] || {};
    var espace = parts[1] || {};
    var d = tout[cle] || {};

    poserTexte('titre', d.titre);
    poserTexte('soustitre', d.soustitre);
    poserTexte('texte', d.texte);
    poserTexte('bouton', d.bouton);

    var lien = champ('bouton');
    if (lien && d.bouton_lien) lien.setAttribute('href', d.bouton_lien);

    poserPhoto(d.image || espace.image);
  });
})();
