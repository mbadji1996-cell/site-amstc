/**
 * Graphies des saisies libres : noms de personnes et localités.
 *
 * Deux sujets, une seule raison d'être : le site laisse saisir du texte
 * libre, et ce texte finit sur une CARTE IMPRIMÉE ou dans un classement.
 * « ndeye marieme niass » et « médina » doivent devenir « Ndeye Marieme
 * NIASS » et « Médina » avant d'être enregistrés.
 *
 * POURQUOI. Le champ « localité » est libre. « Thiès », « Thies »,
 * « THIES » et « thiès » désignent la même ville mais comptaient pour
 * quatre dans les statistiques ; de même « Saint-Louis » et « Saint
 * Louis ». La liste des dix premières localités en devenait fausse - une
 * ville pouvait manquer au classement parce que ses membres étaient
 * répartis sur deux orthographes.
 *
 * DEUX FONCTIONS, DEUX RÔLES :
 *   localiteCle(s)     - clé de regroupement, invisible pour l'usager.
 *   localiteLibelle(s) - graphie à afficher.
 */

/**
 * Casse « titre » : une majuscule à chaque mot, le reste en minuscules.
 *
 * Le reste est bien ABAISSÉ, pas seulement la première lettre élevée :
 * « MOUHAMED » doit donner « Mouhamed », pas rester en capitales.
 *
 * Coupent un mot : l'espace, le trait d'union et l'apostrophe - « n'diaye »
 * donne « N'Diaye » et « marie-claire » donne « Marie-Claire ». Les
 * espaces surnuméraires sont réduits au passage.
 */
function casseTitre(valeur) {
  var s = String(valeur == null ? '' : valeur).replace(/\s+/g, ' ').trim();
  if (!s) return '';
  var sortie = '';
  var debut = true;
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i);
    sortie += debut ? c.toUpperCase() : c.toLowerCase();
    debut = (c === ' ' || c === '-' || c === "'" || c === '’');
  }
  return sortie;
}

/**
 * Prénom(s) : « mouhamed » devient « Mouhamed », « NDEYE MARIEME » devient
 * « Ndeye Marieme ».
 */
function normaliserPrenom(valeur) {
  return casseTitre(valeur);
}

/**
 * Nom de famille : tout en capitales, accents compris - « badji » devient
 * « BADJI », « séne » devient « SÉNE ». C'est la convention de l'état
 * civil, et elle distingue le nom du prénom sur la carte.
 */
function normaliserNom(valeur) {
  return String(valeur == null ? '' : valeur)
    .replace(/\s+/g, ' ').trim().toUpperCase();
}

/**
 * Nom complet affiché : « Mouhamed BADJI ».
 */
function nomCompletNormalise(prenom, nom) {
  return [normaliserPrenom(prenom), normaliserNom(nom)].filter(Boolean).join(' ');
}

/**
 * Branche la normalisation sur un champ de saisie : elle s'applique quand
 * le champ est quitté, pour que la personne VOIE la correction plutôt que
 * de la découvrir sur sa carte. La saisie n'est jamais gênée en cours de
 * frappe.
 */
function brancherNormalisation(champ, fonction) {
  if (!champ) return;
  champ.addEventListener('blur', function () {
    var corrige = fonction(champ.value);
    if (corrige !== champ.value) champ.value = corrige;
  });
}

// Les quatorze régions administratives du Sénégal. Liste UNIQUE du site :
// les formulaires la déroulent, et elle doit rester identique à la
// contrainte SQL profiles_region_check (phase66).
var REGIONS_SENEGAL = [
  'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou',
  'Kolda', 'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda',
  'Thiès', 'Ziguinchor'
];

/**
 * Remplit un <select> avec les quatorze régions, précédées d'une option
 * vide. Conserve la valeur actuelle si elle est connue.
 */
function remplirSelectRegions(select, valeurActuelle) {
  if (!select) return;
  select.innerHTML = '<option value="">- Choisir -</option>'
    + REGIONS_SENEGAL.map(function (r) {
        return '<option value="' + r + '">' + r + '</option>';
      }).join('');
  if (valeurActuelle && REGIONS_SENEGAL.indexOf(valeurActuelle) !== -1) {
    select.value = valeurActuelle;
  }
}

