/**
 * Retire du dépôt public le corps des contenus « réservés aux membres »,
 * et le dépose en base.
 *
 * POURQUOI. Un fichier du dépôt est public, quoi qu'en dise la page qui
 * l'affiche : GitHub Pages le sert tel quel à qui connaît l'adresse.
 * Cocher « réservé » dans Decap ne suffirait donc pas. Ce script, lancé
 * par le workflow de construction, fait le vrai travail : pour chaque
 * fiche marquée « reserve: true » dont le corps est encore présent, il
 * envoie ce corps en base (fonction deposer_contenu_reserve, phase 95),
 * puis RÉÉCRIT le fichier avec son en-tête seul et une ligne qui dit où
 * lire. Le workflow commite. Le texte réservé ne repasse jamais dans le
 * dépôt : au passage suivant, le corps est déjà absent, rien à faire.
 *
 * CE QUI RESTE PUBLIC, VOLONTAIREMENT : titre, résumé, image, date -
 * la vignette avec son cadenas, qui donne envie de s'inscrire.
 *
 * DÉCOCHER la case ne restaure pas le corps dans le fichier : il est en
 * base, et le fichier n'en a plus. C'est dit clairement dans Decap ; si
 * le besoin se présente, on rapatrie à la main.
 *
 * Secrets attendus : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Sans eux,
 * le script s'arrête AVANT toute réécriture : on ne vide jamais un
 * fichier dont le corps n'a pas été mis en sûreté.
 */
const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = path.join(__dirname, '..');
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://api.amstc.org';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

// dossier du dépôt -> catégorie en base
const DOSSIERS = { actualites: 'actualite', formations: 'formation' };

const MARQUEUR = '<!-- Contenu réservé aux membres : le texte complet est en base, pas dans ce fichier. -->';

function parseFrontMatter(raw) {
  const m = raw.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n?([\s\S]*)$/);
  if (!m) return null;
  const data = {};
  let cle = null;
  m[1].split(/\r?\n/).forEach((l) => {
    const k = l.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (k) { cle = k[1]; data[cle] = k[2].trim().replace(/^"(.*)"$/, '$1'); }
    else if (cle && l.trim()) data[cle] = (data[cle] + ' ' + l.trim()).trim();
  });
  return { entete: m[1], data, corps: m[2] };
}

function estVrai(v) {
  return v === true || /^(true|yes|oui|1)$/i.test(String(v || '').trim());
}

function rpc(fonction, corps) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(corps);
    const u = new URL(SUPABASE_URL + '/rest/v1/rpc/' + fonction);
    const req = https.request({
      hostname: u.hostname, port: u.port || undefined, path: u.pathname, method: 'POST',
      headers: {
        apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY,
        'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload),
      }, timeout: 20000,
    }, (res) => {
      let b = '';
      res.on('data', (c) => { b += c; });
      res.on('end', () => (res.statusCode >= 200 && res.statusCode < 300)
        ? resolve(b) : reject(new Error('HTTP ' + res.statusCode + ' : ' + b.slice(0, 200))));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(new Error('délai dépassé')); });
    req.end(payload);
  });
}

(async () => {
  // D'abord repérer ce qu'il y a à faire, pour ne pas exiger de secret
  // quand il n'y a rien à réserver.
  const aFaire = [];
  for (const [dossier, categorie] of Object.entries(DOSSIERS)) {
    const dir = path.join(ROOT, 'content', dossier);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.md'))) {
      const chemin = path.join(dir, f);
      const brut = fs.readFileSync(chemin, 'utf8');
      const fm = parseFrontMatter(brut);
      if (!fm || !estVrai(fm.data.reserve)) continue;
      const corps = fm.corps.trim();
      // Déjà vidé : rien à faire.
      if (!corps || corps === MARQUEUR) continue;
      aFaire.push({ chemin, f, slug: f.replace(/\.md$/, ''), categorie, fm, corps });
    }
  }
  if (!aFaire.length) { console.log('Contenus réservés : rien à réserver.'); return; }

  if (!SERVICE_KEY) {
    // On NE VIDE PAS : le corps resterait public, mais au moins il n'est
    // pas perdu. On le dit fort pour que le secret soit ajouté.
    console.error(`Contenus réservés : ${aFaire.length} fiche(s) à réserver mais SUPABASE_SERVICE_ROLE_KEY absent.`
      + ' Ajoutez le secret dans GitHub > Settings > Secrets. Aucun fichier modifié.');
    process.exitCode = 1;
    return;
  }

  let ok = 0;
  for (const it of aFaire) {
    try {
      await rpc('deposer_contenu_reserve', {
        p_slug: it.slug, p_category: it.categorie,
        p_title: it.fm.data.title || '', p_excerpt: it.fm.data.excerpt || '',
        p_image: it.fm.data.image || '', p_content: it.corps,
      });
      // Le corps est en sûreté : on réécrit le fichier sans lui.
      fs.writeFileSync(it.chemin, '---\n' + it.fm.entete.trim() + '\n---\n\n' + MARQUEUR + '\n');
      ok++;
      console.log('  réservé : ' + it.categorie + '/' + it.slug + ' (' + it.corps.length + ' caractères déplacés en base)');
    } catch (e) {
      // Un échec laisse le fichier INTACT : mieux vaut un corps encore
      // public un passage de plus qu'un corps perdu.
      console.error('  ÉCHEC   : ' + it.slug + ' - ' + e.message + ' (fichier laissé tel quel)');
      process.exitCode = 1;
    }
  }
  console.log(`Contenus réservés : ${ok}/${aFaire.length} fiche(s) traitée(s).`);
})();
