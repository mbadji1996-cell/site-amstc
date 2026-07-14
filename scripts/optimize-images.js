const sharp = require('sharp');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const asset = (f) => path.join(ROOT, 'assets', f);

async function main() {
  // logo-mark.png = the actual horizontal lockup (icon + "AMSTC" text), used in nav/footer/404
  await sharp(asset('logo-mark.png'))
    .resize({ width: 640 })
    .png({ quality: 90, compressionLevel: 9 })
    .toFile(asset('logo-mark-sm.png'));

  // logo-horizontal.png = the actual square stacked lockup, used for favicon/admin CMS logo
  await sharp(asset('logo-horizontal.png'))
    .resize({ width: 400 })
    .png({ quality: 90, compressionLevel: 9 })
    .toFile(asset('logo-horizontal-sm.png'));

  // Build a white silhouette of the horizontal lockup, for the OG/share image on a dark background
  const origMeta = await sharp(asset('logo-mark.png')).metadata();
  const w = 720;
  const h = Math.round(origMeta.height * (w / origMeta.width));
  const alpha = await sharp(asset('logo-mark.png')).resize({ width: w }).ensureAlpha().extractChannel('alpha').raw().toBuffer();
  const white = await sharp({
    create: { width: w, height: h, channels: 3, background: { r: 255, g: 255, b: 255 } }
  }).raw().toBuffer();
  const whiteLogo = await sharp(white, { raw: { width: w, height: h, channels: 3 } })
    .joinChannel(alpha, { raw: { width: w, height: h, channels: 1 } })
    .png()
    .toBuffer();

  const whiteLogoMeta = { width: w, height: h };

  // OG / social share image: 1200x630, brand green background, white logo centered
  await sharp({
    create: { width: 1200, height: 630, channels: 3, background: { r: 6, g: 68, b: 28 } } // --green-deep
  })
    .composite([{
      input: whiteLogo,
      left: Math.round((1200 - whiteLogoMeta.width) / 2),
      top: Math.round((630 - whiteLogoMeta.height) / 2)
    }])
    .jpeg({ quality: 88 })
    .toFile(asset('og-image.jpg'));

  console.log('Done: logo-mark-sm.png, logo-horizontal-sm.png, og-image.jpg');
}

main().catch(err => { console.error(err); process.exit(1); });
