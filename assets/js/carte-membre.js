// ===== Moteur de dessin de la carte de membre (template officiel) =====
// Partagé par membres/profil.html (carte à l'écran + PDF individuel) et
// membres/validation.html (impression des cartes en lot). Un seul rendu,
// sur canvas : bord dégradé or->vert, logo de l'association, pilule verte
// CARTE DE MEMBRE, photo ronde cerclée (initiales en repli), QR code avec
// le numéro dessous, champs Prénom / NOM / Filière / Tel / Validité.
//
// Dépendances à charger par la page : qrcode.min.js (génération du QR) et
// les polices Sora/Inter. Les pages appelantes vivent dans membres/, d'où
// le chemin relatif du logo.

const CARTE_MEMBRE = {
  W: 2000, H: 1294, // ratio 85 x 55 mm (format d'impression)
  OR: '#F8B718', VERT: '#1B7A3E', VERT_FONCE: '#06441C', NOIR: '#111111',
};

const CARTE_DOMAINES = {
  medecine: 'Médecine', pharmacie: 'Pharmacie', odontologie: 'Odontologie',
  soins_infirmiers: 'Soins infirmiers', soins_obstetricaux: 'Soins obstétricaux',
};

function carteNumeroPour(p) {
  return p.legacy_card_number
    || ('AMSTC-' + String(p.member_since || new Date().getFullYear()) + '-' + p.id.slice(0, 4).toUpperCase());
}

// Seuls Dr et Pr précèdent le nom (même règle que l'affichage du site).
function carteNomAffiche(p) {
  const titre = (p.title === 'Dr' || p.title === 'Pr') ? p.title : null;
  const parts = [titre, p.first_name, p.last_name].filter(Boolean);
  return parts.length ? parts.join(' ') : (p.full_name || p.email || '-');
}

// "Filière" du template : le domaine (ou sa précision "autre"), sans la
// spécialité pour rester sur une ligne.
function carteFilierePour(p) {
  if (p.domain === 'autre') return p.domain_autre || 'Autre';
  return CARTE_DOMAINES[p.domain] || '-';
}

function carteChargerImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

async function carteUrlVersDataUrl(url) {
  const res = await fetch(url);
  const blob = await res.blob();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

function carteDegrade(ctx, x0, y0, x1, y1) {
  const g = ctx.createLinearGradient(x0, y0, x1, y1);
  g.addColorStop(0, CARTE_MEMBRE.OR);
  g.addColorStop(1, '#17763B');
  return g;
}

function cartePilule(ctx, x, y, w, h, fill) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, h / 2);
  ctx.fillStyle = fill;
  ctx.fill();
}

// Version JPEG (fond blanc, sans canal alpha) pour les PDF : jsPDF stocke
// les PNG à transparence en bitmap brut, ce qui gonflait le fichier à
// ~10 Mo PAR CARTE. En JPEG : ~200 Ko par page.
async function carteJpegDataUrl(p) {
  const canvas = await dessinerCarteMembre(p);
  const fond = document.createElement('canvas');
  fond.width = canvas.width; fond.height = canvas.height;
  const ctx = fond.getContext('2d');
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, fond.width, fond.height);
  ctx.drawImage(canvas, 0, 0);
  return fond.toDataURL('image/jpeg', 0.92);
}

