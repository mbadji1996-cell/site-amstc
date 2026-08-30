/* ============================================================
   Service worker - AMSTC
   Stratégie volontairement simple pour un site statique :
   - Pages (navigation) : réseau d'abord, cache en secours, puis
     offline.html si la page n'a jamais été visitée.
   - Autres ressources (css/js/images/json) : cache d'abord avec
     mise à jour en arrière-plan (stale-while-revalidate), pour que
     la recherche et les index de contenu restent utilisables hors
     ligne après une première visite.
   Incrémenter CACHE_VERSION invalide l'ancien cache au déploiement
   suivant. À FAIRE À CHAQUE FOIS qu'un fichier de SHELL_ASSETS ou une
   feuille/script partagé change - oublié le 17/08/2026, la barre
   d'onglets ajoutée à member-nav.css est arrivée sans style sur les
   téléphones, pendant que le site en ligne était correct.

   C'est précisément parce que cet oubli est facile que les CSS et les JS
   sont passés en RÉSEAU D'ABORD ci-dessous : une correction de style ne
   doit jamais rester invisible un déploiement de plus.
   L'administration (/admin/) est volontairement exclue : c'est un outil
   de rédaction qui doit toujours refléter la dernière version en ligne.
   Servie depuis le cache, une correction n'y apparaissait qu'à la visite
   suivante - invisible dans l'application Android, qui garde son cache
   d'une session à l'autre.
   ============================================================ */
const CACHE_VERSION = "amstc-v4";
const SHELL_ASSETS = [
  "/offline.html",
  "/manifest.json",
  "/assets/icon-192.png",
  "/assets/icon-512.png",
  "/assets/css/dark-mode.css",
  "/assets/css/site-search.css",
  "/assets/js/theme-toggle.js",
  "/assets/js/site-search.js"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(
        names.filter((n) => n !== CACHE_VERSION).map((n) => caches.delete(n))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET" || !req.url.startsWith(self.location.origin)) return;
  if (new URL(req.url).pathname.startsWith("/admin/")) return;

  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_VERSION).then((cache) => cache.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((cached) => cached || caches.match("/offline.html")))
    );
    return;
  }

  // Les FEUILLES DE STYLE et les SCRIPTS passent par le réseau d'abord,
  // avec le cache en secours. Servis depuis le cache, ils faisaient vivre
  // une version du site à l'écran pendant qu'une autre était en ligne :
  // le HTML, lui, est toujours frais (navigation ci-dessus), et un HTML
  // neuf avec un CSS d'hier donne une page cassée - barre d'onglets sans
  // style, bouton de menu invisible. Hors ligne, le cache prend le
  // relais : rien n'est perdu, seul l'ordre change.
  const estCode = /\.(css|js)(\?|$)/i.test(new URL(req.url).pathname + new URL(req.url).search)
    || req.destination === "style" || req.destination === "script";

  // LES INDEX DE CONTENU AUSSI, et pour une raison qui avait ete mal vue.
  // Le commentaire plus bas les rangeait avec les images, au motif que
  // « ces fichiers changent de nom quand ils changent ». C'est vrai d'une
  // photo, dont le nom porte le contenu ; c'est FAUX de
  // content/actualites-index.json, qui garde son nom pour toujours et dont
  // seul le contenu change - a chaque publication. Servi depuis le cache,
  // il affichait la liste d'hier : un article publie restait invisible
  // pour qui avait deja visite le site, sans le moindre message d'erreur.
  // Constate sur la publication de l'article du Gamou 2026.
  // TOUT ce qui vit sous /content/ change sans changer de nom : les index
  // .json comme les fiches .md des articles, projets et formations. Le
  // premier correctif ne visait que les .json - un article reecrit
  // s'affichait donc encore dans sa version d'hier pour qui avait deja
  // visite le site, et ne se corrigeait qu'a la visite suivante.
  // Constate en verifiant une fiche projet qui venait d'etre modifiee.
  const estIndexContenu = /^\/content\//i.test(new URL(req.url).pathname);

  if (estCode || estIndexContenu) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_VERSION).then((cache) => cache.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req))
    );
    return;
  }

  // Le reste - images, polices - garde le cache d'abord : ceux-la
  // changent bien de nom quand ils changent (image-01.jpg d'un article
  // n'est jamais remplacee par une autre photo), et leur fraicheur
  // immediate n'a aucune incidence sur l'affichage. Tout /content/,
  // en revanche, est passe plus haut : ces fichiers changent SANS changer
  // de nom.
  event.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_VERSION).then((cache) => cache.put(req, copy));
          return res;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
