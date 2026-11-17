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
let playwrightPath = 'playwright';
if (process.env.PLAYWRIGHT) {
  playwrightPath = process.env.PLAYWRIGHT;
}
try {
  playwright = require(playwrightPath);
} catch {
  playwright = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
}

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const docs = join(root, '..', 'docs');
const shots = join(root, 'build', 'shots');
const jua = pathToFileURL(join(root, 'assets', 'fonts', 'Jua-Regular.ttf')).href;
const logo = `data:image/png;base64,${readFileSync(join(root, '..', 'main-site', 'UFX-512.png')).toString('base64')}`;

// Where the marked things are on a screen, as the shot test wrote them beside its picture; none if
// it didn't.
function marksOf(name) {
  const marksPath = join(shots, `${name}.json`);
  if (existsSync(marksPath)) {
    return JSON.parse(readFileSync(marksPath, 'utf8'));
  }
  return {};
}

// A screen's picture, as a data URL the page can show.
function shotDataUrl(name) {
  return `data:image/png;base64,${readFileSync(join(shots, `${name}.png`)).toString('base64')}`;
}

// Whether a note gave a value for an optional setting (it's neither missing nor null).
function isGiven(value) {
  return value !== undefined && value !== null;
}

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

// The pictures' colours: deep takes on the app's seven (theme.dart's swatches), each with its pale
// tint for the words. Picture n runs from EDGES[n] on its left to EDGES[n + 1] on its right, so in
// Play's row each one carries on in the colour the last left off with, round the wheel and home to
// green; the night one lands on indigo and midnight.
const EDGES = [
  { background: '#1f6b3d', ink: '#ccffcc' }, // green (Classic)
  { background: '#146b74', ink: '#ccffff' }, // teal (Not green 5)
  { background: '#7a2f86', ink: '#ffccff' }, // plum (Not green 4)
  { background: '#a3304f', ink: '#ffcccc' }, // berry (Not green 1)
  { background: '#a8561a', ink: '#ffffcc' }, // amber (Not green 3)
  { background: '#3b3f9e', ink: '#ccccff' }, // indigo (Not green 2)
  { background: '#1c2357', ink: '#ccccff' }, // midnight
  { background: '#146b74', ink: '#ccffff' }, // teal
  { background: '#1f6b3d', ink: '#ccffcc' }, // green again
];
const SWATCHES = ['#ccffcc', '#ffcccc', '#ccccff', '#ffffcc', '#ffccff', '#ccffff'];

// Picture number `index`'s colours: its left edge's and its right edge's.
function palette(index) {
  return {
    startBackground: EDGES[index].background,
    endBackground: EDGES[index + 1].background,
    startInk: EDGES[index].ink,
    endInk: EDGES[index + 1].ink,
    index,
  };
}

const css = `
@font-face { font-family: Jua; src: url("${jua}"); }
* { margin: 0; box-sizing: border-box; }
body { width: var(--w); height: var(--h); overflow: hidden; font-family: Jua, sans-serif; position: relative;
  background:
    radial-gradient(ellipse at 12% 8%, rgba(255,255,255,0.14), transparent 45%),
    radial-gradient(ellipse at 90% 45%, rgba(255,255,255,0.08), transparent 40%),
    linear-gradient(115deg, var(--a) 15%, var(--b) 85%); }
.hill { position: absolute; border-radius: 50%; background: rgba(0,0,0,0.13); }
.dot { position: absolute; border-radius: 50%; }
h1 { position: absolute; left: 0; right: 0; text-align: center; white-space: pre-line; line-height: 1.12; letter-spacing: 0.01em; }
h1 span { background: linear-gradient(90deg, var(--inkA), var(--inkB)); -webkit-background-clip: text; background-clip: text; color: transparent; }
.device { position: absolute; background: #111; box-shadow: 0 30px 80px rgba(0,0,0,0.35); }
.device img { position: absolute; display: block; }
.status { position: absolute; display: flex; justify-content: space-between; align-items: center; font-family: Roboto, "Segoe UI", sans-serif; color: #1a1f1c; }
.note { position: absolute; white-space: pre-line; text-align: center; line-height: 1.12; transform: translateY(-50%); }
svg.arrows { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; overflow: visible; }
svg.arrows path { fill: none; stroke-linecap: round; stroke-linejoin: round; }
`;

