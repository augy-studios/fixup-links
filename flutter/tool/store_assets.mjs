// The Google Play listing's pictures (GOOGLE-PLAY.md, "Store listing"), as sgbus-timings' are:
// each of the app's real screens (build/shots/, from test/shots/store_shots_test.dart) in a device
// on the brand green, a headline in Jua, and a few hand-written notes with chalk arrows to what
// they're about. Drawn as a page in Chromium (Playwright) and saved at Play's sizes:
//
//   docs/phone-assets/01-*.png ... 08-*.png         1620 x 2880 (9:16), phone screenshots
//   docs/tablet-assets/7-inch/*.png, 10-inch/*.png   1620 x 2880 (9:16), tablet screenshots
//   docs/desktop-assets/*.png                        2880 x 1620 (16:9), Chromebook screenshots
//   docs/feature-graphic.png                         1024 x 500, the feature graphic (no alpha)
//
//   SHOTS=all flutter test test/shots/        first, for build/shots/
//   node tool/store_assets.mjs                then (from flutter/; PLAYWRIGHT=<path> if need be)
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require(process.env.PLAYWRIGHT || 'playwright');
} catch {
  playwright = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
}

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const docs = join(root, '..', 'docs');
const shots = join(root, 'build', 'shots');
const jua = pathToFileURL(join(root, 'assets', 'fonts', 'Jua-Regular.ttf')).href;
const logo = `data:image/png;base64,${readFileSync(join(root, '..', 'main-site', 'UFX-512.png')).toString('base64')}`;
const marksOf = (name) => (existsSync(join(shots, `${name}.json`)) ? JSON.parse(readFileSync(join(shots, `${name}.json`), 'utf8')) : {});
const img = (name) => `data:image/png;base64,${readFileSync(join(shots, `${name}.png`)).toString('base64')}`;

// Each picture: the screen, its headline, and its notes. A note's arrow runs to a marked thing on
// the screen (`to`: a TourTarget's id, whose place the shot test writes beside each picture), at
// its left, middle or right (`at`), `fy` of the way down it; or to `tx`, `ty`, fractions of the
// screen. The note sits on its side (`side`) level with that, `dy` of the picture lower.
const PHONE = [
  ['01-clean-in-one-tap', 'home', 'Clean links,\nin one tap.', [
    { text: 'Trackers,\ngone', side: 'l', to: 'home.changes', at: 'l', dy: 0.07 },
    { text: 'Previews that\nwork in Discord\n& Telegram', side: 'r', to: 'home.result', at: 'r', dy: -0.07 },
  ]],
  ['02-fix-from-any-app', 'quick', 'Fix a link\nfrom any app.', [
    { text: 'Highlight a link,\npick Fix link', side: 'l', to: 'home.input', at: 'l', dy: 0.08 },
    { text: 'Replace puts\nit back for you', side: 'r', to: 'quick.replace', at: 'r', dy: -0.08 },
  ]],
  ['03-every-link', 'history', 'Every link\nyou\u2019ve fixed.', [
    { text: 'With its\npage\u2019s title', side: 'l', to: 'history.list', at: 'l', fy: 0.25, dy: 0.08 },
    { text: 'Tap one to\nfix it again', side: 'r', to: 'history.list', at: 'r', fy: 0.75, dy: 0.12 },
  ]],
  ['04-all-your-devices', 'sync', 'Your history,\non all your devices.', [
    { text: 'Scan it, or\ntype the code', side: 'l', to: 'sync.code', at: 'l', fy: 0.5, dy: 0.1 },
    { text: 'Straight from\none to the\nother', side: 'r', to: 'sync.note', at: 'r', dy: -0.1 },
  ]],
  ['05-your-look', 'look', 'Material You,\nor UwU Apps.', [
    { text: 'Light, dark,\nor by the clock', side: 'l', to: 'look.mode', at: 'l', dy: 0.1 },
    { text: 'Seven\ncolours', side: 'r', to: 'look.colour', at: 'r', fy: 0.4, dy: 0.12 },
  ]],
  ['06-easy-at-night', 'home-dark', 'Easy on the\neyes at night.', [
    { text: 'Dark, in any\nof seven colours', side: 'l', to: 'home.clean', at: 'l', dy: -0.1 },
    { text: 'TikTok links\nthat preview', side: 'r', to: 'home.result', at: 'r', dy: 0.1 },
  ]],
  ['07-sites-it-knows', 'platforms', '29 sites it\nknows by heart.', [
    { text: 'X, Instagram,\nTikTok & more', side: 'l', to: 'home.platforms', at: 'l', fy: 0.2, dy: -0.06 },
    { text: 'Every other link\nloses its\ntrackers too', side: 'r', to: 'home.platforms', at: 'r', fy: 0.85, dy: 0.08 },
  ]],
  ['08-shows-you-around', 'tour', 'It shows\nyou around.', [
    { text: 'A quick tour\nof each page', side: 'l', to: 'home.clean', at: 'l', dy: 0.12 },
    { text: 'Replay any\ntime', side: 'r', to: 'tray.tour', at: 'c', dy: 0.1 },
  ]],
];

