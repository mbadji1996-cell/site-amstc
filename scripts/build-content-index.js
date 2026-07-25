const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

function parseFrontMatter(raw) {
  const match = raw.match(/^---\s*([\s\S]*?)\s*---\s*([\s\S]*)$/);
  if (!match) return {};
  const data = {};
  let currentKey = null;
  match[1].split(/\r?\n/).forEach(line => {
    const keyMatch = line.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (keyMatch) {
      currentKey = keyMatch[1].trim();
      data[currentKey] = keyMatch[2].trim().replace(/^"(.*)"$/, '$1');
    } else if (currentKey && line.trim()) {
      // Ligne de repli YAML (valeur trop longue renvoyée à la ligne par
      // Decap CMS) : on la rattache à la valeur en cours au lieu de la
      // perdre silencieusement.
      data[currentKey] = (data[currentKey] + ' ' + line.trim()).trim();
    }
  });
  return data;
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
      image: data.image || '',
      statut: data.statut || '',
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
