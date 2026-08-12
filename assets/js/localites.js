/**
 * Localités : regrouper les graphies d'une même ville.
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
  return String(valeur == null ? '' : valeur)
    .replace(/\s+/g, ' ').trim()
    .replace(/(^|[\s\-'’])(\S)/g, function (_, avant, lettre) {
      return avant + lettre.toUpperCase();
    });
}
