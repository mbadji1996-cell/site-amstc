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
const CACHE_VERSION = "amstc-v3";
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

  if (estCode) {
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

  // Le reste - images, polices, index de contenu - garde le cache
  // d'abord : ces fichiers changent de nom quand ils changent, et leur
  // fraîcheur immédiate n'a pas d'incidence sur l'affichage.
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
