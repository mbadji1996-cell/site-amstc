/**
 * Génère une page d'aperçu par article, formation, projet, étape et cours.
 *
 * POURQUOI. Les fiches sont servies par des pages uniques paramétrées
 * (`article.html?slug=…`, `membres/cours.html?id=…`). Sur un hébergement
 * statique, toutes ces adresses renvoient LE MÊME fichier : le robot de
 * WhatsApp, qui n'exécute pas JavaScript, y lit donc toujours le titre
 * générique (« Cours - Daara AMSTC »). Aucune balise posée à l'exécution
 * ne peut corriger cela - il faut un vrai fichier par fiche.
 *
 * CE QUE FAIT CE SCRIPT. Pour chaque fiche, il écrit un petit fichier
 * portant les bonnes balises Open Graph, puis renvoyant le visiteur vers
 * la page réelle. La redirection est faite en JavaScript, jamais par
 * meta-refresh : les robots ne l'exécutent pas et s'arrêtent donc sur nos
 * balises, alors qu'un meta-refresh en ferait suivre certains jusqu'à la
 * page générique - ce qu'on cherche précisément à éviter.
 *
 * Adresses produites :
 *   /a/<slug>.html  article        /f/<slug>.html  formation
 *   /p/<slug>.html  projet         /e/<slug>.html  étape
 *   /c/<id>.html    cours du Daara ou leçon médicale
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = path.join(__dirname, '..');
const SITE = 'https://amstc.org';
const IMAGE_DEFAUT = SITE + '/assets/og-image.jpg';

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// Les descriptions viennent du CMS et peuvent contenir du Markdown ou des
// retours à la ligne, illisibles dans un aperçu.
function resume(s, max) {
  const t = String(s == null ? '' : s)
    .replace(/[#*_>`]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (t.length <= max) return t;
  return t.slice(0, max - 1).replace(/\s+\S*$/, '') + '…';
}

function urlAbsolue(image) {
  if (!image) return IMAGE_DEFAUT;
  if (/^https?:\/\//i.test(image)) return image;
  return SITE + '/' + String(image).replace(/^\/+/, '');
}

function pagePartage({ titre, description, image, destination, adressePartage }) {
  const t = esc(titre);
  const d = esc(description);
  const img = esc(urlAbsolue(image));
  // Racine obligatoire : la page d'aperçu vit dans /a/, /f/… et un chemin
  // relatif y résoudrait « article.html » en « /a/article.html ».
  const dest = '/' + String(destination).replace(/^\/+/, '');
  // Les dimensions ne sont déclarées que pour l'image par défaut, la seule
  // dont on connaisse la taille : annoncer 1200x630 pour une photo qui ne
  // les fait pas déforme l'aperçu.
  const dimensions = urlAbsolue(image) === IMAGE_DEFAUT
    ? '\n<meta property="og:image:width" content="1200">\n<meta property="og:image:height" content="630">' : '';
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${t}</title>
<meta name="description" content="${d}">
<!-- canonical vers la vraie fiche (pour les moteurs de recherche), mais
     og:url vers CETTE page : certains robots refont une requête sur og:url,
     et retomberaient alors sur les balises génériques de la page paramétrée. -->
<link rel="canonical" href="${SITE}${esc(dest)}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="AMSTC">
<meta property="og:locale" content="fr_FR">
<meta property="og:title" content="${t}">
<meta property="og:description" content="${d}">
<meta property="og:url" content="${SITE}${esc(adressePartage)}">
<meta property="og:image" content="${img}">${dimensions}
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${t}">
<meta name="twitter:description" content="${d}">
<meta name="twitter:image" content="${img}">
<style>
  body{font-family:Inter,-apple-system,Arial,sans-serif;background:#F6F7F1;color:#0B2E17;
       display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center;}
  a{color:#17763B;font-weight:600;}
</style>
</head>
<body>
  <div>
    <p>${t}</p>
    <p><a href="${esc(dest)}">Ouvrir la page</a></p>
  </div>
  <script>location.replace(${JSON.stringify(dest)});</script>
</body>
</html>
`;
}

function ecrire(dossier, nom, contenu) {
  const dir = path.join(ROOT, dossier);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, nom + '.html'), contenu);
}

// Les pages d'un tour précédent qui ne correspondent plus à une fiche
// doivent disparaître : un lien déjà partagé vers une fiche supprimée
// afficherait sinon un aperçu fantôme.
function purger(dossier, gardes) {
  const dir = path.join(ROOT, dossier);
  if (!fs.existsSync(dir)) return 0;
  let supprimes = 0;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.html')) continue;
    if (!gardes.has(f.replace(/\.html$/, ''))) {
      fs.unlinkSync(path.join(dir, f));
      supprimes++;
    }
  }
  return supprimes;
}

function lireIndex(nom) {
  const p = path.join(ROOT, 'content', nom + '-index.json');
  if (!fs.existsSync(p)) return [];
  try {
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    return Array.isArray(data) ? data : (data.items || []);
  } catch (e) {
    console.error('Index illisible :', nom, e.message);
    return [];
  }
}

function genererDepuisIndex(index, dossier, pageCible, cle) {
  const fiches = lireIndex(index);
  const gardes = new Set();
  for (const f of fiches) {
    const id = f[cle];
    if (!id) continue;
    gardes.add(id);
    ecrire(dossier, id, pagePartage({
      titre: f.title || 'AMSTC',
      description: resume(f.excerpt || f.description, 200) || "Association Médico-Sociale des Talibés Cheikh.",
      image: f.image,
      destination: `${pageCible}?${cle}=${encodeURIComponent(id)}`,
      adressePartage: `/${dossier}/${encodeURIComponent(id)}.html`,
    }));
  }
  const supprimes = purger(dossier, gardes);
  console.log(`  ${dossier.padEnd(4)} : ${fiches.length} page(s)` + (supprimes ? `, ${supprimes} obsolète(s) supprimée(s)` : ''));
  return fiches.length;
}

// ===== Cours : les titres vivent dans Supabase, pas dans le dépôt =====
// On les lit avec la clé publique du site (déjà dans assets/js), via une
// fonction qui n'expose que les métadonnées (voir phase54). Aucun secret
// à configurer dans GitHub Actions.
function lireConfigSupabase() {
  const js = fs.readFileSync(path.join(ROOT, 'assets', 'js', 'supabase-client.js'), 'utf8');
  const url = /const SUPABASE_URL\s*=\s*"([^"]+)"/.exec(js);
  const cle = /const SUPABASE_ANON_KEY\s*=\s*"([^"]+)"/.exec(js);
  if (!url || !cle) throw new Error('URL ou clé Supabase introuvable dans assets/js/supabase-client.js');
  return { url: url[1], cle: cle[1] };
}

function appelRpc(conf, fonction) {
  return new Promise((resolve, reject) => {
    const req = https.request(`${conf.url}/rest/v1/rpc/${fonction}`, {
      method: 'POST',
      headers: {
        apikey: conf.cle,
        Authorization: `Bearer ${conf.cle}`,
        'Content-Type': 'application/json',
        'Content-Length': 2,
      },
      timeout: 15000,
    }, (res) => {
      let corps = '';
      res.on('data', (c) => { corps += c; });
      res.on('end', () => {
        if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} : ${corps.slice(0, 200)}`));
        try { resolve(JSON.parse(corps)); } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(new Error('délai dépassé')); });
    req.end('{}');
  });
}

async function genererCours() {
  let cours;
  try {
    cours = await appelRpc(lireConfigSupabase(), 'cours_metadonnees_publiques');
  } catch (e) {
    // Fonction pas encore déployée, ou instance injoignable : on garde les
    // pages existantes plutôt que de les effacer, et la construction
    // continue - le reste du site ne doit pas dépendre de Supabase.
    console.warn('  c    : cours ignorés (' + e.message + ')');
    return 0;
  }
  // Une réponse vide alors que des pages existent est presque toujours un
  // incident (base repartie à vide, droits retirés) plutôt qu'un retrait
  // volontaire de TOUS les cours. On garde les pages : des liens déjà
  // partagés qui cessent de fonctionner coûtent plus cher qu'un aperçu
  // survivant à une dépublication.
  const dossierCours = path.join(ROOT, 'c');
  const existantes = fs.existsSync(dossierCours)
    ? fs.readdirSync(dossierCours).filter((f) => f.endsWith('.html')).length : 0;
  if (cours.length === 0 && existantes > 0) {
    console.warn(`  c    : aucun cours renvoyé alors que ${existantes} page(s) existent - conservées par précaution.`);
    return 0;
  }

  const gardes = new Set();
  for (const c of cours) {
    if (!c.id) continue;
    gardes.add(c.id);
    const cible = c.source === 'medical' ? 'membres/lecon.html' : 'membres/cours.html';
    const morceaux = [resume(c.description, 160), c.author ? 'Par ' + c.author : ''].filter(Boolean);
    ecrire('c', c.id, pagePartage({
      titre: c.title,
      description: morceaux.join(' · ') || "Espace membres de l'AMSTC.",
      image: null,
      destination: `${cible}?id=${encodeURIComponent(c.id)}`,
      adressePartage: `/c/${encodeURIComponent(c.id)}.html`,
    }));
  }
  const supprimes = purger('c', gardes);
  console.log(`  c    : ${cours.length} page(s)` + (supprimes ? `, ${supprimes} obsolète(s) supprimée(s)` : ''));
  return cours.length;
}

// ===== Bibliothèque : titres et couvertures vivent dans Supabase =====
// Même montage que les cours (phase76) : la fonction n'expose que ce qui
// figure dans l'aperçu - identifiant, titre, résumé, couverture - jamais
// le fichier, qui reste réservé aux membres.
async function genererBibliotheque() {
  let docs;
  try {
    docs = await appelRpc(lireConfigSupabase(), 'bibliotheque_metadonnees_publiques');
  } catch (e) {
    console.warn('  b    : bibliothèque ignorée (' + e.message + ')');
    return 0;
  }
  // Même précaution que les cours : une réponse vide alors que des pages
  // existent ressemble plus à un incident qu'à un retrait volontaire de
  // TOUS les documents.
  const dossierB = path.join(ROOT, 'b');
  const existantes = fs.existsSync(dossierB)
    ? fs.readdirSync(dossierB).filter((f) => f.endsWith('.html')).length : 0;
  if (docs.length === 0 && existantes > 0) {
    console.warn(`  b    : aucun document renvoyé alors que ${existantes} page(s) existent - conservées par précaution.`);
    return 0;
  }

  const gardes = new Set();
  for (const d of docs) {
    if (!d.id) continue;
    gardes.add(d.id);
    ecrire('b', d.id, pagePartage({
      titre: d.title,
      description: resume(d.excerpt, 200) || 'Bibliothèque des membres de l\'AMSTC.',
      image: d.cover_image,
      destination: `membres/bibliotheque.html?doc=${encodeURIComponent(d.id)}`,
      adressePartage: `/b/${encodeURIComponent(d.id)}.html`,
    }));
  }
  const supprimes = purger('b', gardes);
  console.log(`  b    : ${docs.length} page(s)` + (supprimes ? `, ${supprimes} obsolète(s) supprimée(s)` : ''));
  return docs.length;
}

(async () => {
  console.log('Pages d\'aperçu de partage :');
  let total = 0;
  total += genererDepuisIndex('actualites', 'a', 'article.html', 'slug');
  total += genererDepuisIndex('formations', 'f', 'formation.html', 'slug');
  total += genererDepuisIndex('projets', 'p', 'projet.html', 'slug');
  total += genererDepuisIndex('etapes', 'e', 'etape.html', 'slug');
  total += await genererCours();
  total += await genererBibliotheque();
  console.log('Total : ' + total + ' page(s).');
})();
