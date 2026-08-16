/**
 * Signale les nouveaux contenus PUBLICS du site pour la chaîne Telegram.
 *
 * POURQUOI UN SCRIPT PLUTÔT QU'UN DÉCLENCHEUR SQL. Les actualités,
 * formations, projets, étapes et événements du site public ne vivent pas
 * dans Supabase : ce sont des fichiers Markdown du dépôt, indexés par
 * scripts/build-content-index.js. Aucune base ne peut donc les voir
 * apparaître - c'est la construction qui doit le signaler.
 *
 * ON PROPOSE, ON NE PUBLIE PAS. Chaque nouveauté part d'abord dans le
 * SALON D'ADMINISTRATION, telle qu'elle paraîtrait, avec deux boutons :
 * « Publier sur la chaîne » ou « Ne pas publier ». C'est la fonction
 * Edge telegram-webhook qui publie, au clic. Un contenu mis en ligne
 * pour le site ne mérite pas toujours une annonce à tous les abonnés, et
 * une annonce partie ne se rattrape pas.
 *
 * Sans TELEGRAM_CHAT_ID, le script retombe sur l'ancien comportement -
 * publication directe sur la chaîne : mieux vaut annoncer sans
 * validation que ne rien annoncer du tout.
 *
 * LE PIÈGE DU PREMIER PASSAGE. Sans précaution, la première exécution
 * signalerait les QUATRE-VINGT-DIX contenus déjà en ligne, d'un coup. Le
 * premier passage se contente donc de MÉMORISER l'existant sans rien
 * envoyer ; seuls les ajouts ultérieurs sont signalés. Un garde-fou
 * supplémentaire plafonne chaque passage à MAX_PAR_PASSAGE envois, au
 * cas où l'état serait perdu.
 *
 * CE QUE MÉMORISE L'ÉTAT : ce qui a été SOUMIS, non ce qui a été publié.
 * Un contenu écarté d'un clic ne doit pas revenir toutes les heures : le
 * refus est une décision, pas un échec.
 *
 * L'état vit dans content/.chaine-publiees.json, commité par le workflow
 * au même titre que les index : c'est ce qui rend le script idempotent
 * d'une exécution à l'autre.
 *
 * Secrets attendus (variables d'environnement) :
 *   TELEGRAM_BOT_TOKEN   - le jeton du bot
 *   TELEGRAM_CHAT_ID     - le salon d'administration, qui reçoit les
 *                          propositions
 *   TELEGRAM_CHANNEL_ID  - la chaîne publique ; sert au repli quand
 *                          TELEGRAM_CHAT_ID est absent
 * Sans jeton ni destinataire, le script ne fait rien et sort en succès -
 * la construction du site ne doit pas dépendre de Telegram.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = path.join(__dirname, '..');
const SITE = 'https://amstc.org';
const ETAT = path.join(ROOT, 'content', '.chaine-publiees.json');

// Plafond de sécurité : même si l'état est perdu ou corrompu, un passage
// ne peut pas inonder la chaîne.
const MAX_PAR_PASSAGE = 5;

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const CHANNEL = process.env.TELEGRAM_CHANNEL_ID;
const ADMIN = process.env.TELEGRAM_CHAT_ID;

// La ligne qui sépare l'en-tête de la proposition du texte à publier.
// telegram-webhook coupe dessus : ce qui suit part sur la chaîne, mot
// pour mot. Si vous la changez ici, changez-la LÀ-BAS aussi.
const SEPARATEUR = '──────';

// index, préfixe de page d'aperçu, intitulé
const SOURCES = [
  { index: 'actualites', prefixe: 'a', intitule: 'Nouvel article' },
  { index: 'formations', prefixe: 'f', intitule: 'Nouvelle formation' },
  { index: 'projets',    prefixe: 'p', intitule: 'Nouveau projet' },
  { index: 'etapes',     prefixe: 'e', intitule: 'Nouvelle étape' },
  { index: 'evenements', prefixe: null, intitule: 'Nouvel événement' },
];

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

function lireEtat() {
  if (!fs.existsSync(ETAT)) return null;   // null = jamais initialisé
  try {
    const d = JSON.parse(fs.readFileSync(ETAT, 'utf8'));
    return Array.isArray(d.publiees) ? new Set(d.publiees) : new Set();
  } catch (e) {
    console.error('État illisible, on repart de zéro sans rien annoncer :', e.message);
    return null;
  }
}

function ecrireEtat(cles) {
  fs.writeFileSync(ETAT, JSON.stringify({
    // Pas d'horodatage : il changerait à chaque passage et produirait un
    // commit même quand rien n'a bougé.
    publiees: [...cles].sort(),
  }, null, 2) + '\n');
}

function resume(s, max) {
  const t = String(s == null ? '' : s).replace(/[#*_>`]/g, '').replace(/\s+/g, ' ').trim();
  return t.length <= max ? t : t.slice(0, max - 1).replace(/\s+\S*$/, '') + '…';
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * Envoie soit la PROPOSITION au salon d'administration, soit - à défaut
 * de salon - l'annonce directement sur la chaîne.
 *
 * Le texte à publier est écrit à l'identique dans les deux cas : ce que
 * l'administration relit est exactement ce que les abonnés liront.
 */