// A scatter of soft dots in the swatches' tints, the same for a picture each time it's drawn, kept
// clear of the words and the device (`avoid`: [left, top, right, bottom] boxes).
function dots(width, height, seed, avoid) {
  let randomState = seed * 9301 + 49297;
  // The next of a repeatable run of numbers from 0 up to 1, so a picture's dots never move.
  function random() {
    randomState = (randomState * 9301 + 49297) % 233280;
    return randomState / 233280;
  }
  const unit = Math.min(width, height);
  const dotElements = [];
  for (let tries = 0; tries < 200 && dotElements.length < 12; tries++) {
    const diameter = unit * (0.012 + random() * 0.035);
    const centerX = random() * width;
    const centerY = random() * height;
    const isRing = random() < 0.4;
    const colour = SWATCHES[Math.floor(random() * SWATCHES.length)];
    const opacity = 0.18 + random() * 0.2;
    const radius = diameter / 2;
    let overlapsAvoidedBox = false;
    for (const [boxLeft, boxTop, boxRight, boxBottom] of avoid) {
      if (
        centerX + radius > boxLeft &&
        centerX - radius < boxRight &&
        centerY + radius > boxTop &&
        centerY - radius < boxBottom
      ) {
        overlapsAvoidedBox = true;
        break;
      }
    }
    if (overlapsAvoidedBox) {
      continue;
    }
    let fill;
    if (isRing) {
      fill = `border:${Math.max(4, diameter * 0.18)}px solid ${colour}`;
    } else {
      fill = `background:${colour}`;
    }
    dotElements.push(`<div class="dot" style="left:${centerX - radius}px; top:${centerY - radius}px; width:${diameter}px; height:${diameter}px; opacity:${opacity}; ${fill}"></div>`);
  }
  return dotElements.join('');
}

/**
 * One picture's page: the backdrop and its dots, the headline, the device with the screen in it,
 * the notes in the margins beside it, and a script that shrinks the headline to fit and draws each
 * note's chalk arrow once the page has laid out. `kind` is 'phone', 'tablet7', 'tablet10' or
 * 'desktop'; `colours` comes from palette().
 */
