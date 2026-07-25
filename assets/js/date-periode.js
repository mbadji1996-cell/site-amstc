/* ============================================================
   Formatage des dates et des périodes — AMSTC

   Une fiche (réalisation, formation, projet, étape) a toujours une date de
   référence obligatoire — c'est elle qui sert au tri, au nom du fichier et
   au regroupement dans les bilans annuels. Elle peut en plus porter une
   date de début et/ou une date de fin facultatives, pour les activités qui
   s'étalent sur plusieurs jours (72h d'activités, campagne sur deux jours,
   projet avec une échéance...).

   formatDatePeriode() choisit la formulation la plus lisible :
     - "du 19 au 24 juin 2026"            (même mois, même année)
     - "du 28 juin au 3 juillet 2026"     (mois différents, même année)
     - "du 28 décembre 2025 au 3 janvier 2026"
     - "15 février 2025"                  (date simple, comportement d'avant)

   Le fichier fonctionne à la fois dans le navigateur (variable globale
   formatDatePeriode) et dans les scripts Node (module.exports), pour que
   les pages et le générateur de bilans annuels partagent exactement la
   même logique.
   ============================================================ */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.formatDatePeriode = factory();
})(typeof self !== "undefined" ? self : this, function () {
  // timeZone UTC : les dates du CMS sont enregistrées en UTC (ex.
  // 2026-01-25T10:00:00.000Z). Sans cette option, un visiteur situé à
  // l'ouest de Greenwich verrait la veille pour les dates du matin.
  var OPTS = { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" };

  function parse(d) {
    if (!d) return null;
    if (d instanceof Date) return isNaN(d.getTime()) ? null : d;
    // Format "JJ/MM/AAAA" : produit par Decap quand date_format était défini
    // sans format de stockage (fiches enregistrées avant le correctif du
    // config.yml). new Date() l'interpréterait comme MM/JJ -> date invalide.
    var fr = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(String(d).trim());
    if (fr) return new Date(Date.UTC(+fr[3], +fr[2] - 1, +fr[1]));
    var date = new Date(d);
    return isNaN(date.getTime()) ? null : date;
  }

  function full(date) {
    return date.toLocaleDateString("fr-FR", OPTS);
  }

  function dayOnly(date) {
    return date.toLocaleDateString("fr-FR", { day: "numeric", timeZone: "UTC" });
  }

  function dayMonth(date) {
    return date.toLocaleDateString("fr-FR", { day: "numeric", month: "long", timeZone: "UTC" });
  }

  /**
   * @param {object|string} item Une fiche ({date, date_debut, date_fin}) ou
   *                             directement une date (compatibilité).
   * @returns {string} La date ou la période, prête à afficher.
   */
  return function formatDatePeriode(item) {
    if (!item) return "";
    if (typeof item === "string" || item instanceof Date) {
      var single = parse(item);
      return single ? full(single) : "";
    }

    var reference = parse(item.date);
    var debut = parse(item.date_debut) || reference;
    var fin = parse(item.date_fin);

    // Pas de période exploitable (ou fin antérieure au début, saisie
    // incohérente) : on retombe sur l'affichage d'une date simple.
    if (!debut) return "";
    if (!fin || fin.getTime() <= debut.getTime()) return full(debut);

    var memeAnnee = debut.getUTCFullYear() === fin.getUTCFullYear();
    var memeMois = memeAnnee && debut.getUTCMonth() === fin.getUTCMonth();

    if (memeMois) return "du " + dayOnly(debut) + " au " + full(fin);
    if (memeAnnee) return "du " + dayMonth(debut) + " au " + full(fin);
    return "du " + full(debut) + " au " + full(fin);
  };
});
