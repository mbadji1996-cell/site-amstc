/**
 * Assistant de l'espace membres.
 *
 * POURQUOI CELUI-CI ET PAS UNE INTELLIGENCE ARTIFICIELLE. Les questions
 * d'un espace membres sont répétitives et procédurales : où est ma carte,
 * ma cotisation est-elle à jour, comment renouveler, j'ai oublié mon mot
 * de passe. Un jeu de réponses écrites par l'association les couvre,
 * NE PEUT RIEN INVENTER, ne coûte rien, et fonctionne en connexion
 * faible - trois avantages qu'aucun modèle de langage ne donne. Si des
 * questions imprévues reviennent, une IA pourra être branchée DERRIÈRE
 * ce socle, en dernier recours seulement.
 *
 * La réponse sur la carte et les cotisations est PERSONNALISÉE : elle lit
 * le profil du membre. Une réponse générique du genre « consultez votre
 * profil » ferait perdre à l'assistant l'essentiel de son intérêt sur la
 * question la plus posée.
 *
 * Dépendances : supabase-client.js (facultatif - sans lui, l'assistant
 * fonctionne, seules les réponses personnalisées se replient sur un
 * texte générique).
 */

(function () {
  // Rien à faire sur une page qui n'appartient pas à l'espace membres.
  if (!document.querySelector('.member-tabs')) return;

  // Les liens sont relatifs au dossier courant, sans calcul de chemin :
  // l'assistant ne s'active que sur les pages portant .member-tabs, et
  // celles-ci vivent toutes dans membres/. Une heuristique fondee sur
  // l'adresse ne pourrait que se tromper - elle le faisait deja.
  function lien(href, texte) {
    return '<a href="' + href + '">' + texte + '</a>';
  }

  // Chaque entrée : des mots-clés pour la recherche, une question
  // affichée, et une réponse. « reponse » peut être une fonction
  // asynchrone quand elle a besoin du profil.
  var QUESTIONS = [
    {
      cles: 'carte membre validite valable expire expiree renouveler renouvellement numero',
      question: 'Ma carte de membre est-elle valable ?',
      reponse: reponseCarte,
    },
    {
      cles: 'cotisation cotisations payer paiement montant retard impayee annee',
      question: 'Où en sont mes cotisations ?',
      reponse: reponseCotisations,
    },
    {
      cles: 'payer paiement wave orange money transaction capture preuve envoyer',
      question: 'Comment payer ma cotisation ou ma carte ?',
      reponse: function () {
        return 'Rendez-vous sur ' + lien('profil.html', 'Carte de membre et Cotisations') + '.'
          + '<br><br>Vous y trouverez les numéros Wave et Orange Money de l\'association, '
          + 'et un formulaire pour déclarer votre paiement une fois effectué. '
          + 'Indiquez-y la référence de la transaction : c\'est elle qui permet à '
          + 'l\'administration de retrouver votre versement et de le valider.';
      },
    },
    {
      cles: 'mot de passe oublie perdu connexion connecter identifiant acces bloque',
      question: 'J\'ai oublié mon mot de passe',
      reponse: function () {
        return 'Sur la page de connexion, utilisez le lien <strong>« Mot de passe oublié »</strong> : '
          + 'un message vous sera envoyé à votre adresse e-mail.'
          + '<br><br>S\'il n\'arrive pas, regardez dans vos courriers indésirables. '
          + 'Sans résultat, écrivez à l\'administration : elle peut vous engendrer un lien directement.';
      },
    },
    {
      cles: 'photo identite portrait carte imprimer changer modifier',
      question: 'Comment changer ma photo ?',
      reponse: function () {
        return 'Depuis ' + lien('profil.html', 'Carte de membre et Cotisations') + ', section informations.'
          + '<br><br>Cette photo est celle qui figure sur votre carte : préférez un portrait net, '
          + 'cadré sur le visage. Sans photo, la carte ne peut pas être établie.';
      },
    },
    {
      cles: 'profil informations nom prenom telephone localite region domaine specialite modifier corriger',
      question: 'Comment corriger mes informations ?',
      reponse: function () {
        return 'Depuis ' + lien('profil.html', 'Carte de membre et Cotisations') + '.'
          + '<br><br>Vous pouvez y modifier votre prénom, votre nom, votre téléphone, '
          + 'votre région et votre localité.'
          + '<br><br>Ces informations figurent sur votre carte imprimée : vérifiez-les avant '
          + 'une impression. Si quelque chose ne peut pas être corrigé depuis cette page, '
          + 'signalez-le à l\'administration.';
      },
    },
    {
      cles: 'formation formations daara cours quiz enseignement medical bibliotheque livre document',
      question: 'Où trouver les formations et les livres ?',
      reponse: function () {
        return 'Tout se trouve sous ' + lien('formations.html', 'Formations') + ' : '
          + 'l\'Espace Daara, les enseignements médicaux, les quiz et la bibliothèque.'
          + '<br><br>Ces contenus sont réservés aux membres dont la carte est à jour.';
      },
    },
    {
      cles: 'document officiel statuts reglement interieur rapport pv assemblee',
      question: 'Où sont les statuts et documents officiels ?',
      reponse: function () {
        return 'Dans ' + lien('documents.html', 'Documents officiels') + ' : statuts, '
          + 'règlement intérieur, rapports et procès-verbaux.';
      },
    },
    {
      cles: 'annuaire membres contacter confrere collegue chercher trouver quelqu un',
      question: 'Comment contacter un autre membre ?',
      reponse: function () {
        return 'Par ' + lien('annuaire.html', 'l\'Annuaire') + ', qui liste les membres '
          + 'avec leur domaine et leur localité.'
          + '<br><br>Pour un échange collectif, le ' + lien('forum.html', 'Forum') + ' est plus adapté.';
      },
    },
    {
      cles: 'pdf document ouvre pas premiere page iphone telephone lecture bloque',
      question: 'Un document ne s\'affiche pas en entier',
      reponse: function () {
        return 'Sur iPhone et iPad, l\'aperçu intégré n\'affiche que la première page : '
          + 'le document s\'ouvre donc dans un nouvel onglet, où il se lit en entier.'
          + '<br><br>Si rien ne s\'ouvre, votre navigateur a probablement bloqué la fenêtre. '
          + 'Autorisez-la, ou touchez le lien « Ouvrir le document » qui s\'affiche à la place.';
      },
    },
    {
      cles: 'contact aide probleme administration ecrire joindre bug erreur',
      question: 'Je n\'ai pas trouvé ma réponse',
      reponse: function () {
        return 'Écrivez à l\'association à <strong>contact@amstc.org</strong>, ou passez par '
          + 'le ' + lien('forum.html', 'Forum') + ' si votre question peut profiter aux autres membres.'
          + '<br><br>Pour un problème technique, précisez la page concernée et ce qui s\'est '
          + 'affiché à l\'écran : cela fait gagner beaucoup de temps.';
      },
    },
  ];

  // ===== Réponses personnalisées =====

  var profilCache = null;

  async function chargerProfil() {
    if (profilCache !== null) return profilCache;
    try {
      if (typeof supabaseClient === 'undefined') { profilCache = false; return false; }
      var s = await supabaseClient.auth.getSession();
      var session = s && s.data && s.data.session;
      if (!session) { profilCache = false; return false; }
      var r = await supabaseClient.from('profiles')
        .select('card_valid_until, member_since, legacy_card_number')
        .eq('id', session.user.id).single();
      profilCache = r.error ? false : r.data;
      return profilCache;
    } catch (e) {
      // Toute panne de lecture retombe sur la réponse générique : mieux
      // vaut une réponse incomplète qu'un assistant qui ne répond pas.
      profilCache = false;
      return false;
    }
  }

  async function reponseCarte() {
    var generique = 'Votre carte et sa validité sont affichées sur '
      + lien('profil.html', 'Carte de membre et Cotisations') + '.';
    var p = await chargerProfil();
    if (!p) return generique;

    var annee = new Date().getFullYear();
    var texte;
    if (!p.card_valid_until) {
      texte = 'Aucune année de validité n\'est enregistrée pour votre carte. '
        + 'Contactez l\'administration pour la faire établir.';
    } else if (p.card_valid_until >= annee) {
      texte = 'Votre carte est <strong>valable jusqu\'en ' + p.card_valid_until + '</strong>.';
    } else {
      texte = 'Votre carte a <strong>expiré fin ' + p.card_valid_until + '</strong>. '
        + 'Vous disposez de deux mois pour la renouveler avant que l\'accès aux '
        + 'contenus réservés ne soit suspendu.';
    }
    if (p.legacy_card_number) {
      texte += '<br><br>Numéro de carte : <strong>' + p.legacy_card_number + '</strong>.';
    }
    return texte + '<br><br>' + generique;
  }

  async function reponseCotisations() {
    return 'Le détail année par année figure sur '
      + lien('profil.html', 'Carte de membre et Cotisations') + ', '
      + 'section Cotisations : les années réglées y sont marquées, les autres restent à jour.'
      + '<br><br>Si un versement que vous avez fait n\'y apparaît pas, c\'est qu\'il '
      + 'n\'a pas encore été validé par l\'administration. Déclarez-le depuis cette même '
      + 'page en indiquant la référence de la transaction.';
  }

  // ===== Recherche =====

  function normaliser(s) {
    return String(s == null ? '' : s)
      .normalize('NFD')
      // Plage ECHAPPEE, jamais les caracteres eux-memes : invisibles a
      // la lecture, ils se perdent au moindre copier-coller et la
      // fonction cesse alors silencieusement de retirer les accents.
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  }

  function chercher(saisie) {
    var mots = normaliser(saisie).split(' ').filter(Boolean);
    if (!mots.length) return QUESTIONS;
    return QUESTIONS
      .map(function (q) {
        var champ = normaliser(q.cles + ' ' + q.question);
        var score = mots.reduce(function (n, m) {
          return n + (champ.indexOf(m) !== -1 ? 1 : 0);
        }, 0);
        return { q: q, score: score };
      })
      .filter(function (x) { return x.score > 0; })
      .sort(function (a, b) { return b.score - a.score; })
      .map(function (x) { return x.q; });
  }

  // ===== Interface =====

  var panneau, listeEl, champEl, reponseEl, ouvert = false;

  function construire() {
    var bouton = document.createElement('button');
    bouton.className = 'assistant-bouton';
    bouton.type = 'button';
    bouton.setAttribute('aria-label', 'Ouvrir l\'assistant');
    bouton.innerHTML = '<span aria-hidden="true">?</span> Besoin d\'aide';
    bouton.addEventListener('click', basculer);

    panneau = document.createElement('div');
    panneau.className = 'assistant-panneau';
    panneau.setAttribute('role', 'dialog');
    panneau.setAttribute('aria-label', 'Assistant de l\'espace membres');
    panneau.innerHTML =
      '<div class="assistant-entete">'
      + '<span>Assistant</span>'
      + '<button type="button" class="assistant-fermer" aria-label="Fermer">&times;</button>'
      + '</div>'
      + '<div class="assistant-corps">'
      + '<input type="search" class="assistant-champ" placeholder="Votre question…" aria-label="Rechercher une question">'
      + '<div class="assistant-reponse" style="display:none;"></div>'
      + '<div class="assistant-liste"></div>'
      + '</div>';

    document.body.appendChild(bouton);
    document.body.appendChild(panneau);

    listeEl = panneau.querySelector('.assistant-liste');
    champEl = panneau.querySelector('.assistant-champ');
    reponseEl = panneau.querySelector('.assistant-reponse');

    panneau.querySelector('.assistant-fermer').addEventListener('click', basculer);
    champEl.addEventListener('input', function () { afficherListe(chercher(champEl.value)); });
    // Échap ferme : sur un panneau superposé, c'est le réflexe attendu.
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && ouvert) basculer();
    });

    afficherListe(QUESTIONS);
  }

  function afficherListe(questions) {
    reponseEl.style.display = 'none';
    if (!questions.length) {
      listeEl.innerHTML = '<p class="assistant-vide">Aucune question ne correspond. '
        + 'Écrivez à contact@amstc.org.</p>';
      return;
    }
    listeEl.innerHTML = '';
    questions.forEach(function (q) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'assistant-question';
      b.textContent = q.question;
      b.addEventListener('click', function () { repondre(q); });
      listeEl.appendChild(b);
    });
  }

  async function repondre(q) {
    reponseEl.style.display = '';
    reponseEl.innerHTML = '<p class="assistant-titre">' + q.question + '</p><p>…</p>';
    var texte = await q.reponse();
    reponseEl.innerHTML = '<p class="assistant-titre">' + q.question + '</p><p>' + texte + '</p>';
    // Le panneau défile en haut : après un clic en bas de liste, la
    // réponse serait sinon hors de vue et l'on croirait qu'il ne s'est
    // rien passé.
    panneau.querySelector('.assistant-corps').scrollTop = 0;
  }

  function basculer() {
    ouvert = !ouvert;
    panneau.classList.toggle('ouvert', ouvert);
    if (ouvert) champEl.focus();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', construire);
  } else {
    construire();
  }
})();
