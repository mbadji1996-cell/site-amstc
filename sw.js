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
   suivant.
   L'administration (/admin/) est volontairement exclue : c'est un outil
   de rédaction qui doit toujours refléter la dernière version en ligne.
   Servie depuis le cache, une correction n'y apparaissait qu'à la visite
   suivante - invisible dans l'application Android, qui garde son cache
   d'une session à l'autre.
   ============================================================ */
const CACHE_VERSION = "amstc-v2";
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