async function dessinerCarteMembre(p) {
  await document.fonts.ready; // Sora/Inter chargées avant de dessiner
  const anneeCourante = new Date().getFullYear();
  const { W, H } = CARTE_MEMBRE;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d');
  const s = W / 1000; // toutes les cotes ci-dessous sont pensées sur 1000pt de large

  // Fond blanc arrondi + bord dégradé
  ctx.beginPath(); ctx.roundRect(0, 0, W, H, 56 * s);
  ctx.fillStyle = '#FFFFFF'; ctx.fill();
  ctx.beginPath(); ctx.roundRect(11 * s, 11 * s, W - 22 * s, H - 22 * s, 48 * s);
  ctx.strokeStyle = carteDegrade(ctx, 0, 0, W, H);
  ctx.lineWidth = 9 * s;
  ctx.stroke();

  // Logo complet du dépôt (emblème + AMSTC + nom de l'association) : il
  // reproduit déjà exactement le haut du template, on le centre tel quel.
  ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
  try {
    const logo = await carteChargerImage('../assets/logo-mark-sm.png');
    const lh = 128 * s, lw = lh * (logo.naturalWidth / logo.naturalHeight);
    ctx.drawImage(logo, 640 * s - lw / 2, 52 * s, lw, lh);
  } catch (e) { /* logo indisponible : la carte reste valable */ }

  // Pilule CARTE DE MEMBRE (à droite de la photo, sans chevauchement)
  cartePilule(ctx, 370 * s, 198 * s, 580 * s, 74 * s, CARTE_MEMBRE.VERT);
  ctx.fillStyle = '#FFFFFF';
  ctx.font = '800 ' + (50 * s) + 'px Sora, Inter, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('CARTE DE MEMBRE', 660 * s, 252 * s);

  // Photo ronde cerclée d'un dégradé
  const cx = 205 * s, cy = 220 * s, R = 118 * s;
  ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.strokeStyle = carteDegrade(ctx, cx, cy - R, cx, cy + R);
  ctx.lineWidth = 10 * s; ctx.stroke();

  const rPhoto = R - 9 * s;
  ctx.save();
  ctx.beginPath(); ctx.arc(cx, cy, rPhoto, 0, Math.PI * 2); ctx.clip();
  let photoOk = false;
  if (p.photo_url) {
    try {
      const photo = await carteChargerImage(await carteUrlVersDataUrl(p.photo_url));
      const cote = Math.min(photo.naturalWidth, photo.naturalHeight);
      ctx.drawImage(photo,
        (photo.naturalWidth - cote) / 2, (photo.naturalHeight - cote) / 2, cote, cote,
        cx - rPhoto, cy - rPhoto, rPhoto * 2, rPhoto * 2);
      photoOk = true;
    } catch (e) { /* photo introuvable : initiales ci-dessous */ }
  }
  if (!photoOk) {
    ctx.fillStyle = '#ECEFE3';
    ctx.fillRect(cx - rPhoto, cy - rPhoto, rPhoto * 2, rPhoto * 2);
    const initiales = (p.full_name || p.email || '?').split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase();
    ctx.fillStyle = '#17763B';
    ctx.font = '800 ' + (72 * s) + 'px Sora, Inter, sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(initiales, cx, cy);
    ctx.textBaseline = 'alphabetic';
  }
  ctx.restore();

  // QR code dans un carré arrondi (généré ici : identité + numéro)
  const qx = 127 * s, qy = 391 * s, qc = 170 * s;
  ctx.beginPath(); ctx.roundRect(qx, qy, qc, qc, 22 * s);
  ctx.strokeStyle = carteDegrade(ctx, qx, qy, qx + qc, qy + qc);
  ctx.lineWidth = 4 * s; ctx.stroke();
  try {
    const texteQr = 'AMSTC | ' + carteNomAffiche(p) + ' | N° ' + carteNumeroPour(p);
    const qrDataUrl = await QRCode.toDataURL(texteQr, { width: 340, margin: 1, color: { dark: '#06441C', light: '#ffffff' } });
    const qr = await carteChargerImage(qrDataUrl);
    ctx.drawImage(qr, qx + 10 * s, qy + 10 * s, qc - 20 * s, qc - 20 * s);
  } catch (e) { /* QR indisponible : cadre vide */ }

  // Numéro de carte sous le QR
  ctx.fillStyle = CARTE_MEMBRE.VERT_FONCE;
  ctx.font = '700 ' + (24 * s) + 'px Sora, Inter, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(carteNumeroPour(p), qx + qc / 2, qy + qc + 36 * s);
  ctx.textAlign = 'left';

  // Champs identité (5 lignes, validité incluse - conforme au template)
  const validite = p.card_valid_until
    ? Math.min(anneeCourante, p.card_valid_until) + ' - ' + p.card_valid_until
    : '-';
  const champs = [
    ['Prénom : ', p.first_name || (p.full_name ? p.full_name.split(' ')[0] : '-')],
    ['NOM : ', (p.last_name || (p.full_name ? p.full_name.split(' ').slice(1).join(' ') : '-') || '-').toUpperCase()],
    ['Filière : ', carteFilierePour(p)],
    ['Tel : ', p.phone || '-'],
    ['Validité : ', validite],
  ];
  ctx.textAlign = 'left';
  let y = 330 * s;
  for (const [label, valeur] of champs) {
    ctx.fillStyle = CARTE_MEMBRE.NOIR;
    ctx.font = '400 ' + (35 * s) + 'px Sora, Inter, sans-serif';
    ctx.fillText(label, 370 * s, y);
    const lw = ctx.measureText(label).width;
    ctx.font = '800 ' + (37 * s) + 'px Sora, Inter, sans-serif';
    ctx.fillText(String(valeur), 370 * s + lw, y);
    y += 62 * s;
  }

  return canvas;
}
