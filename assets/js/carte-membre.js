// ===== Moteur de dessin de la carte de membre (template officiel) =====
// Partagé par membres/profil.html (carte à l'écran + PDF individuel) et
// membres/validation.html (impression des cartes en lot). Un seul rendu,
// sur canvas : bord dégradé or->vert, logo de l'association, pilule verte
// CARTE DE MEMBRE, photo ronde cerclée (initiales en repli), QR code avec
// le numéro dessous, champs Prénom / NOM / Filière / Localité / Tel /
// Validité - la localité au format « Localité, Région ».
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
  if (p && p.legacy_card_number) return p.legacy_card_number;
  // Numéro provisoire à partir de l'identifiant du compte. L'identifiant
  // peut manquer selon l'écran appelant (fiche partielle, aperçu) : sans
  // cette garde, tout le dessin de la carte échouait sur un « slice »
  // d'indéfini - repéré par la revue du 16/08/2026.
  const suffixe = p && p.id ? String(p.id).replace(/-/g, '').slice(0, 4).toUpperCase() : '0000';
  return 'AMSTC-' + String((p && p.member_since) || new Date().getFullYear()) + '-' + suffixe;
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

/**
 * Réduit un texte jusqu'à ce qu'il tienne dans la largeur donnée, et
 * renvoie { texte, taille }.
 *
 * POURQUOI. La carte part à l'impression : un nom qui sort du cadre n'est
 * pas un défaut d'affichage, c'est une carte inutilisable. Or les membres
 * saisissent librement - « AHMAD TIDIANE DIAWARA » en nom, un prénom
 * composé de trois mots - et rien ne garantit la longueur.
 *
 * Trois leviers, dans cet ordre : rétrécir la police (le texte reste
 * intact), abréger les mots intermédiaires (« AHMAD T. DIAWARA » - le
 * premier et le dernier mot portent l'identité), puis tronquer. Le texte
 * complet à petite taille est préféré à un texte abrégé en grand : mieux
 * vaut un nom exact qu'un nom raccourci.
 *
 * L'abréviation ne vaut QUE pour les noms (option « abreger »). Appliquée
 * à une filière ou à une adresse, elle produit du charabia : « Technicien
 * supérieur en imagerie médicale » devenait « Technicien s. e. i.
 * médicale », et « Parcelles Assainies Unité 26 » devenait « Parcelles A.
 * U. 2. ». Pour ces champs, une troncature franche reste lisible.
 */
function carteAjusterTexte(ctx, texte, maxLargeur, options) {
  const o = options || {};
  const s = o.s || 1;
  const poids = o.poids || '800';
  const tailleMax = o.tailleMax || 37;
  const tailleMin = o.tailleMin || 26;
  const police = (t) => poids + ' ' + (t * s) + 'px Sora, Inter, sans-serif';
  const tient = (txt, taille) => {
    ctx.font = police(taille);
    return ctx.measureText(txt).width <= maxLargeur;
  };

  for (let t = tailleMax; t >= tailleMin; t--) {
    if (tient(texte, t)) return { texte: texte, taille: t };
  }

  const mots = String(texte).split(/\s+/).filter(Boolean);
  if (o.abreger && mots.length > 2) {
    const abrege = [mots[0]]
      .concat(mots.slice(1, -1).map(m => m[0] + '.'))
      .concat([mots[mots.length - 1]])
      .join(' ');
    for (let t = tailleMax; t >= tailleMin; t--) {
      if (tient(abrege, t)) return { texte: abrege, taille: t };
    }
    texte = abrege;
  }

  // Dernier recours : on coupe. Jamais de débordement.
  ctx.font = police(tailleMin);
  let coupe = String(texte);
  while (coupe.length > 1 && ctx.measureText(coupe + '…').width > maxLargeur) {
    coupe = coupe.slice(0, -1);
  }
  return { texte: coupe.replace(/\s+$/, '') + '…', taille: tailleMin };
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

  // Champs identité (6 lignes, validité incluse). La localité s'écrit
  // « Localité, Région » - « Darou Salam, Thiès » ; sans région, la
  // localité seule. L'interligne passe de 62 à 56 et le départ remonte :
  // la sixième ligne doit rester dans le cadre (647 pt de haut).
  const validite = p.card_valid_until
    ? Math.min(anneeCourante, p.card_valid_until) + ' - ' + p.card_valid_until
    : '-';
  const localite = [
    String(p.city || '').trim(),
    String(p.region || '').trim(),
  ].filter(Boolean).join(', ') || '-';
  // Le drapeau dit si le champ accepte l'abréviation en initiales : les
  // noms oui, le reste non (voir carteAjusterTexte).
  const champs = [
    ['Prénom : ', p.first_name || (p.full_name ? p.full_name.split(' ')[0] : '-'), true],
    ['NOM : ', (p.last_name || (p.full_name ? p.full_name.split(' ').slice(1).join(' ') : '-') || '-').toUpperCase(), true],
    ['Filière : ', carteFilierePour(p), false],
    ['Localité : ', localite, false],
    ['Tel : ', p.phone || '-', false],
    ['Validité : ', validite, false],
  ];
  ctx.textAlign = 'left';
  let y = 322 * s;
  for (const [label, valeur, abreger] of champs) {
    ctx.fillStyle = CARTE_MEMBRE.NOIR;
    ctx.font = '400 ' + (35 * s) + 'px Sora, Inter, sans-serif';
    ctx.fillText(label, 370 * s, y);
    const lw = ctx.measureText(label).width;
    // Aucune valeur ne dépasse le bord intérieur (965 pt) : rétrécissement,
    // puis abréviation, puis troncature. Voir carteAjusterTexte.
    const ajuste = carteAjusterTexte(ctx, String(valeur), 965 * s - (370 * s + lw), { s, abreger });
    ctx.font = '800 ' + (ajuste.taille * s) + 'px Sora, Inter, sans-serif';
    ctx.fillText(ajuste.texte, 370 * s + lw, y);
    y += 56 * s;
  }

  return canvas;
}
