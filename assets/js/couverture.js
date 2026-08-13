/**
 * Champ « image de couverture » : envoi direct ou adresse collée.
 *
 * POURQUOI UN LIEN GOOGLE DRIVE NE MARCHE PAS. Une adresse de partage
 * Drive (drive.google.com/file/d/.../view) désigne une PAGE WEB, avec sa
 * barre d'outils et son lecteur - pas un fichier image. Un navigateur à
 * qui l'on demande d'afficher cette adresse dans une balise <img> reçoit
 * du HTML et n'affiche rien. Aucun réglage de partage n'y change quoi que
 * ce soit : ce n'est pas une question de droits mais de nature.
 *
 * Drive expose bien une adresse de fichier (lh3.googleusercontent.com/d/
 * <identifiant>), reconstruite ici automatiquement pour que les liens
 * déjà collés fonctionnent. Mais elle n'est pas documentée par Google,
 * qui l'a déjà changée par le passé, et elle exige que le fichier reste
 * partagé publiquement. L'ENVOI DIRECT est donc proposé en premier : la
 * couverture vit alors sur le serveur de l'association, et ne dépend de
 * personne.
 *
 * Usage :
 *   couvertureInit('cover_image');   // l'identifiant du champ d'adresse
 *
 * Dépendances : supabase-client.js.
 */

var COUVERTURES_BUCKET = 'couvertures';

/**
 * Transforme une adresse de partage en adresse de fichier affichable.
 * Renvoie { url, converti, service } - « converti » dit si l'adresse a
 * dû être réécrite, information montrée à l'administration.
 */