const DESKTOP = [
  ['01-clean-in-one-tap', 'desktop-split', 'Clean links, in one click.', [
    { text: 'History\nright beside it', side: 'l', to: 'history.list', at: 'l', dy: 0.12 },
    { text: 'Trackers,\ngone', side: 'l', to: 'home.changes', at: 'l', dy: 0.2 },
    { text: 'Previews that\nwork everywhere', side: 'r', to: 'home.result', at: 'r', dy: -0.12 },
  ]],
  ['02-paste-anywhere', 'desktop-command', 'Ctrl+K: paste, search, go.', [
    { text: 'Paste a link\nand press Enter', side: 'l', tx: 0.28, ty: 0.02, y: 0.3 },
    { text: 'Finds anything\nin your history', side: 'r', tx: 0.6, ty: 0.1, y: 0.35 },
  ]],
  ['03-all-your-devices', 'desktop-sync', 'Your history, on all your devices.', [
    { text: 'Scan with\nyour phone', side: 'l', to: 'sync.code', at: 'l', fy: 0.5, dy: 0.12 },
    { text: 'Straight from\none to the other', side: 'r', to: 'sync.note', at: 'r', dy: 0.1 },
  ]],
  ['04-your-look', 'desktop-look', 'Your look, your colours.', [
    { text: 'UwU Apps\nor Material You', side: 'l', to: 'look.style', at: 'l', dy: 0.12 },
    { text: 'Seven colours,\nor your computer\u2019s', side: 'r', to: 'look.colour', at: 'r', fy: 0.3, dy: 0.1 },
  ]],
  ['05-easy-at-night', 'desktop-dark', 'Easy on the eyes at night.', [
    { text: 'Dark, in any\nof seven colours', side: 'r', to: 'home.result', at: 'r', dy: -0.12 },
  ]],
  ['06-material-you', 'desktop-you', 'Material You, on desktop too.', [
    { text: 'Colours from\nyour computer', side: 'r', to: 'home.clean', at: 'r', dy: -0.12 },
  ]],
  ['07-sites-it-knows', 'desktop-platforms', '29 sites it knows by heart.', [
    { text: 'And every other\nlink loses its\ntrackers too', side: 'r', to: 'home.platforms', at: 'r', fy: 0.7, dy: 0.05 },
  ]],
  ['08-shows-you-around', 'desktop-tour', 'It shows you around.', [
    { text: 'A quick tour\nof each page', side: 'l', to: 'home.clean', at: 'l', dy: 0.12 },
  ]],
];

const css = `
@font-face { font-family: Jua; src: url("${jua}"); }
* { margin: 0; box-sizing: border-box; }
body { width: var(--w); height: var(--h); overflow: hidden; font-family: Jua, sans-serif; background: #1f6b3d; position: relative; }
.hill { position: absolute; border-radius: 50%; background: #1b5e36; }
h1 { position: absolute; left: 0; right: 0; text-align: center; color: #ccffcc; white-space: pre-line; line-height: 1.12; letter-spacing: 0.01em; }
.device { position: absolute; background: #111; box-shadow: 0 30px 80px rgba(0,0,0,0.35); }
.device img { position: absolute; display: block; }
.status { position: absolute; display: flex; justify-content: space-between; align-items: center; font-family: Roboto, "Segoe UI", sans-serif; color: #1a1f1c; }
.note { position: absolute; color: #ccffcc; white-space: pre-line; text-align: center; line-height: 1.12; transform: translateY(-50%); }
svg.arrows { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; overflow: visible; }
svg.arrows path { fill: none; stroke: #ccffcc; stroke-linecap: round; stroke-linejoin: round; }
`;

