/* ============================================================
   Lecture de l'en-tête YAML des fiches (content/*.md)
   ------------------------------------------------------------
   Une seule lecture pour tout le site : les pages (article,
   formation, projet, étape) et les scripts de construction
   (index, contenus réservés) s'en servent tous.

   POURQUOI UN VRAI TRAITEMENT DES VALEURS. Decap CMS renvoie à la
   ligne les valeurs longues, et choisit selon le texte :
     title: "Nemekou Daara - Etape 5 - Ramadan (en hommage ... :
       visite médicale + don de denrées ..."
     excerpt: |-
       3 Daaras ont bénéficié de soins :
       1.Daaral Houda de Grand Dakar
   L'ancienne lecture n'ôtait les guillemets que si la PREMIÈRE ligne
   se refermait : sur un titre replié, le « " » d'ouverture restait
   affiché (et celui de fermeture aussi, au bout de la dernière ligne),
   et « |- » apparaissait en tête des résumés.

   Couvert : valeurs simples, entre "…" (échappements \" \\ \n \t \uXXXX)
   ou '…' ('' pour une apostrophe), repliées sur plusieurs lignes, blocs
   | et > (avec - ou +), listes « - élément ». Les valeurs restent des
   chaînes, comme avant : « true » et les dates sont lues par l'appelant.
   ============================================================ */
(function (racine) {
  function retirerIndentation(lignes) {
    var min = Infinity;
    lignes.forEach(function (l) {
      if (!l.trim()) return;
      var n = l.match(/^[ \t]*/)[0].length;
      if (n < min) min = n;
    });
    if (min === Infinity) min = 0;
    return lignes.map(function (l) { return l.slice(min); });
  }

  // Lignes repliées : un saut simple devient une espace, une ligne vide
  // un vrai retour à la ligne - la règle YAML.
  function replier(morceaux) {
    var sortie = '';
    var vide = false;
    morceaux.forEach(function (m, i) {
      var t = m.trim();
      if (!t) { sortie += '\n'; vide = true; return; }
      if (i > 0 && !vide && sortie && !/\n$/.test(sortie)) sortie += ' ';
      sortie += t;
      vide = false;
    });
    return sortie;
  }

  function entreGuillemets(texte) {
    // texte commence par « " » ; on s'arrête au premier « " » non échappé.
    var s = '';
    for (var i = 1; i < texte.length; i++) {
      var c = texte.charAt(i);
      if (c === '\\' && i + 1 < texte.length) {
        var e = texte.charAt(++i);
        if (e === 'n') s += '\n';
        else if (e === 't') s += '\t';
        else if (e === 'u' && /^[0-9a-fA-F]{4}$/.test(texte.substr(i + 1, 4))) {
          s += String.fromCharCode(parseInt(texte.substr(i + 1, 4), 16));
          i += 4;
        } else s += e; // \" \\ \/ et le reste
        continue;
      }
      if (c === '"') return s;
      s += c;
    }
    return s; // guillemet fermant absent : on garde ce qui a été lu
  }

  function entreApostrophes(texte) {
    var s = '';
    for (var i = 1; i < texte.length; i++) {
      var c = texte.charAt(i);
      if (c === "'") {
        if (texte.charAt(i + 1) === "'") { s += "'"; i++; continue; }
        return s;
      }
      s += c;
    }
    return s;
  }

  function valeur(tete, suite) {
    tete = (tete || '').trim();

    // Bloc | ou > : le texte est dans les lignes suivantes.
    var bloc = tete.match(/^([|>])([+-]?)\d*\s*(#.*)?$/);
    if (bloc) {
      var lignes = retirerIndentation(suite);
      var texte = bloc[1] === '|'
        ? lignes.join('\n')
        : lignes.reduce(function (acc, l) {
            if (!acc) return l;
            if (!l.trim() || /\n$/.test(acc)) return acc + '\n' + l;
            return acc + ' ' + l;
          }, '');
      return texte.replace(/\s+$/, '');
    }

    // Liste « - élément » sous la clé.
    if (!tete && suite.length && suite.filter(function (l) { return l.trim(); })
          .every(function (l) { return /^\s*-\s/.test(l) || /^\s*-$/.test(l); })) {
      return suite.filter(function (l) { return l.trim(); })
        .map(function (l) { return valeur(l.replace(/^\s*-\s?/, ''), []); });
    }

    var replie = replier([tete].concat(suite));
    if (replie.charAt(0) === '"') return entreGuillemets(replie).trim();
    if (replie.charAt(0) === "'") return entreApostrophes(replie).trim();
    return replie.trim();
  }

  function lireEntete(entete) {
    var data = {};
    var lignes = entete.split(/\r?\n/);
    for (var i = 0; i < lignes.length; i++) {
      var k = lignes[i].match(/^([A-Za-z0-9_]+):(?:[ \t]+(.*))?[ \t]*$/);
      if (!k) continue;
      var suite = [];
      // La valeur continue tant que les lignes sont indentées (ou vides
      // entre deux lignes indentées).
      var j = i + 1;
      while (j < lignes.length && (/^[ \t]/.test(lignes[j]) || !lignes[j].trim())) {
        suite.push(lignes[j]);
        j++;
      }
      while (suite.length && !suite[suite.length - 1].trim()) suite.pop();
      data[k[1]] = valeur(k[2], suite);
      i = j - 1;
    }
    return data;
  }

  // { data, body } - body est le texte après l'en-tête.
  function parseFrontMatter(raw) {
    raw = String(raw || '');
    var m = raw.match(/^﻿?---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)([\s\S]*)$/)
         || raw.match(/^---\s*([\s\S]*?)\s*---\s*([\s\S]*)$/);
    if (!m) return { data: {}, body: raw, entete: '' };
    return { data: lireEntete(m[1]), body: m[2], entete: m[1] };
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = { parseFrontMatter: parseFrontMatter };
  else racine.lireFrontMatter = parseFrontMatter;
})(typeof window !== 'undefined' ? window : this);