function page({ width, height, shot, marks, headline, notes: givenNotes, kind, colours }) {
  // Where the device goes, and the screen inside it. Phones and tablets stand upright.
  let device;
  const isHandheld = kind === 'phone' || kind.startsWith('tablet');
  if (isHandheld) {
    let screenHeight;
    let ratio;
    if (kind === 'phone') {
      screenHeight = 1960;
      ratio = 1236 / 2676;
    } else if (kind === 'tablet7') {
      screenHeight = 1760;
      ratio = 1200 / 2048;
    } else {
      screenHeight = 1620;
      ratio = 1600 / 2560;
    }
    const screenWidth = Math.round(screenHeight * ratio);
    let bezel = 34;
    let radius = 70;
    if (kind === 'phone') {
      bezel = 26;
      radius = 110;
    }
    device = {
      x: (width - screenWidth) / 2 - bezel,
      y: 640,
      w: screenWidth + bezel * 2,
      h: screenHeight + bezel * 2,
      bezel,
      radius,
      screenW: screenWidth,
      screenH: screenHeight,
    };
  } else {
    const screenWidth = 2160;
    const screenHeight = 1350;
    device = {
      x: (width - screenWidth) / 2 - 3,
      y: 230,
      w: screenWidth + 6,
      h: screenHeight + 6,
      bezel: 3,
      radius: 22,
      screenW: screenWidth,
      screenH: screenHeight,
    };
  }

  // Each note's target on the screen (`tx`, `ty`, fractions of the screen) and its own place
  // (`x`, `y`, fractions of the picture), and its colour.
  const notes = [];
  for (const note of givenNotes) {
    let targetX = 0.5;
    if (isGiven(note.tx)) {
      targetX = note.tx;
    }
    let targetY = 0.5;
    if (isGiven(note.ty)) {
      targetY = note.ty;
    }
    let markedBox = null;
    if (note.to) {
      markedBox = marks[note.to];
    }
    if (markedBox) {
      const [boxLeft, boxTop, boxRight, boxBottom] = markedBox;
      if (note.at === 'l') {
        targetX = boxLeft + 0.02;
      } else if (note.at === 'r') {
        targetX = boxRight - 0.02;
      } else {
        targetX = (boxLeft + boxRight) / 2;
      }
      let fractionDown = 0.5;
      if (isGiven(note.fy)) {
        fractionDown = note.fy;
      }
      targetY = boxTop + (boxBottom - boxTop) * fractionDown;
    }
    const targetPictureY = (device.y + device.bezel + targetY * device.screenH) / height;
    let noteY;
    if (isGiven(note.y)) {
      noteY = note.y;
    } else {
      let lower = 0;
      if (isGiven(note.dy)) {
        lower = note.dy;
      }
      noteY = targetPictureY + lower;
    }
    noteY = Math.min(0.92, Math.max(0.3, noteY));
    let noteX = 0.1;
    let ink = colours.startInk;
    if (note.side === 'r') {
      noteX = 0.9;
      ink = colours.endInk;
    }
    notes.push({ ...note, tx: targetX, ty: targetY, y: noteY, x: noteX, ink });
  }

  let headlineTop;
  let headlineSize;
  let noteSize;
  // Notes sit in the margins beside the device, anchored to their side, never off the picture.
  let gutter;
  let headlineRoom;
  let arrowStrokeWidth;
  let status = '';
  if (isHandheld) {
    headlineTop = 120;
    if (kind === 'phone') {
      headlineSize = 190;
      noteSize = 70;
    } else {
      headlineSize = 180;
      noteSize = 58;
    }
    gutter = device.x + 24;
    headlineRoom = device.y - headlineTop - 30;
    arrowStrokeWidth = 9;
    let statusFontSize = 34;
    if (kind === 'phone') {
      statusFontSize = 42;
    }
    status = `<div class="status" style="left:${device.x + device.bezel + 70}px; top:${device.y + device.bezel + 22}px; width:${device.screenW - 140}px; font-size:${statusFontSize}px">
        <span>9:41</span><span>▾ ◢ ▮</span></div>`;
  } else {
    headlineTop = 40;
    headlineSize = 140;
    noteSize = 66;
    gutter = device.x - 30;
    headlineRoom = device.y - headlineTop - 16;
    arrowStrokeWidth = 7;
  }

  // The dots keep clear of the headline, the device and each note.
  const avoidBoxes = [
    [0, 0, width, device.y - 10],
    [device.x - 20, device.y - 20, device.x + device.w + 20, device.y + device.h + 20],
  ];
  for (const note of notes) {
    const noteTop = note.y * height - 0.1 * height;
    const noteBottom = note.y * height + 0.1 * height;
    if (note.x < 0.5) {
      avoidBoxes.push([0, noteTop, device.x, noteBottom]);
    } else {
      avoidBoxes.push([device.x + device.w, noteTop, width, noteBottom]);
    }
  }
  const dotsHtml = dots(width, height, colours.index + 1, avoidBoxes);

  let notesHtml = '';
  for (let noteIndex = 0; noteIndex < notes.length; noteIndex++) {
    const note = notes[noteIndex];
    let anchorSide = 'right';
    if (note.x < 0.5) {
      anchorSide = 'left';
    }
    notesHtml += `<div class="note" id="n${noteIndex}" style="${anchorSide}:24px; width:${gutter - 24}px; top:${note.y * height}px; font-size:${noteSize}px; color:${note.ink}">${note.text}</div>`;
  }

  return `<!doctype html><html><head><style>${css}</style></head>
  <body style="--w:${width}px; --h:${height}px; --a:${colours.startBackground}; --b:${colours.endBackground}; --inkA:${colours.startInk}; --inkB:${colours.endInk}">
    <div class="hill" style="left:${-width * 0.3}px; top:${height * 0.55}px; width:${width * 1.1}px; height:${height * 0.9}px"></div>
    <div class="hill" style="left:${width * 0.45}px; top:${height * 0.7}px; width:${width}px; height:${height}px; background:rgba(0,0,0,0.2)"></div>
    ${dotsHtml}
    <h1 style="top:${headlineTop}px; font-size:${headlineSize}px"><span>${headline}</span></h1>
    <div class="device" style="left:${device.x}px; top:${device.y}px; width:${device.w}px; height:${device.h}px; border-radius:${device.radius}px">
      <img src="${shot}" style="left:${device.bezel}px; top:${device.bezel}px; width:${device.screenW}px; height:${device.screenH}px; border-radius:${Math.max(4, device.radius - device.bezel)}px; object-fit:cover; object-position:top">
    </div>
    ${status}
    ${notesHtml}
    <svg class="arrows" viewBox="0 0 ${width} ${height}"><defs><filter id="chalk"><feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="5"/></filter></defs><g id="arrows" filter="url(#chalk)"></g></svg>
    <script>
      // A headline that doesn't fit above the device shrinks till it does.
      const headlineElement = document.querySelector('h1');
      const room = ${headlineRoom};
      while (headlineElement.getBoundingClientRect().height > room && parseFloat(headlineElement.style.fontSize) > 40) {
        headlineElement.style.fontSize = (parseFloat(headlineElement.style.fontSize) * 0.95) + 'px';
      }
      // A bowed arrow from each note's edge to its spot on the screen, as the page tours draw them.
      const notes = ${JSON.stringify(notes)};
      const device = ${JSON.stringify(device)};
      const arrowGroup = document.getElementById('arrows');
      for (let noteIndex = 0; noteIndex < notes.length; noteIndex++) {
        const note = notes[noteIndex];
        const noteBox = document.getElementById('n' + noteIndex).getBoundingClientRect();
        const targetX = device.x + device.bezel + note.tx * device.screenW;
        const targetY = device.y + device.bezel + note.ty * device.screenH;
        const noteCenterX = (noteBox.left + noteBox.right) / 2;
        const noteCenterY = (noteBox.top + noteBox.bottom) / 2;
        // From the note's side or end nearest the target.
        let startX;
        let startY;
        if (Math.abs(targetY - noteCenterY) > Math.abs(targetX - noteCenterX) * 0.8) {
          startX = noteCenterX;
          if (targetY > noteCenterY) {
            startY = noteBox.bottom + 24;
          } else {
            startY = noteBox.top - 24;
          }
        } else {
          if (targetX > noteCenterX) {
            startX = noteBox.right + 20;
          } else {
            startX = noteBox.left - 20;
          }
          startY = noteCenterY;
        }
        const deltaX = targetX - startX;
        const deltaY = targetY - startY;
        const length = Math.hypot(deltaX, deltaY);
        // Every other arrow bows the other way.
        let bowDirection = 1;
        if (noteIndex % 2) {
          bowDirection = -1;
        }
        const bow = bowDirection * 0.22;
        const controlX = (startX + targetX) / 2 - deltaY * bow;
        const controlY = (startY + targetY) / 2 + deltaX * bow;
        const angle = Math.atan2(targetY - controlY, targetX - controlX);
        const headLength = Math.min(60, length * 0.25);
        const strokeWidth = ${arrowStrokeWidth};
        const inkStyle = 'style="stroke:' + note.ink + '" ';
        arrowGroup.insertAdjacentHTML('beforeend',
          '<path ' + inkStyle + 'stroke-width="' + strokeWidth + '" d="M' + startX + ',' + startY + ' Q' + controlX + ',' + controlY + ' ' + targetX + ',' + targetY + '"/>' +
          '<path ' + inkStyle + 'stroke-width="' + strokeWidth + '" d="M' + (targetX + Math.cos(angle + 2.5) * headLength) + ',' + (targetY + Math.sin(angle + 2.5) * headLength) + ' L' + targetX + ',' + targetY + ' L' + (targetX + Math.cos(angle - 2.5) * headLength) + ',' + (targetY + Math.sin(angle - 2.5) * headLength) + '"/>');
      }
    </script>
  </body></html>`;
}

