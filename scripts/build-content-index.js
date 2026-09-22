const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

// Lecture de l'en-tete : assets/js/front-matter.js, la meme que les pages.
const lireFrontMatter = require('../assets/js/front-matter.js').parseFrontMatter;
function parseFrontMatter(raw) {
  return lireFrontMatter(raw).data;
}

// Une valeur seule, une liste, ou rien : toujours une liste propre.
function listeCategories(valeur) {
  if (Array.isArray(valeur)) return valeur.map(v => String(v).trim()).filter(Boolean);
  const t = String(valeur || '').trim();
  return t ? [t] : [];
}

function buildIndex(folderName) {
  const dir = path.join(ROOT, 'content', folderName);
  const outFile = path.join(ROOT, 'content', `${folderName}-index.json`);
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.md')) : [];

  // Normalise "JJ/MM/AAAA" (fiches enregistrées par Decap avant que le
  // config.yml ne fixe un format de stockage ISO) : new Date() lirait ce
  // format comme MM/JJ et produirait une date invalide, éjectant la fiche
  // du tri, de l'agenda et des bilans annuels.
  const normalizeDate = (d) => {
    const fr = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(String(d || '').trim());
    if (fr) return `${fr[3]}-${fr[2].padStart(2, '0')}-${fr[1].padStart(2, '0')}`;
    return d || '';
  };

  const items = files.map(f => {
    const raw = fs.readFileSync(path.join(dir, f), 'utf8');
    const data = parseFrontMatter(raw);
    return {
      slug: f.replace(/\.md$/, ''),
      title: data.title || '',
      date: normalizeDate(data.date),
      date_debut: normalizeDate(data.date_debut),
      date_fin: normalizeDate(data.date_fin),
      excerpt: data.excerpt || '',
      // Reserve aux membres : la vignette reste publique avec un cadenas ;
      // le corps est en base (scripts/reserver-contenus.js).
      reserve: /^(true|yes|oui|1)$/i.test(String(data.reserve || '').trim()),
      image: data.image || '',
      // Activites de la fiche : une fiche peut en porter plusieurs (un
      // gamou couvert medicalement est un gamou ET des consultations).
      // L'index ecrit toujours une LISTE ; « categorie » garde la
      // premiere valeur, pour ce qui lit encore une chaine.
      categorie: listeCategories(data.categorie)[0] || '',
      categories: listeCategories(data.categorie),
      statut: data.statut || '',
      // Domaine d'intervention d'un projet : sante, education,
      // infrastructures... Sert aux pastilles de la page Projets.
      domaine: data.domaine || '',
      projet: data.projet || '',
      ordre: data.ordre !== undefined ? Number(data.ordre) : '',
      // Propres aux événements du calendrier (content/evenements)
      lieu: data.lieu || '',
      lien: data.lien || ''
    };
  });

  items.sort((a, b) => new Date(b.date) - new Date(a.date));
  fs.writeFileSync(outFile, JSON.stringify(items, null, 2) + '\n');
  console.log(`${outFile}: ${items.length} article(s)`);
}

buildIndex('actualites');
buildIndex('formations');
buildIndex('projets');
buildIndex('etapes');
buildIndex('evenements');
