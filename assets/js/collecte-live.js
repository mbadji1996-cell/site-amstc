/* ============================================================
   Chiffres de collecte en direct - AMSTC

   LE BESOIN. Une fiche projet qui appelle aux dons annonce un montant
   déjà réuni. Écrit en dur, ce montant vieillit dès le premier don
   suivant : la page dit 406 000 quand la collecte en est à 900 000, et
   c'est l'inverse de l'effet recherché.

   POURQUOI CE N'EST PAS DANS LA FICHE. Le corps d'un article ou d'un
   projet est désinfecté avant affichage : les <script> y sont retirés,
   et c'est bien ainsi - un contenu rédigé dans le CMS ne doit pas
   pouvoir exécuter de code. La fiche se contente donc de MARQUER ses
   chiffres, et ce script, chargé par la page elle-même, les remplit.

   COMMENT MARQUER, dans le HTML d'une fiche :

     <b data-collecte="objectif">5 000 000 F</b>
     <b data-collecte="montant">406 000 F</b>
     <b data-collecte="reste">4 594 000 F</b>
     <b data-collecte="pourcentage">8 %</b>
     <b data-collecte="echeance">31 déc. 2026</b>

   Un conteneur marqué « data-collecte-bloc » disparaît quand aucune
   campagne n'est active - utile pour une pastille ou un encart qui n'ont
   rien à dire en dehors d'une collecte.

   LE TEXTE ÉCRIT DANS LA FICHE SERT DE REPLI. Si le serveur ne répond
   pas, ou si aucune campagne n'est active, on ne remplace rien : le
   lecteur voit le dernier chiffre connu plutôt qu'un tiret. Un chiffre
   un peu ancien vaut mieux qu'une case vide sur une page qui demande
   de la confiance.

   Le contenu des fiches arrive APRÈS le chargement de la page : on
   observe donc le document, et l'on remplit les marques dès qu'elles
   apparaissent.
   ============================================================ */
(function () {
  var API = "https://api.amstc.org";
  var CLE = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc4NDg3MTA2MCwiZXhwIjo0OTQwNTQ0NjYwLCJyb2xlIjoiYW5vbiJ9.At_rHwK9bgTh4eoh1ykkLGaPiVXpZBpXxtgDb_allaM";

  var promesse = null;
  function campagne() {
    if (promesse) return promesse;
    promesse = fetch(API + "/rest/v1/rpc/campagne_don_publique", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: CLE,
        Authorization: "Bearer " + CLE,
      },
      body: "{}",
    })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
    return promesse;
  }

  function fcfa(n) {
    return Number(n || 0).toLocaleString("fr-FR") + " F";
  }

  function dateCourte(d) {
    if (!d) return null;
    var t = new Date(d + "T00:00:00");
    if (isNaN(t)) return null;
    return t.toLocaleDateString("fr-FR", { day: "numeric", month: "short", year: "numeric" });
  }

  function valeur(cle, c) {
    var objectif = Number(c.objectif) || 0;
    var collecte = Math.max(0, Number(c.collecte) || 0);
    if (cle === "objectif") return objectif ? fcfa(objectif) : null;
    if (cle === "montant") return fcfa(collecte);
    if (cle === "reste") return objectif ? fcfa(Math.max(0, objectif - collecte)) : null;
    if (cle === "pourcentage") {
      return objectif ? Math.min(100, Math.round((collecte / objectif) * 100)) + " %" : null;
    }
    if (cle === "titre") return c.titre || null;
    if (cle === "echeance") return dateCourte(c.echeance);
    return null;
  }

  function remplir(racine) {
    var marques = (racine || document).querySelectorAll("[data-collecte]");
    if (!marques.length) return;
    campagne().then(function (c) {
      // Pas de campagne active, ou serveur muet : on laisse le texte de
      // la fiche. C'est le repli voulu, pas un oubli.
      //
      // SAUF pour un bloc marque « data-collecte-bloc » : celui-la est
      // RETIRE. Une fiche peut vivre avec un chiffre un peu ancien ; une
      // pastille « Collecte - » sur un bandeau a l'air cassee, et il n'y
      // a rien d'autre a y montrer.
      if (!c) {
        document.querySelectorAll("[data-collecte-bloc]").forEach(function (b) {
          b.style.display = "none";
        });
        return;
      }
      marques.forEach(function (el) {
        if (el.getAttribute("data-collecte-fait") === "1") return;
        var v = valeur(el.getAttribute("data-collecte"), c);
        if (v === null || v === undefined) return;
        el.textContent = v;
        el.setAttribute("data-collecte-fait", "1");
      });
    });
  }

  function demarrer() {
    remplir(document);
    if (!window.MutationObserver) return;
    // Le corps des fiches est injecté après coup : on remplit les
    // marques a mesure qu'elles apparaissent.
    new MutationObserver(function () { remplir(document); })
      .observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", demarrer);
  } else {
    demarrer();
  }
})();