// Graphies officielles des localités sénégalaises les plus courantes,
// indexées par leur clé. Sans cette table, la variante affichée serait la
// plus fréquente - « Thies » l'emporterait sur « Thiès » par 9 contre 5,
// et le tableau afficherait durablement une faute.
var LOCALITES_CANONIQUES = {
  'dakar': 'Dakar', 'thies': 'Thiès', 'saint louis': 'Saint-Louis',
  'louga': 'Louga', 'tivaouane': 'Tivaouane', 'fatick': 'Fatick',
  'mbour': 'Mbour', 'pikine': 'Pikine', 'guediawaye': 'Guédiawaye',
  'kaolack': 'Kaolack', 'ziguinchor': 'Ziguinchor', 'diourbel': 'Diourbel',
  'touba': 'Touba', 'rufisque': 'Rufisque', 'mbacke': 'Mbacké',
  'tambacounda': 'Tambacounda', 'kolda': 'Kolda', 'matam': 'Matam',
  'kedougou': 'Kédougou', 'sedhiou': 'Sédhiou', 'kaffrine': 'Kaffrine',
  'podor': 'Podor', 'linguere': 'Linguère', 'bignona': 'Bignona',
  'richard toll': 'Richard-Toll', 'joal fadiouth': 'Joal-Fadiouth',
  'gueule tapee': 'Gueule Tapée', 'parcelles assainies': 'Parcelles Assainies',
  'grand yoff': 'Grand Yoff', 'yeumbeul': 'Yeumbeul', 'keur massar': 'Keur Massar',
  'guinaw rail': 'Guinaw Rail', 'ouakam': 'Ouakam', 'ngor': 'Ngor',
  'yoff': 'Yoff', 'medina': 'Médina', 'point e': 'Point E',
  'sicap': 'Sicap', 'liberte': 'Liberté', 'hlm': 'HLM',
  'malika': 'Malika', 'thiaroye': 'Thiaroye', 'bargny': 'Bargny',
  'diamniadio': 'Diamniadio', 'sebikotane': 'Sébikotane', 'nioro': 'Nioro',
  'velingara': 'Vélingara', 'bakel': 'Bakel', 'dagana': 'Dagana',
  'gossas': 'Gossas', 'foundiougne': 'Foundiougne', 'bambey': 'Bambey',
  'kebemer': 'Kébémer', 'goudomp': 'Goudomp', 'oussouye': 'Oussouye',
  'salemata': 'Salémata', 'saraya': 'Saraya', 'koungheul': 'Koungheul',
  'birkelane': 'Birkelane', 'malem hodar': 'Malem Hodar', 'ranerou': 'Ranérou',
  'kanel': 'Kanel', 'guinguineo': 'Guinguinéo', 'mbao': 'Mbao',
  'diamaguene': 'Diamaguène', 'golf sud': 'Golf Sud', 'wakhinane': 'Wakhinane'
};