const graphic = `<!doctype html><html><head><style>
@font-face { font-family: Jua; src: url("${jua}"); }
* { margin: 0; box-sizing: border-box; }
body { width: 1024px; height: 500px; overflow: hidden; font-family: Jua, sans-serif; position: relative;
  background: radial-gradient(ellipse at 30% 30%, rgba(255,255,255,0.6), transparent 50%), linear-gradient(110deg, #ccffcc 0%, #ccffff 45%, #dcd6ff 80%, #ffd6f5 100%); }
.hill { position: absolute; border-radius: 50%; background: #ffd9d0; }
.dot { position: absolute; border-radius: 50%; }
.logo { position: absolute; left: 70px; top: 70px; width: 360px; height: 360px; border-radius: 80px; box-shadow: 0 18px 40px rgba(31,107,61,0.25); }
h1 { position: absolute; left: 480px; top: 120px; font-size: 92px; color: #1f6b3d; }
.pill { position: absolute; left: 480px; top: 250px; padding: 14px 28px; border-radius: 22px; background: #ffd27a; border: 5px solid #1f6b3d; color: #1f6b3d; font-size: 34px; }
.links { position: absolute; left: 484px; top: 352px; font-size: 26px; color: #2e6b47; letter-spacing: 0.01em; }
</style></head><body>
  <div class="hill" style="left:-200px; top:300px; width:900px; height:500px"></div>
  <div class="hill" style="left:560px; top:330px; width:800px; height:500px; background:#fff3b8"></div>
  <div class="dot" style="left:445px; top:40px; width:26px; height:26px; background:#ffb3c7"></div>
  <div class="dot" style="left:900px; top:60px; width:44px; height:44px; border:7px solid #b3b8ff"></div>
  <div class="dot" style="left:960px; top:200px; width:18px; height:18px; background:#ffd27a"></div>
  <div class="dot" style="left:30px; top:28px; width:20px; height:20px; background:#9fe8c0"></div>
  <div class="dot" style="left:840px; top:150px; width:16px; height:16px; background:#f0a8ff"></div>
  <img class="logo" src="${logo}">
  <h1>uwuFix</h1>
  <div class="pill">Clean links. Fix embeds.</div>
  <div class="links">X · Instagram · TikTok · Reddit · and 26 more</div>
</body></html>`;