function couvertureNormaliserUrl(valeur) {
  var url = String(valeur == null ? '' : valeur).trim();
  if (!url) return { url: '', converti: false, service: null };

  // Drive : /file/d/<id>/view, ou open?id=<id>, ou uc?id=<id>
  var drive = url.match(/drive\.google\.com\/file\/d\/([\w-]+)/)
           || url.match(/drive\.google\.com\/(?:open|uc)\?(?:[^#]*&)?id=([\w-]+)/);
  if (drive) {
    return { url: 'https://lh3.googleusercontent.com/d/' + drive[1],
             converti: true, service: 'Google Drive' };
  }

  // Dropbox : le paramètre dl=0 sert la page, raw=1 sert le fichier.
  if (/dropbox\.com\//.test(url) && !/[?&]raw=1/.test(url)) {
    // Le séparateur se décide sur l'adresse UNE FOIS dl retiré : le
    // tester avant produisait « image.jpg&raw=1 », sans point
    // d'interrogation, donc une adresse invalide.
    var sans = url.replace(/([?&])dl=\d&?/, '$1').replace(/[?&]$/, '');
    return { url: sans + (sans.indexOf('?') === -1 ? '?' : '&') + 'raw=1',
             converti: true, service: 'Dropbox' };
  }

  return { url: url, converti: false, service: null };
}

// Réduit l'image avant l'envoi. Une couverture s'affiche en vignette et
// comme aperçu de partage : 1200 px de côté suffisent largement, quand
// une photo de téléphone en fait 4000 et pèse plusieurs mégaoctets.
function couvertureRedimensionner(fichier, coteMax, qualite) {
  coteMax = coteMax || 1200;
  qualite = qualite || 0.82;
  return new Promise(function (resolve, reject) {
    var lecteur = new FileReader();
    lecteur.onload = function (e) {
      var img = new Image();
      img.onload = function () {
        var l = img.width, h = img.height;
        if (l > h) { if (l > coteMax) { h = h * coteMax / l; l = coteMax; } }
        else { if (h > coteMax) { l = l * coteMax / h; h = coteMax; } }
        var c = document.createElement('canvas');
        c.width = l; c.height = h;
        c.getContext('2d').drawImage(img, 0, 0, l, h);
        c.toBlob(function (blob) {
          blob ? resolve(blob) : reject(new Error('conversion impossible'));
        }, 'image/jpeg', qualite);
      };
      img.onerror = function () { reject(new Error('image illisible')); };
      img.src = e.target.result;
    };
    lecteur.onerror = reject;
    lecteur.readAsDataURL(fichier);
  });
}

function couvertureInit(champId) {
  var champ = document.getElementById(champId);
  if (!champ || champ.dataset.couvertureBranchee) return;
  champ.dataset.couvertureBranchee = '1';

  var bloc = document.createElement('div');
  bloc.className = 'couverture-bloc';
  bloc.innerHTML =
    '<div class="couverture-actions">'
    + '<button type="button" class="couverture-btn">Envoyer une image</button>'
    + '<input type="file" accept="image/*" style="display:none;">'
    + '<button type="button" class="couverture-retirer" style="display:none;">Retirer</button>'
    + '<span class="couverture-etat"></span>'
    + '</div>'
    + '<img class="couverture-apercu" alt="" style="display:none;">'
    + '<p class="couverture-note"></p>';
  champ.parentNode.insertBefore(bloc, champ.nextSibling);

  var bouton = bloc.querySelector('.couverture-btn');
  var fichierInput = bloc.querySelector('input[type="file"]');
  var retirer = bloc.querySelector('.couverture-retirer');
  var etat = bloc.querySelector('.couverture-etat');
  var apercu = bloc.querySelector('.couverture-apercu');
  var note = bloc.querySelector('.couverture-note');

  // Chaque affichage reçoit un jeton. Les images déjà remplacées peuvent
  // encore déclencher leur événement de chargement ou d'erreur bien
  // après : sans ce jeton, un événement périmé effaçait le message de
  // l'adresse en cours - constaté au test.
  var jeton = 0;

  function afficherApercu() {
    var v = champ.value.trim();
    var mien = ++jeton;
    note.textContent = '';
    note.className = 'couverture-note';

    if (!v) {
      apercu.style.display = 'none';
      apercu.removeAttribute('src');
      retirer.style.display = 'none';
      return;
    }
    retirer.style.display = '';
    apercu.style.display = '';

    // L'aperçu est la seule preuve qui vaille : une adresse peut être
    // parfaitement formée et ne rien afficher. Le dire ici évite de le
    // découvrir sur la page publique.
    apercu.onerror = function () {
      if (mien !== jeton) return;
      apercu.style.display = 'none';
      note.textContent = "Cette adresse n'affiche aucune image. Si elle vient de Google Drive "
        + "ou d'un service de partage, envoyez plutôt le fichier avec le bouton ci-dessus.";
      note.className = 'couverture-note alerte';
    };
    apercu.onload = function () {
      if (mien !== jeton) return;
      apercu.style.display = '';
    };
    apercu.src = v;
  }

  // ===== Garder l'aperçu en accord avec le champ =====
  //
  // LE PROBLÈME. Les écrans d'administration remplissent ce champ EN
  // CODE quand on ouvre un document (« .value = ... »), et le vident par
  // form.reset(). Or aucune de ces deux voies ne déclenche l'événement
  // « change » : l'aperçu gardait la couverture du document précédent,
  // et l'on croyait la nouvelle fiche déjà illustrée.
  //
  // On intercepte donc l'écriture de « value » sur CE champ, en
  // déléguant au comportement natif. Corriger ici plutôt que dans les
  // quatre écrans évite que le défaut ne revienne au prochain écran qui
  // réutilisera le module.
  var descripteur = Object.getOwnPropertyDescriptor(
    Object.getPrototypeOf(champ), 'value');
  if (descripteur && descripteur.get && descripteur.set) {
    Object.defineProperty(champ, 'value', {
      configurable: true,
      get: function () { return descripteur.get.call(this); },
      set: function (v) {
        descripteur.set.call(this, v);
        etat.textContent = '';
        afficherApercu();
      },
    });
  }

  // form.reset() ne passe pas par le descripteur : il rétablit la valeur
  // par défaut. L'événement précède la remise à zéro, d'où l'attente.
  var formulaire = champ.closest('form');
  if (formulaire) {
    formulaire.addEventListener('reset', function () {
      setTimeout(function () { etat.textContent = ''; afficherApercu(); }, 0);
    });
  }

  champ.addEventListener('change', function () {
    var n = couvertureNormaliserUrl(champ.value);
    if (n.converti) champ.value = n.url;
    // L'aperçu D'ABORD : afficherApercu vide la note, et l'écrire avant
    // revenait à l'effacer aussitôt - le message de conversion ne
    // s'affichait jamais.
    afficherApercu();
    if (n.converti) {
      note.textContent = 'Adresse ' + n.service + ' convertie en adresse d\'image. '
        + 'Elle dépend du partage public de votre fichier : l\'envoi direct est plus sûr.';
      note.className = 'couverture-note conversion';
    }
  });

  bouton.addEventListener('click', function () { fichierInput.click(); });

  retirer.addEventListener('click', function () {
    champ.value = '';
    afficherApercu();
    etat.textContent = '';
  });

  fichierInput.addEventListener('change', async function () {
    var f = fichierInput.files[0];
    if (!f) return;
    fichierInput.value = '';

    if (typeof supabaseClient === 'undefined') {
      etat.textContent = 'Envoi indisponible sur cette page.';
      return;
    }

    bouton.disabled = true;
    etat.textContent = 'Préparation…';
    try {
      var blob = await couvertureRedimensionner(f);
      etat.textContent = 'Envoi…';

      // Nom engendré : deux couvertures du même nom de fichier
      // s'écraseraient, et un nom d'origine peut contenir des caractères
      // que le stockage refuse.
      var chemin = Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.jpg';
      var r = await supabaseClient.storage.from(COUVERTURES_BUCKET)
        .upload(chemin, blob, { contentType: 'image/jpeg' });
      if (r.error) throw r.error;

      var pub = supabaseClient.storage.from(COUVERTURES_BUCKET).getPublicUrl(chemin);
      champ.value = (pub && pub.data && pub.data.publicUrl) || '';
      note.className = 'couverture-note';
      afficherApercu();
      etat.textContent = 'Image envoyée.';
    } catch (e) {
      var m = (e && e.message) || String(e);
      etat.textContent = /bucket|not found|introuvable/i.test(m)
        ? "Le script supabase/phase75-couvertures.sql n'a pas encore été exécuté."
        : 'Échec : ' + m;
    }
    bouton.disabled = false;
  });

  afficherApercu();
}
