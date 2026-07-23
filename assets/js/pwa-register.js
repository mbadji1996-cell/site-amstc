/* ============================================================
   Enregistrement du service worker — AMSTC
   Silencieux si le navigateur ne supporte pas les service workers
   ou si servi hors HTTPS/localhost (l'enregistrement échouerait).
   ============================================================ */
(function () {
  if (!("serviceWorker" in navigator)) return;
  window.addEventListener("load", function () {
    navigator.serviceWorker.register("/sw.js").catch(function () {});
  });
})();
