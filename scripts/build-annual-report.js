// Génère une page de bilan annuel (rapports/<année>.html) à partir de
// content/actualites-index.json, prête à imprimer ou exporter en PDF
// (bouton "Imprimer / Enregistrer en PDF" -> window.print(), le
// navigateur gère l'export PDF nativement, aucune dépendance requise).
//
// Usage : node scripts/build-annual-report.js <année>
// Exemple : node scripts/build-annual-report.js 2025

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const year = process.argv[2];

if (!year || !/^\d{4}$/.test(year)) {
  console.error('Usage : node scripts/build-annual-report.js <année>');
  console.error('Exemple : node scripts/build-annual-report.js 2025');
  process.exit(1);
}

const indexPath = path.join(ROOT, 'content', 'actualites-index.json');
if (!fs.existsSync(indexPath)) {
  console.error(`Introuvable : ${indexPath}. Lancez d'abord scripts/build-content-index.js.`);
  process.exit(1);
}

const allItems = JSON.parse(fs.readFileSync(indexPath, 'utf8'));
const yearItems = allItems
  .filter(a => a.date && new Date(a.date).getUTCFullYear() === Number(year))
  .sort((a, b) => new Date(a.date) - new Date(b.date));

if (yearItems.length === 0) {
  console.error(`Aucune réalisation trouvée pour ${year}.`);
  process.exit(1);
}

function esc(s) {
  return String(s || '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function formatDate(d) {
  return new Date(d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
}

function resolveAsset(p) {
  if (!p) return '';
  if (/^https?:\/\//.test(p) || p.startsWith('/')) return p;
  return '../' + p;
}

const itemsHtml = yearItems.map((a, i) => `
      <article class="report-item">
        <div class="report-item-num">${String(i + 1).padStart(2, '0')}</div>
        <div class="report-item-body">
          ${a.image ? `<img src="${esc(resolveAsset(a.image))}" alt="" class="report-item-img">` : ''}
          <div class="report-item-text">
            <span class="report-item-date">${formatDate(a.date)}</span>
            <h3>${esc(a.title)}</h3>
            ${a.excerpt ? `<p>${esc(a.excerpt)}</p>` : ''}
          </div>
        </div>
      </article>`).join('\n');

const html = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Rapport annuel ${year} - AMSTC</title>
<meta name="robots" content="noindex">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{
    --ink:#0B2E17; --green:#17763B; --green-deep:#06441C; --gold:#F8B718; --gold-deep:#AA7B11;
    --paper:#F6F7F1; --paper-alt:#ECEFE3; --white:#FFFFFF; --line:rgba(6,68,28,0.14);
    --display:'Sora',sans-serif; --body:'Inter',-apple-system,sans-serif; --mono:'JetBrains Mono',monospace;
  }
  *{box-sizing:border-box;margin:0;padding:0;}
  body{font-family:var(--body);color:var(--ink);background:var(--paper);line-height:1.6;padding:0 0 60px;}
  a{color:inherit;}
  .wrap{max-width:820px;margin:0 auto;padding:0 28px;}

  header{background:var(--green-deep);padding:36px 0;margin-bottom:36px;}
  .report-logo{height:44px;filter:brightness(0) invert(1);margin-bottom:18px;}
  header .eyebrow{font-family:var(--mono);font-size:0.78rem;text-transform:uppercase;letter-spacing:0.1em;color:var(--gold);margin-bottom:8px;}
  header h1{font-family:var(--display);font-weight:700;font-size:clamp(1.6rem,4vw,2.3rem);color:var(--white);margin-bottom:8px;}
  header p{color:rgba(255,255,255,0.75);font-size:0.98rem;}

  .toolbar{display:flex;justify-content:flex-end;margin-bottom:28px;}
  .btn-print{
    display:inline-flex;align-items:center;gap:8px;font-family:var(--body);font-weight:600;font-size:0.92rem;
    padding:11px 22px;border-radius:999px;border:none;background:var(--gold);color:var(--green-deep);cursor:pointer;
  }
  .btn-print:hover{background:var(--gold-deep);color:var(--white);}

  .report-items{display:flex;flex-direction:column;gap:20px;margin-bottom:48px;}
  .report-item{
    display:grid;grid-template-columns:52px 1fr;gap:18px;background:var(--white);
    border:1px solid var(--line);border-radius:14px;padding:22px 24px;
  }
  .report-item-num{font-family:var(--display);font-weight:800;font-size:1.3rem;color:var(--gold-deep);}
  .report-item-body{display:flex;gap:18px;flex-wrap:wrap;}
  .report-item-img{width:140px;height:100px;object-fit:cover;border-radius:8px;flex-shrink:0;}
  .report-item-text{flex:1;min-width:200px;}
  .report-item-date{font-family:var(--mono);font-size:0.72rem;text-transform:uppercase;letter-spacing:0.06em;color:var(--gold-deep);}
  .report-item-text h3{font-family:var(--display);font-weight:600;font-size:1.05rem;color:var(--green-deep);margin:6px 0 6px;}
  .report-item-text p{font-size:0.92rem;color:#465A4E;}

  footer{text-align:center;font-size:0.85rem;color:#5A6C60;}
  footer p{margin-bottom:4px;}

  @media print{
    body{background:#fff;padding:0;}
    header{background:#fff !important;padding:20px 0;}
    .report-logo{filter:none;height:38px;}
    header .eyebrow{color:var(--gold-deep);}
    header h1, header p{color:var(--ink) !important;}
    .toolbar{display:none;}
    .report-item{border:1px solid #ccc;box-shadow:none;break-inside:avoid;page-break-inside:avoid;}
  }
</style>
</head>
<body>

<header>
  <div class="wrap">
    <img src="../assets/logo-horizontal.png" alt="AMSTC" class="report-logo">
    <p class="eyebrow">Rapport annuel</p>
    <h1>Bilan des réalisations ${year}</h1>
    <p>${yearItems.length} réalisation${yearItems.length > 1 ? 's' : ''} - Association Médico-Sociale des Talibés Cheikh</p>
  </div>
</header>

<div class="wrap">
  <div class="toolbar">
    <button class="btn-print" onclick="window.print()">🖨️ Imprimer / Enregistrer en PDF</button>
  </div>

  <div class="report-items">
${itemsHtml}
  </div>

  <footer>
    <p>Association Médico-Sociale des Talibés Cheikh (AMSTC)</p>
    <p>Récépissé n° 022909/MISP/DGAT/DLPL/DAPA</p>
    <p>Généré automatiquement depuis amstc.org</p>
  </footer>
</div>

</body>
</html>
`;

const outDir = path.join(ROOT, 'rapports');
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, `${year}.html`);
fs.writeFileSync(outFile, html);
console.log(`rapports/${year}.html généré avec ${yearItems.length} réalisation(s).`);
