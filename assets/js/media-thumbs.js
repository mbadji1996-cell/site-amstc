// Vignettes de la Médiathèque
//
// Problème résolu : les grilles affichaient les photos en pleine résolution
// (1920 px, 300-700 Ko) dans des tuiles de 150 à 240 px. Un album de 40
// photos faisait donc télécharger ~16 Mo au lieu des ~600 Ko nécessaires.
//
// Ce module demande à Supabase Storage des versions redimensionnées côté
// serveur (imgproxy). Deux limites de l'API imposent la forme du code :
//
//   - createSignedUrls() (au pluriel) n'accepte PAS d'option de
//     transformation : il faut donc une requête par photo, d'où la limite
//     de parallélisme ci-dessous.
//   - la transformation d'images n'est pas activée sur toutes les
//     instances auto-hébergées. On la teste une seule fois par page ; si
//     elle est indisponible, on retombe silencieusement sur les URLs
//     pleine taille, exactement le comportement d'avant. La galerie ne
//     peut donc pas casser à cause de ce module.
//
// Les photos en plein écran (lightbox) doivent continuer d'utiliser les
// URLs pleine taille : n'appelez ce module que pour les vignettes.

(function (global) {
  "use strict";

  var PARALLELISME = 6;
  // Au-delà de ce nombre, demander une URL par photo devient plus lent que
  // le gain obtenu : on repasse alors à la requête groupée pleine taille
  // (une seule requête). Les pages qui affichent de gros albums doivent
  // paginer plutôt que de dépasser ce seuil.
  var SEUIL_LOT = 80;
  // null = pas encore testé, true/false une fois connu (par chargement de page)
  var transformationDisponible = null;

  function client() {
    return global.supabaseClient;
  }

  // Exécute fn sur chaque élément, au plus `limite` en même temps.
  async function parCourantes(elements, limite, fn) {
    var suivant = 0;
    async function ouvrier() {
      while (true) {
        var i = suivant++;
        if (i >= elements.length) return;
        await fn(elements[i]);
      }
    }
    var ouvriers = [];
    for (var i = 0; i < Math.min(limite, elements.length); i++) ouvriers.push(ouvrier());
    await Promise.all(ouvriers);
  }

  // Comportement historique : une seule requête, images pleine taille.
  async function urlsPleineTaille(bucket, chemins, expiration) {
    var map = {};
    if (!chemins.length) return map;
    var res = await client().storage.from(bucket).createSignedUrls(chemins, expiration);
    (res.data || []).forEach(function (s) {
      if (s.signedUrl) map[s.path] = s.signedUrl;
    });
    return map;
  }

  async function urlVignette(bucket, chemin, expiration, transform) {
    var res = await client().storage
      .from(bucket)
      .createSignedUrl(chemin, expiration, { transform: transform });
    if (res.error || !res.data || !res.data.signedUrl) return null;
    return res.data.signedUrl;
  }

  /**
   * Renvoie un objet { chemin: url } d'URLs signées vers des vignettes.
   *
   * @param {string} bucket   nom du bucket Storage
   * @param {string[]} chemins  chemins des fichiers (doublons et valeurs
   *                            vides ignorés)
   * @param {object} [options]  { largeur, hauteur, qualite, expiration }
   *                            largeur/hauteur en pixels réels : passez le
   *                            double de la taille CSS pour rester net sur
   *                            les écrans haute densité.
   */
  async function vignettes(bucket, chemins, options) {
    options = options || {};
    var largeur = options.largeur || 300;
    var hauteur = options.hauteur || largeur;
    var expiration = options.expiration || 3600;
    var transform = {
      width: largeur,
      height: hauteur,
      resize: "cover",
      quality: options.qualite || 70,
    };

    var uniques = [];
    var vus = {};
    (chemins || []).forEach(function (c) {
      if (c && !vus[c]) { vus[c] = true; uniques.push(c); }
    });
    if (!uniques.length) return {};
    if (!client()) return {};

    if (transformationDisponible === false || uniques.length > SEUIL_LOT) {
      return urlsPleineTaille(bucket, uniques, expiration);
    }

    var map = {};

    // Premier appel = test de disponibilité de la transformation.
    if (transformationDisponible === null) {
      var premiere;
      try {
        premiere = await urlVignette(bucket, uniques[0], expiration, transform);
      } catch (e) {
        premiere = null;
      }
      if (!premiere) {
        transformationDisponible = false;
        return urlsPleineTaille(bucket, uniques, expiration);
      }
      transformationDisponible = true;
      map[uniques[0]] = premiere;
      uniques = uniques.slice(1);
    }

    var echecs = [];
    await parCourantes(uniques, PARALLELISME, async function (chemin) {
      var url = null;
      try {
        url = await urlVignette(bucket, chemin, expiration, transform);
      } catch (e) {
        url = null;
      }
      if (url) map[chemin] = url;
      else echecs.push(chemin);
    });

    // Une photo dont la vignette a échoué reste affichée en pleine taille
    // plutôt que de laisser un trou dans la grille.
    if (echecs.length) {
      var secours = await urlsPleineTaille(bucket, echecs, expiration);
      Object.keys(secours).forEach(function (c) { map[c] = secours[c]; });
    }

    return map;
  }

  /**
   * Compte les photos de chaque album, sans rapatrier les photos.
   *
   * L'approche d'origine (select de toutes les lignes de media_photos, puis
   * comptage dans le navigateur) dépassait le délai maximal au-delà de
   * quelques milliers de photos : l'erreur était ignorée et tous les albums
   * affichaient 0.
   *
   * @param {string[]} folderIds  identifiants des albums
   * @returns {Promise<object>}   { folderId: nombre }
   */
  async function comptePhotos(folderIds) {
    var parDossier = {};
    if (!client() || !folderIds || !folderIds.length) return parDossier;

    // Voie rapide : une requête (nécessite phase36-mediatheque-performance.sql)
    var res = await client().rpc("media_photo_counts");
    if (!res.error && Array.isArray(res.data)) {
      res.data.forEach(function (l) {
        parDossier[l.folder_id] = Number(l.photo_count) || 0;
      });
      return parDossier;
    }

    // Repli si la fonction n'existe pas encore en base : un comptage par
    // album, sans transfert de lignes (head: true).
    console.warn("media_photo_counts indisponible, comptage album par album", res.error);
    var i = 0;
    async function ouvrier() {
      while (i < folderIds.length) {
        var id = folderIds[i++];
        var r = await client()
          .from("media_photos")
          .select("id", { count: "exact", head: true })
          .eq("folder_id", id);
        parDossier[id] = r.count || 0;
      }
    }
    var ouvriers = [];
    for (var k = 0; k < Math.min(4, folderIds.length); k++) ouvriers.push(ouvrier());
    await Promise.all(ouvriers);
    return parDossier;
  }

  global.mediaVignettes = vignettes;
  global.mediaComptePhotos = comptePhotos;
})(window);
