/**
 * Bouton « afficher / masquer » sur tous les champs de mot de passe.
 *
 * Se pose tout seul sur chaque <input type="password"> de la page, et
 * ignore ceux qui portent déjà leur propre bouton (connexion.html et
 * inscription.html en avaient un avant ce fichier) : il peut donc être
 * inclus partout sans rien casser, et couvrira les formulaires à venir.
 *
 * Saisir un mot de passe sur un clavier de téléphone est la première
 * cause d'échec à l'inscription : sans relecture possible, une faute de
 * frappe ne se découvre qu'à la première connexion.
 */
(function () {
  var OEIL = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z"/><circle cx="12" cy="12" r="3"/></svg>';
  var OEIL_BARRE = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.94 10.94 0 0 1 12 20c-7 0-11-8-11-8a21.8 21.8 0 0 1 5.06-6.06M9.9 4.24A10.94 10.94 0 0 1 12 4c7 0 11 8 11 8a21.8 21.8 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';

  function poserStyles() {
    if (document.getElementById("oeil-mdp-styles")) return;
    var s = document.createElement("style");
    s.id = "oeil-mdp-styles";
    s.textContent =
      ".champ-mdp{position:relative;}" +
      ".champ-mdp input{padding-right:44px !important;}" +
      ".btn-oeil-mdp{position:absolute;right:6px;top:50%;transform:translateY(-50%);" +
      "background:none;border:none;cursor:pointer;color:#8A9E8F;padding:6px;display:flex;align-items:center;}" +
      ".btn-oeil-mdp:hover{color:#17763B;}";
    document.head.appendChild(s);
  }

  function equiper(input) {
    // Champ déjà équipé, ici ou par la page elle-même.
    if (input.closest(".champ-mdp") || input.closest(".password-field")) return;

    poserStyles();
    var enveloppe = document.createElement("div");
    enveloppe.className = "champ-mdp";
    input.parentNode.insertBefore(enveloppe, input);
    enveloppe.appendChild(input);

    var btn = document.createElement("button");
    btn.type = "button";               // sans quoi il validerait le formulaire
    btn.className = "btn-oeil-mdp";
    btn.setAttribute("aria-label", "Afficher le mot de passe");
    btn.innerHTML = OEIL;

    btn.addEventListener("click", function () {
      var montrer = input.type === "password";
      input.type = montrer ? "text" : "password";
      btn.innerHTML = montrer ? OEIL_BARRE : OEIL;
      btn.setAttribute("aria-label", montrer ? "Masquer le mot de passe" : "Afficher le mot de passe");
      input.focus();
    });

    enveloppe.appendChild(btn);
  }

  function equiperTout() {
    document.querySelectorAll('input[type="password"]').forEach(equiper);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", equiperTout);
  } else {
    equiperTout();
  }

  // Certains formulaires sont construits en JavaScript après le chargement
  // (écran de complétion, panneaux dépliants) : on les équipe aussi.
  window.equiperChampsMotDePasse = equiperTout;
})();
