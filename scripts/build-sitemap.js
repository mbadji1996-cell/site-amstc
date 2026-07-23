// Génère sitemap.xml à partir des index de contenu (Réalisations,
// Formations, Projets, Étapes) + des pages statiques du site, pour que
// les moteurs de recherche découvrent aussi les pages individuelles
// (article.html?slug=..., formation.html?slug=..., etc.), pas seulement
// les listes.
//
// Usage : node scripts/build-sitemap.js
// Appelé automatiquement par .github/workflows/build-content-index.yml
// à chaque changement de contenu, juste après build-content-index.js.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SITE_URL = 'https://amstc.org';

function isoDate(d) {
  if (!d) return null;
  const date = new Date(d);
  if (isNaN(date.getTime())) return null;
  return date.toISOString().slice(0, 10);
}

function xmlEscape(s) {
  return String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

function readIndex(name) {
  const file = path.join(ROOT, 'content', `${name}-index.json`);
  if (!fs.existsSync(file)) return [];
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function latestDate(items, fallback) {
  const dates = items.map(it => isoDate(it.date)).filter(Boolean).sort();
  return dates.length ? dates[dates.length - 1] : fallback;
}

const today = isoDate(new Date()) || '2026-01-01';

const actualites = readIndex('actualites');
const formations = readIndex('formations');
const projets = readIndex('projets');
const etapes = readIndex('etapes');

const urls = [];

function addUrl(loc, lastmod, changefreq, priority) {
  urls.push({ loc, lastmod: lastmod || today, changefreq, priority });
}

// ===== Pages statiques =====
addUrl(`${SITE_URL}/`, latestDate(actualites, today), 'weekly', '1.0');
addUrl(`${SITE_URL}/actualites.html`, latestDate(actualites, today), 'weekly', '0.8');
addUrl(`${SITE_URL}/formations.html`, latestDate(formations, today), 'weekly', '0.8');
addUrl(`${SITE_URL}/projets.html`, latestDate(projets, today), 'weekly', '0.8');
addUrl(`${SITE_URL}/don.html`, today, 'monthly', '0.6');
addUrl(`${SITE_URL}/guide.html`, today, 'monthly', '0.4');
addUrl(`${SITE_URL}/confidentialite.html`, today, 'yearly', '0.3');
addUrl(`${SITE_URL}/cgu.html`, today, 'yearly', '0.3');

// ===== Pages individuelles =====
// encodeURIComponent : certains slugs contiennent des caractères accentués
// (générés depuis un titre) - une URL de sitemap doit rester correctement
// encodée, sinon des lecteurs stricts (Google Search Console, validateurs
// XML) peuvent la rejeter.
actualites.forEach(a => addUrl(`${SITE_URL}/article.html?slug=${encodeURIComponent(a.slug)}`, isoDate(a.date), 'monthly', '0.6'));
formations.forEach(f => addUrl(`${SITE_URL}/formation.html?slug=${encodeURIComponent(f.slug)}`, isoDate(f.date), 'monthly', '0.6'));
projets.forEach(p => addUrl(`${SITE_URL}/projet.html?slug=${encodeURIComponent(p.slug)}`, isoDate(p.date), 'monthly', '0.6'));
etapes.forEach(e => addUrl(`${SITE_URL}/etape.html?slug=${encodeURIComponent(e.slug)}`, isoDate(e.date), 'monthly', '0.5'));

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map(u => `  <url>
    <loc>${xmlEscape(u.loc)}</loc>
    <lastmod>${u.lastmod}</lastmod>
    <changefreq>${u.changefreq}</changefreq>
    <priority>${u.priority}</priority>
  </url>`).join('\n')}
</urlset>
`;

fs.writeFileSync(path.join(ROOT, 'sitemap.xml'), xml);
console.log(`sitemap.xml généré avec ${urls.length} URL(s).`);
