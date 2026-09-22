/**
 * Génère guide-site-amstc.pdf à partir de guide.html.
 *
 * POURQUOI UN SCRIPT. Le PDF était exporté à la main : il a vite décrit
 * un site qui n'existait plus. Ici, il se refait en une commande, depuis
 * la page elle-même - une seule source, celle que lisent les visiteurs.
 *
 *   node scripts/build-guide-pdf.js
 *
 * COMMENT. La page cache l'espace membres et l'administration tant que
 * personne n'est connecté (Supabase répond « visiteur »). Le PDF, lui,
 * est destiné aux membres et aux administrateurs : le script prépare une
 * copie temporaire où ces parties sont visibles et où chaque fiche est
 * dépliée, puis demande à Chrome (ou Edge) de l'imprimer.
 *
 * Aucune dépendance à installer : on utilise le navigateur déjà présent
 * sur la machine, en mode « headless ».
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const SOURCE = path.join(ROOT, 'guide.html');
const SORTIE = path.join(ROOT, 'guide-site-amstc.pdf');

// Le navigateur : Chrome d'abord, Edge ensuite. CHROME_PATH force un choix.
function trouverNavigateur() {
  const candidats = [
    process.env.CHROME_PATH,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ].filter(Boolean);
  const trouve = candidats.find(c => fs.existsSync(c));
  if (!trouve) {
    console.error("Aucun navigateur trouvé. Indiquez-en un : CHROME_PATH=... node scripts/build-guide-pdf.js");
    process.exit(1);
  }
  return trouve;
}

function preparerCopie() {
  let html = fs.readFileSync(SOURCE, 'utf8');

  // 1. Les parties réservées deviennent visibles : le PDF s'adresse aux
  //    membres et aux administrateurs.
  html = html.replace(/(data-tier="(?:membres|admin)")\s+style="display:none;"/g, '$1');

  // 2. Chaque fiche est dépliée : un PDF ne se clique pas.
  html = html.replace(/<details class="page-card">/g, '<details class="page-card" open>');

  // 3. Le script qui adapte la page au profil n'a plus rien à faire, et
  //    Supabase n'est pas joignable hors ligne.
  html = html.replace(/<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js@2"><\/script>/, '');
  html = html.replace(/<script src="assets\/js\/supabase-client\.js"><\/script>/, '');

  // 4. Le chapeau annonce les trois niveaux : c'est ce que le PDF contient.
  html = html.replace(
    /<p class="hero-lede" id="heroLede">[\s\S]*?<\/p>/,
    '<p class="hero-lede" id="heroLede">Ce guide couvre les trois niveaux du site de '
    + "l'Association Médico-Sociale des Talibés Cheikh : le site public, l'espace membres, "
    + "et les outils d'administration. Pour chaque page : à quoi elle sert, comment y accéder, "
    + "et ce qu'on peut y faire.</p>");

  // 5. Repère pour les styles d'impression (voir guide.html).
  html = html.replace('<body>', '<body class="guide-pdf">');

  const copie = path.join(ROOT, '_guide-pdf.html');
  fs.writeFileSync(copie, html);
  return copie;
}

const navigateur = trouverNavigateur();
const copie = preparerCopie();
const profil = fs.mkdtempSync(path.join(os.tmpdir(), 'amstc-pdf-'));

try {
  execFileSync(navigateur, [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--user-data-dir=' + profil,
    '--no-pdf-header-footer',
    '--print-to-pdf=' + SORTIE,
    'file:///' + copie.replace(/\\/g, '/'),
  ], { stdio: 'inherit', timeout: 120000 });
} finally {
  fs.unlinkSync(copie);
  fs.rmSync(profil, { recursive: true, force: true });
}

const ko = Math.round(fs.statSync(SORTIE).size / 1024);
console.log('guide-site-amstc.pdf régénéré depuis guide.html (' + ko + ' Ko).');