function page({ w, h, shot, marks, headline, notes: given, kind }) {
  // Where the device goes, and the screen inside it.
  let dev;
  const phone = kind === 'phone' || kind.startsWith('tablet');
  if (phone) {
    const screenH = kind === 'phone' ? 1960 : kind === 'tablet7' ? 1760 : 1620;
    const ratio = kind === 'phone' ? 1236 / 2676 : kind === 'tablet7' ? 1200 / 2048 : 1600 / 2560;
    const screenW = Math.round(screenH * ratio);
    const bezel = kind === 'phone' ? 26 : 34;
    dev = { x: (w - screenW) / 2 - bezel, y: 640, w: screenW + bezel * 2, h: screenH + bezel * 2, bezel, radius: kind === 'phone' ? 110 : 70, screenW, screenH };
  } else {
    const screenW = 2160, screenH = 1350;
    dev = { x: (w - screenW) / 2 - 3, y: 230, w: screenW + 6, h: screenH + 6, bezel: 3, radius: 22, screenW, screenH };
  }
  const notes = given.map((n) => {
    let tx = n.tx ?? 0.5, ty = n.ty ?? 0.5;
    const r = n.to && marks[n.to];
    if (r) {
      const [l, t, rr, b] = r;
      tx = n.at === 'l' ? l + 0.02 : n.at === 'r' ? rr - 0.02 : (l + rr) / 2;
      ty = t + (b - t) * (n.fy ?? 0.5);
    }
    const py = (dev.y + dev.bezel + ty * dev.screenH) / h;
    const y = Math.min(0.92, Math.max(0.3, n.y ?? py + (n.dy ?? 0)));
    return { ...n, tx, ty, y, x: n.side === 'r' ? 0.9 : 0.1 };
  });
  const head = phone ? { top: 120, size: kind === 'phone' ? 190 : 180 } : { top: 40, size: 140 };
  const noteSize = kind === 'phone' ? 70 : phone ? 58 : 66;
  // Notes sit in the margins beside the device, anchored to their side, never off the picture.
  const gutter = phone ? dev.x + 24 : dev.x - 30;
  const status = phone
    ? `<div class="status" style="left:${dev.x + dev.bezel + 70}px; top:${dev.y + dev.bezel + 22}px; width:${dev.screenW - 140}px; font-size:${kind === 'phone' ? 42 : 34}px">
        <span>9:41</span><span>▾ ◢ ▮</span></div>`
    : '';
  return `<!doctype html><html><head><style>${css}</style></head>
  <body style="--w:${w}px; --h:${h}px">
    <div class="hill" style="left:${-w * 0.3}px; top:${h * 0.55}px; width:${w * 1.1}px; height:${h * 0.9}px"></div>
    <div class="hill" style="left:${w * 0.45}px; top:${h * 0.7}px; width:${w}px; height:${h}px; background:#195632"></div>
    <h1 style="top:${head.top}px; font-size:${head.size}px">${headline}</h1>
    <div class="device" style="left:${dev.x}px; top:${dev.y}px; width:${dev.w}px; height:${dev.h}px; border-radius:${dev.radius}px">
      <img src="${shot}" style="left:${dev.bezel}px; top:${dev.bezel}px; width:${dev.screenW}px; height:${dev.screenH}px; border-radius:${Math.max(4, dev.radius - dev.bezel)}px; object-fit:cover; object-position:top">
    </div>
    ${status}
    ${notes.map((n, i) => `<div class="note" id="n${i}" style="${n.x < 0.5 ? 'left' : 'right'}:24px; width:${gutter - 24}px; top:${n.y * h}px; font-size:${noteSize}px">${n.text}</div>`).join('')}
    <svg class="arrows" viewBox="0 0 ${w} ${h}"><defs><filter id="chalk"><feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="5"/></filter></defs><g id="arrows" filter="url(#chalk)"></g></svg>
    <script>
      // A headline that doesn't fit above the device shrinks till it does.
      const h1 = document.querySelector('h1');
      const room = ${phone ? dev.y - head.top - 30 : dev.y - head.top - 16};
      while (h1.getBoundingClientRect().height > room && parseFloat(h1.style.fontSize) > 40) {
        h1.style.fontSize = (parseFloat(h1.style.fontSize) * 0.95) + 'px';
      }
      // A bowed arrow from each note's edge to its spot on the screen, as the page tours draw them.
      const notes = ${JSON.stringify(notes)};
      const dev = ${JSON.stringify(dev)};
      const g = document.getElementById('arrows');
      notes.forEach((n, i) => {
        const r = document.getElementById('n' + i).getBoundingClientRect();
        const tx = dev.x + dev.bezel + n.tx * dev.screenW, ty = dev.y + dev.bezel + n.ty * dev.screenH;
        const cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
        // From the note's side or end nearest the target.
        let sx, sy;
        if (Math.abs(ty - cy) > Math.abs(tx - cx) * 0.8) { sx = cx; sy = ty > cy ? r.bottom + 24 : r.top - 24; }
        else { sx = tx > cx ? r.right + 20 : r.left - 20; sy = cy; }
        const dx = tx - sx, dy = ty - sy, len = Math.hypot(dx, dy);
        const bow = (i % 2 ? -1 : 1) * 0.22;
        const mx = (sx + tx) / 2 - dy * bow, my = (sy + ty) / 2 + dx * bow;
        const ang = Math.atan2(ty - my, tx - mx), head = Math.min(60, len * 0.25);
        const sw = ${phone ? 9 : 7};
        g.insertAdjacentHTML('beforeend',
          '<path stroke-width="' + sw + '" d="M' + sx + ',' + sy + ' Q' + mx + ',' + my + ' ' + tx + ',' + ty + '"/>' +
          '<path stroke-width="' + sw + '" d="M' + (tx + Math.cos(ang + 2.5) * head) + ',' + (ty + Math.sin(ang + 2.5) * head) + ' L' + tx + ',' + ty + ' L' + (tx + Math.cos(ang - 2.5) * head) + ',' + (ty + Math.sin(ang - 2.5) * head) + '"/>');
      });
    </script>
  </body></html>`;
}