// Région de rattachement des localités connues, indexée par la même clé
// que la table ci-dessus.
//
// POURQUOI. La région n'est demandée que depuis phase66 : la centaine de
// profils antérieurs ne la porte pas, et sans cette table le graphique
// par région resterait vide pendant des mois. Elle sert UNIQUEMENT à
// l'affichage des statistiques, jamais à écrire en base - la valeur
// déduite est signalée comme telle à l'écran.
var LOCALITE_VERS_REGION = {
  // Région de Dakar (départements Dakar, Pikine, Guédiawaye, Rufisque)
  'dakar': 'Dakar', 'pikine': 'Dakar', 'guediawaye': 'Dakar', 'rufisque': 'Dakar',
  'gueule tapee': 'Dakar', 'parcelles assainies': 'Dakar', 'grand yoff': 'Dakar',
  'yeumbeul': 'Dakar', 'keur massar': 'Dakar', 'guinaw rail': 'Dakar',
  'ouakam': 'Dakar', 'ngor': 'Dakar', 'yoff': 'Dakar', 'medina': 'Dakar',
  'point e': 'Dakar', 'sicap': 'Dakar', 'liberte': 'Dakar', 'hlm': 'Dakar',
  'malika': 'Dakar', 'thiaroye': 'Dakar', 'bargny': 'Dakar',
  'diamniadio': 'Dakar', 'sebikotane': 'Dakar', 'mbao': 'Dakar',
  'diamaguene': 'Dakar', 'golf sud': 'Dakar', 'wakhinane': 'Dakar',
  // Thiès
  'thies': 'Thiès', 'tivaouane': 'Thiès', 'mbour': 'Thiès', 'joal fadiouth': 'Thiès',
  // Saint-Louis
  'saint louis': 'Saint-Louis', 'podor': 'Saint-Louis', 'dagana': 'Saint-Louis',
  'richard toll': 'Saint-Louis',
  // Louga
  'louga': 'Louga', 'linguere': 'Louga', 'kebemer': 'Louga',
  // Diourbel
  'diourbel': 'Diourbel', 'touba': 'Diourbel', 'mbacke': 'Diourbel', 'bambey': 'Diourbel',
  // Fatick
  'fatick': 'Fatick', 'foundiougne': 'Fatick', 'gossas': 'Fatick',
  // Kaolack
  'kaolack': 'Kaolack', 'nioro': 'Kaolack', 'guinguineo': 'Kaolack',
  // Kaffrine
  'kaffrine': 'Kaffrine', 'koungheul': 'Kaffrine', 'birkelane': 'Kaffrine',
  'malem hodar': 'Kaffrine',
  // Ziguinchor
  'ziguinchor': 'Ziguinchor', 'bignona': 'Ziguinchor', 'oussouye': 'Ziguinchor',
  // Kolda
  'kolda': 'Kolda', 'velingara': 'Kolda',
  // Sédhiou
  'sedhiou': 'Sédhiou', 'goudomp': 'Sédhiou',
  // Tambacounda
  'tambacounda': 'Tambacounda', 'bakel': 'Tambacounda',
  // Kédougou
  'kedougou': 'Kédougou', 'salemata': 'Kédougou', 'saraya': 'Kédougou',
  // Matam
  'matam': 'Matam', 'kanel': 'Matam', 'ranerou': 'Matam'
};

/**
 * Ramène une saisie libre à l'une des quatorze régions, ou null.
 *
 * Sert aux imports, où la valeur vient d'un tableur rempli à la main :
 * « thies », « THIÈS » et « Thies  » désignent tous la région de Thiès.
 * Une localité connue est acceptée aussi - « Ouakam » dans une colonne
 * Région désigne sans ambiguïté la région de Dakar, et refuser la ligne
 * pour cette raison ferait perdre une donnée juste.
 *
 * Renvoie null sur ce qui n'est pas reconnaissable : mieux vaut une
 * région vide qu'une région inventée.
 */
function regionNormalisee(valeur) {
  var cle = localiteCle(valeur);
  if (!cle) return null;
  for (var i = 0; i < REGIONS_SENEGAL.length; i++) {
    if (localiteCle(REGIONS_SENEGAL[i]) === cle) return REGIONS_SENEGAL[i];
  }
  return LOCALITE_VERS_REGION[cle] || null;
}

/**
 * Région d'un profil : celle qu'il a saisie, sinon celle déduite de sa
 * localité, sinon rien. Renvoie null plutôt qu'une valeur inventée.
 */
function regionDuProfil(profil) {
  if (!profil) return null;
  var saisie = String(profil.region || '').trim();
  if (saisie) return saisie;
  return LOCALITE_VERS_REGION[localiteCle(profil.city)] || null;
}

/**
 * Clé de regroupement : minuscules, sans accents, tirets et apostrophes
 * ramenés à des espaces, espaces multiples réduits.
 *
 * La plage de caractères combinants est écrite en séquences d'échappement
 * (\u0300-\u036f) et jamais avec les caractères eux-mêmes : invisibles
 * dans l'éditeur, ils se perdent au moindre copier-coller et la fonction
 * cesse alors silencieusement de retirer les accents.
 */
function localiteCle(valeur) {
  return String(valeur == null ? '' : valeur)
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/['’\-_.]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Graphie à afficher pour une localité. La table officielle prime ; à
 * défaut, la saisie est nettoyée de ses espaces superflus et chaque mot
 * reçoit une majuscule - « THIES » et « thies  » deviennent « Thies »,
 * regroupés mais présentés proprement.
 */
function localiteLibelle(valeur) {
  var cle = localiteCle(valeur);
  if (!cle) return '';
  if (LOCALITES_CANONIQUES[cle]) return LOCALITES_CANONIQUES[cle];
  // casseTitre plutôt qu'une simple élévation de l'initiale : celle-ci
  // laissait « TIVAOUANE PEULH » en capitales, la saisie tout en
  // majuscules étant justement l'un des cas à corriger.
  return casseTitre(valeur);
}
