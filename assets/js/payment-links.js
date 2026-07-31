// Liens de paiement (Wave, Orange Money…) partagés entre la page publique
// "Faire un don" et l'espace membres (boutique, cotisations, validité de
// carte).
//
// Source unique : content/don.json, modifiable depuis le CMS
// (Administration > Page d'accueil > Faire un don > Options Mobile Money >
// "Lien de paiement"). Un seul endroit à mettre à jour le jour où le lien
// Wave change, et il s'applique partout.

(function (global) {
  // Les pages de l'espace membres vivent dans /membres/, les pages publiques
  // à la racine : le chemin vers le fichier de contenu diffère.
  const CONTENT_URL = location.pathname.includes("/membres/")
    ? "../content/don.json"
    : "content/don.json";

  // "Orange Money" -> "orange_money", pour correspondre aux valeurs déjà
  // utilisées en base (colonnes payment_method).
  function methodKey(operator) {
    return (operator || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .trim()
      .replace(/\s+/g, "_");
  }

  // N'accepte qu'une vraie URL http(s) : une saisie du type "javascript:..."
  // dans le CMS ne doit jamais devenir un lien cliquable.
  function safeUrl(u) {
    return /^https?:\/\//i.test((u || "").trim()) ? u.trim() : "";
  }

  let cache = null;

  /**
   * Retourne un objet { wave: "https://…", orange_money: "…" } ne contenant
   * que les opérateurs pour lesquels un lien valide est configuré.
   * Ne rejette jamais : sans lien configuré (ou en cas d'erreur réseau), on
   * renvoie un objet vide et l'appelant n'affiche simplement aucun bouton.
   */
  async function getPaymentLinks() {
    if (cache) return cache;
    try {
      const res = await fetch(CONTENT_URL);
      if (!res.ok) return (cache = {});
      const data = await res.json();
      const links = {};
      (Array.isArray(data.mobile_options) ? data.mobile_options : []).forEach((m) => {
        const url = safeUrl(m && m.link);
        if (url) links[methodKey(m.operator)] = url;
      });
      return (cache = links);
    } catch (e) {
      return (cache = {});
    }
  }

  global.getPaymentLinks = getPaymentLinks;
})(window);