function envoyer(titre, texte, lien) {
  const annonce = [`<b>${esc(titre)}</b>`, texte ? esc(texte) : '', lien ? esc(lien) : '']
    .filter(Boolean).join('\n\n');

  const corps = ADMIN
    ? `📣 <b>À publier sur la chaîne ?</b>\n${SEPARATEUR}\n${annonce}`
    : annonce;
  const payload = JSON.stringify({
    chat_id: ADMIN || CHANNEL,
    text: corps,
    parse_mode: 'HTML',
    ...(ADMIN ? {
      disable_web_page_preview: true,
      reply_markup: { inline_keyboard: [[
        { text: '📣 Publier sur la chaîne', callback_data: 'pub:go:x' },
        { text: '✖️ Ne pas publier', callback_data: 'pub:no:x' },
      ]] },
    } : {}),
  });
  return new Promise((resolve) => {
    const req = https.request(`https://api.telegram.org/bot${TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
      timeout: 15000,
    }, (res) => {
      let corpsRep = '';
      res.on('data', (c) => { corpsRep += c; });
      res.on('end', () => {
        if (res.statusCode !== 200) {
          console.error('  échec Telegram', res.statusCode, corpsRep.slice(0, 160));
          resolve(false);
        } else resolve(true);
      });
    });
    // Un échec réseau ne doit pas faire échouer la construction du site.
    req.on('error', (e) => { console.error('  échec réseau :', e.message); resolve(false); });
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.end(payload);
  });
}

(async () => {
  if (!TOKEN || (!ADMIN && !CHANNEL)) {
    console.log('Chaîne Telegram : secrets absents, rien à faire.');
    return;
  }
  console.log(ADMIN
    ? 'Chaîne Telegram : les nouveautés sont PROPOSÉES au salon d\'administration.'
    : 'Chaîne Telegram : TELEGRAM_CHAT_ID absent, publication directe sur la chaîne.');

  // Tout le contenu actuel, sous forme de clés stables.
  const actuels = [];
  for (const s of SOURCES) {
    for (const f of lireIndex(s.index)) {
      const id = f.slug || f.id;
      if (!id) continue;
      actuels.push({
        cle: s.index + ':' + id,
        titre: s.intitule + ' : ' + (f.title || 'AMSTC'),
        texte: resume(f.excerpt || f.description, 180),
        // La page d'aperçu porte titre et image ; à défaut, la page réelle.
        lien: s.prefixe ? `${SITE}/${s.prefixe}/${encodeURIComponent(id)}.html`
                        : `${SITE}/evenements.html`,
      });
    }
  }

  const connues = lireEtat();

  // PREMIER PASSAGE : on mémorise sans annoncer. C'est la protection qui
  // évite d'envoyer 90 messages d'un coup le jour de la mise en service.
  if (connues === null) {
    ecrireEtat(actuels.map((a) => a.cle));
    console.log(`Chaîne Telegram : premier passage, ${actuels.length} contenu(s) `
      + `mémorisé(s) sans annonce. Les prochains ajouts seront signalés.`);
    return;
  }

  const nouveaux = actuels.filter((a) => !connues.has(a.cle));
  if (!nouveaux.length) {
    console.log('Chaîne Telegram : aucun nouveau contenu.');
    return;
  }

  const aEnvoyer = nouveaux.slice(0, MAX_PAR_PASSAGE);
  if (nouveaux.length > MAX_PAR_PASSAGE) {
    console.log(`Chaîne Telegram : ${nouveaux.length} nouveautés, plafonné à `
      + `${MAX_PAR_PASSAGE} pour ce passage. Le reste suivra au prochain.`);
  }

  for (const n of aEnvoyer) {
    const ok = await envoyer(n.titre, n.texte, n.lien);
    console.log(`  ${ok ? (ADMIN ? 'proposé' : 'annoncé') : 'ÉCHEC  '} : ${n.cle}`);
    // Seul ce qui est réellement parti est mémorisé : un échec sera
    // réessayé au passage suivant plutôt que perdu en silence. Un refus,
    // lui, ne repassera pas : c'est une décision, pas un échec.
    if (ok) connues.add(n.cle);
  }

  ecrireEtat(connues);
  console.log(`Chaîne Telegram : ${aEnvoyer.length} contenu(s) traité(s).`);
})();
