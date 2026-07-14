const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

function parseFrontMatter(raw) {
  const match = raw.match(/^---\s*([\s\S]*?)\s*---\s*([\s\S]*)$/);
  if (!match) return {};
  const data = {};
  match[1].split('\n').forEach(line => {
    const idx = line.indexOf(':');
    if (idx === -1) return;
    const key = line.slice(0, idx).trim();
    const val = line.slice(idx + 1).trim().replace(/^"(.*)"$/, '$1');
    data[key] = val;
  });
  return data;
}

function buildIndex(folderName) {
  const dir = path.join(ROOT, 'content', folderName);
  const outFile = path.join(ROOT, 'content', `${folderName}-index.json`);
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.md')) : [];

  const items = files.map(f => {
    const raw = fs.readFileSync(path.join(dir, f), 'utf8');
    const data = parseFrontMatter(raw);
    return {
      slug: f.replace(/\.md$/, ''),
      title: data.title || '',
      date: data.date || '',
      excerpt: data.excerpt || '',
      image: data.image || ''
    };
  });

  items.sort((a, b) => new Date(b.date) - new Date(a.date));
  fs.writeFileSync(outFile, JSON.stringify(items, null, 2) + '\n');
  console.log(`${outFile}: ${items.length} article(s)`);
}

buildIndex('actualites');
buildIndex('formations');