let chromePath;
if (process.env.CHROME) {
  chromePath = process.env.CHROME;
}
const browser = await playwright.chromium.launch({ executablePath: chromePath });

// Draws the HTML in a browser page of the given size, once its fonts have loaded, and saves it as
// a PNG at outputPath.
async function render(html, width, height, outputPath) {
  mkdirSync(dirname(outputPath), { recursive: true });
  const browserPage = await browser.newPage({ viewport: { width, height } });
  await browserPage.setContent(html, { waitUntil: 'load' });
  await browserPage.evaluate(function () {
    return document.fonts.ready;
  });
  await browserPage.waitForTimeout(150);
  await browserPage.screenshot({ path: outputPath, omitBackground: false });
  await browserPage.close();
  console.log(outputPath);
}

const HANDHELD_KINDS = [
  ['phone', 'phone-assets'],
  ['tablet7', join('tablet-assets', '7-inch')],
  ['tablet10', join('tablet-assets', '10-inch')],
];
for (const [kind, folder] of HANDHELD_KINDS) {
  for (const [pictureIndex, [file, shot, headline, notes]] of PHONE.entries()) {
    const shotName = `${kind}-${shot}`;
    if (!existsSync(join(shots, `${shotName}.png`))) {
      continue;
    }
    const html = page({
      width: 1620,
      height: 2880,
      shot: shotDataUrl(shotName),
      marks: marksOf(shotName),
      headline,
      notes,
      kind,
      colours: palette(pictureIndex),
    });
    await render(html, 1620, 2880, join(docs, folder, `${file}.png`));
  }
}
for (const [pictureIndex, [file, shot, headline, notes]] of DESKTOP.entries()) {
  if (!existsSync(join(shots, `${shot}.png`))) {
    continue;
  }
  const html = page({
    width: 2880,
    height: 1620,
    shot: shotDataUrl(shot),
    marks: marksOf(shot),
    headline,
    notes,
    kind: 'desktop',
    colours: palette(pictureIndex),
  });
  await render(html, 2880, 1620, join(docs, 'desktop-assets', `${file}.png`));
}
await render(graphic, 1024, 500, join(docs, 'feature-graphic.png'));
await browser.close();