const graphic = `<!doctype html><html><head><style>
@font-face { font-family: Jua; src: url("${jua}"); }
* { margin: 0; box-sizing: border-box; }
body { width: 1024px; height: 500px; overflow: hidden; background: #ccffcc; font-family: Jua, sans-serif; position: relative; }
.hill { position: absolute; border-radius: 50%; background: #b8f0bd; }
.logo { position: absolute; left: 70px; top: 70px; width: 360px; height: 360px; border-radius: 80px; box-shadow: 0 18px 40px rgba(31,107,61,0.25); }
h1 { position: absolute; left: 480px; top: 120px; font-size: 92px; color: #1f6b3d; }
.pill { position: absolute; left: 480px; top: 250px; padding: 14px 28px; border-radius: 22px; background: #ffd27a; border: 5px solid #1f6b3d; color: #1f6b3d; font-size: 34px; }
.links { position: absolute; left: 484px; top: 352px; font-size: 26px; color: #2e6b47; letter-spacing: 0.01em; }
</style></head><body>
  <div class="hill" style="left:-200px; top:300px; width:900px; height:500px"></div>
  <div class="hill" style="left:560px; top:330px; width:800px; height:500px; background:#aee8b4"></div>
  <img class="logo" src="${logo}">
  <h1>uwuFix</h1>
  <div class="pill">Clean links. Fix embeds.</div>
  <div class="links">X · Instagram · TikTok · Reddit · and 26 more</div>
</body></html>`;

const browser = await playwright.chromium.launch({ executablePath: process.env.CHROME || undefined });
async function render(html, w, h, out) {
  mkdirSync(dirname(out), { recursive: true });
  const p = await browser.newPage({ viewport: { width: w, height: h } });
  await p.setContent(html, { waitUntil: 'load' });
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(150);
  await p.screenshot({ path: out, omitBackground: false });
  await p.close();
  console.log(out);
}

for (const [kind, folder] of [['phone', 'phone-assets'], ['tablet7', join('tablet-assets', '7-inch')], ['tablet10', join('tablet-assets', '10-inch')]]) {
  for (const [file, shot, headline, notes] of PHONE) {
    const src = `${kind}-${shot}`;
    if (!existsSync(join(shots, `${src}.png`))) continue;
    await render(page({ w: 1620, h: 2880, shot: img(src), marks: marksOf(src), headline, notes, kind }), 1620, 2880, join(docs, folder, `${file}.png`));
  }
}
for (const [file, shot, headline, notes] of DESKTOP) {
  if (!existsSync(join(shots, `${shot}.png`))) continue;
  await render(page({ w: 2880, h: 1620, shot: img(shot), marks: marksOf(shot), headline, notes, kind: 'desktop' }), 2880, 1620, join(docs, 'desktop-assets', `${file}.png`));
}
await render(graphic, 1024, 500, join(docs, 'feature-graphic.png'));
await browser.close();
