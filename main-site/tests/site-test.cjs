// The website's page tours and Share history, in Chromium under Playwright. No server: the page is
// served from main-site/ by Playwright itself, with /api/resolve answered empty and Google's
// analytics left unloaded. PeerJS and its broker are the real ones (0.peerjs.com), as Share
// history needs.
//
//   node main-site/tests/site-test.cjs
//
// Needs Playwright (PLAYWRIGHT=<path to it>, or a global install) and its Chromium. SHOTS=<folder>
// saves a picture of each tour step.
//
// What it checks:
//   1. The welcome tour comes the first time, on a phone and on a big screen: each step's thing is
//      on screen (scrolled to), lit, and the card, its Next button and the whole arrow are inside
//      the window. Done ends it, and it doesn't come back.
//   2. A link (?url=) never gets a tour. Escape ends one.
//   3. History's tour, the first time History opens, lights its rows (scrolling to them).
//   4. Show me around plays a tour again, and puts you back where you were.
//   5. Share history between two browsers: the guest joins with the host's code, sees its
//      history, adds it to its own; sends its own, which the host is asked about first and adds.
//      Leaving retires the code. The pairing has no TURN server in it.
//   6. Offline, Share history says it needs a connection.
const path = require('path');
const fs = require('fs');

let playwright;
try {
  playwright = require(process.env.PLAYWRIGHT || 'playwright');
} catch {
  try {
    playwright = require('playwright-core');
  } catch {
    playwright = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright'));
  }
}

const SITE = path.resolve(__dirname, '..');
const ORIGIN = 'https://fixup.test';
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.ico': 'image/x-icon', '.svg': 'image/svg+xml' };
const SHOTS = process.env.SHOTS ? path.resolve(process.env.SHOTS) : null;
if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });

let failures = 0;
let passes = 0;
function ok(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ` :: ${extra}` : ''}`);
  if (cond) passes++;
  else failures++;
}

async function serve(context) {
  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (/googletagmanager|google-analytics/.test(url.hostname)) return route.abort();
    if (url.origin !== ORIGIN) return route.continue();
    if (url.pathname.startsWith('/api/')) return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
    let file = path.join(SITE, decodeURIComponent(url.pathname));
    if (url.pathname === '/' || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(SITE, 'index.html');
    return route.fulfill({ status: 200, contentType: TYPES[path.extname(file)] || 'application/octet-stream', body: fs.readFileSync(file) });
  });
}

const HISTORY = [
  { id: 1763100000000, original: 'https://x.com/a/status/1?s=20', cleaned: 'https://fixupx.com/i/status/1', platform: 'X / Twitter', title: 'A post', date: '2026-11-14T05:00:00.000Z' },
  { id: 1763000000000, original: 'https://www.reddit.com/r/a/?share_id=1', cleaned: 'https://www.vxreddit.com/r/a/', platform: 'Reddit', title: null, date: '2026-11-13T01:00:00.000Z' },
];

async function newPage(browser, { viewport, storage = {}, mobile = false } = {}) {
  // No service worker: its own fetches would skip the routes above, to a site that isn't there.
  const context = await browser.newContext({ viewport, isMobile: mobile, hasTouch: mobile, deviceScaleFactor: mobile ? 2 : 1, serviceWorkers: 'block' });
  await serve(context);
  await context.addInitScript((s) => {
    if (sessionStorage.getItem('seeded')) return;
    sessionStorage.setItem('seeded', '1');
    for (const [k, v] of Object.entries(s)) localStorage.setItem(k, v);
  }, storage);
  const page = await context.newPage();
  page.on('pageerror', (e) => ok(`no page error (${e.message})`, false));
  return { context, page };
}

// Checks the step on show: its card, Next, and arrow inside the window, and its lit hole over
// something on screen.
async function checkStep(page, label) {
  const r = await page.evaluate(() => {
    const vw = document.documentElement.clientWidth, vh = innerHeight;
    const box = (el) => { const b = el.getBoundingClientRect(); return { l: b.left, t: b.top, r: b.right, b: b.bottom }; };
    const card = box(document.querySelector('.tourCard'));
    const next = box(document.querySelector('.tourNext'));
    const hole = box(document.querySelector('.tourHole'));
    const d = document.querySelector('.tourLine').getAttribute('d') || '';
    const nums = (d.match(/-?\d+(\.\d+)?/g) || []).map(Number);
    const head = (document.querySelector('.tourHead').getAttribute('d') || '').match(/-?\d+(\.\d+)?/g)?.map(Number) || [];
    const pts = [...nums, ...head];
    const xs = pts.filter((_, i) => i % 2 === 0), ys = pts.filter((_, i) => i % 2 === 1);
    return {
      vw, vh, card, next, hole,
      text: document.querySelector('.tourText').textContent,
      arrowIn: xs.every((x) => x >= 0 && x <= vw) && ys.every((y) => y >= 0 && y <= vh),
      arrow: pts.length > 0,
      solid: document.querySelector('.tourCard').classList.contains('solid'),
      bodyLocked: getComputedStyle(document.body).overflow === 'hidden',
    };
  });
  const inside = (b) => b.l >= -0.5 && b.t >= -0.5 && b.r <= r.vw + 0.5 && b.b <= r.vh + 0.5;
  ok(`${label}: card on screen`, inside(r.card), JSON.stringify(r.card));
  ok(`${label}: Next on screen`, inside(r.next), JSON.stringify(r.next));
  ok(`${label}: arrow on screen (or none, on a backing)`, r.arrow ? r.arrowIn : r.solid);
  const holeShown = Math.min(r.hole.b, r.vh) - Math.max(r.hole.t, 0) > 10 && Math.min(r.hole.r, r.vw) - Math.max(r.hole.l, 0) > 10;
  ok(`${label}: what it lights is scrolled into view`, holeShown, JSON.stringify(r.hole));
  ok(`${label}: the page under it doesn't scroll`, r.bodyLocked);
  return r;
}

async function runTour(page, name, shotPrefix) {
  await page.waitForSelector('.tour .tourCard', { timeout: 8000 });
  await page.waitForTimeout(450);
  const texts = [];
  for (let i = 0; i < 10; i++) {
    const r = await checkStep(page, `${name} step ${i + 1}`);
    texts.push(r.text);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `${shotPrefix}-${i + 1}.png`) });
    const label = await page.textContent('.tourNext');
    await page.click('.tourNext');
    await page.waitForTimeout(400);
    if (label === 'Done') break;
  }
  return texts;
}

(async () => {
  const browser = await playwright.chromium.launch({ executablePath: process.env.CHROME || undefined });

  // 1. The welcome, on a phone and a big screen.
  for (const [name, viewport, mobile] of [['phone', { width: 360, height: 740 }, true], ['desktop', { width: 1280, height: 800 }, false]]) {
    const { context, page } = await newPage(browser, { viewport, mobile });
    await page.goto(`${ORIGIN}/`);
    // A result first, so the step on its buttons is there, low on a phone.
    await page.fill('#urlInput', 'https://x.com/someone/status/42?s=20&t=abc');
    const texts = await runTour(page, `welcome (${name})`, `welcome-${name}`);
    ok(`welcome (${name}) has 4 or 5 steps`, texts.length >= 4 && texts.length <= 5, texts.length);
    ok(`welcome (${name}) ends`, (await page.$('.tour')) === null);
    ok(`welcome (${name}) is kept as seen`, (await page.evaluate(() => localStorage.getItem('tour.welcome'))) === 'done');
    await page.reload();
    await page.waitForTimeout(2500);
    ok(`welcome (${name}) doesn't come back`, (await page.$('.tour')) === null);
    await context.close();
  }

  // 2. A link never gets a tour; Escape ends one.
  {
    const { context, page } = await newPage(browser, { viewport: { width: 400, height: 800 } });
    await page.goto(`${ORIGIN}/?url=${encodeURIComponent('https://x.com/a/status/1?s=1')}`);
    await page.waitForTimeout(3000);
    ok('a link opens with no tour', (await page.$('.tour')) === null);
    ok('the link is cleaned', (await page.textContent('#resultUrl')) === 'https://fixupx.com/i/status/1');
    await page.goto(`${ORIGIN}/`);
    await page.waitForSelector('.tour .tourCard', { timeout: 8000 });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    ok('Escape ends a tour', (await page.$('.tour')) === null);
    await context.close();
  }

  // 3. History's tour, the first time History opens, over a long history on a short phone.
  {
    const long = Array.from({ length: 12 }, (_, i) => ({ ...HISTORY[i % 2], id: 1763000000000 + i, cleaned: `${HISTORY[i % 2].cleaned}?n=${i}` }));
    const { context, page } = await newPage(browser, { viewport: { width: 360, height: 640 }, mobile: true, storage: { 'tour.welcome': 'done', uwufix_history: JSON.stringify(long) } });
    await page.goto(`${ORIGIN}/`);
    await page.click('#openHistoryModal');
    const texts = await runTour(page, 'history', 'history');
    ok('history tour covers the rows, delete, Share and Clear All', texts.length === 4, texts.length);
    ok('history tour ends in History', !(await page.$eval('#historyModal', (m) => m.classList.contains('hidden'))));
    await context.close();
  }

  // 4. Show me around plays one again, and comes back.
  {
    const { context, page } = await newPage(browser, { viewport: { width: 1280, height: 800 }, storage: { 'tour.welcome': 'done', 'tour.pages': '["history","sync"]' } });
    await page.goto(`${ORIGIN}/`);
    await page.waitForTimeout(1500);
    ok('no tour once all are seen', (await page.$('.tour')) === null);
    await page.click('#tourBtn');
    const picks = await page.$$eval('#tourPicks [data-tour]', (b) => b.map((x) => x.dataset.tour));
    ok('Show me around has every page', ['home', 'history', 'sync'].every((p) => picks.includes(p)), picks.join(','));
    await page.click('#tourPicks [data-tour="history"]');
    await runTour(page, 'history replay', 'history-replay');
    await page.waitForTimeout(700);
    ok('the replay goes back to the page it began on', await page.$eval('#historyModal', (m) => m.classList.contains('hidden')));
    await context.close();
  }

  // 5. Share history between two browsers.
  {
    const seen = { 'tour.welcome': 'done', 'tour.pages': '["history","sync"]' };
    const host = await newPage(browser, { viewport: { width: 1000, height: 900 }, storage: { ...seen, uwufix_history: JSON.stringify(HISTORY) } });
    const guestHistory = [{ id: 1762000000000, original: 'https://open.spotify.com/track/x?si=1', cleaned: 'https://fxspotify.com/track/x', platform: 'Spotify', title: 'A song', date: '2026-11-10T10:00:00.000Z' }];
    const guest = await newPage(browser, { viewport: { width: 420, height: 900 }, mobile: true, storage: { ...seen, uwufix_history: JSON.stringify(guestHistory) } });

    await host.page.goto(`${ORIGIN}/`);
    await host.page.click('#openHistoryModal');
    await host.page.click('#openSyncBtn');
    await host.page.waitForFunction(() => /^[A-Z0-9]{6}$/.test(document.getElementById('syncCode').textContent), null, { timeout: 20000 });
    const code = await host.page.textContent('#syncCode');
    ok('the host shows a six-letter code', /^[BCDFGHJKLMNPQRSTVWXYZ2-9]{6}$/.test(code), code);
    ok('the host shows its QR code', (await host.page.$('#syncQr img, #syncQr canvas')) !== null);
    const qr = await host.page.$eval('#syncQr', (q) => { const b = q.getBoundingClientRect(); const m = q.closest('.modal').getBoundingClientRect(); return Math.abs((b.left + b.right) / 2 - (m.left + m.right) / 2); });
    ok('the QR code is centred', qr < 3, qr);
    await host.page.waitForFunction(() => /On the other device/.test(document.getElementById('syncHostStatus').textContent), null, { timeout: 20000 });

    // The guest follows the join link.
    await guest.page.goto(`${ORIGIN}/join?id=${code}`);
    await guest.page.waitForFunction(() => !document.getElementById('syncModal').classList.contains('hidden'), null, { timeout: 5000 });
    ok('the join link fills the code in', (await guest.page.inputValue('#syncCodeInput')) === code);
    ok('the join link has no tour', (await guest.page.$('.tour')) === null);
    await guest.page.click('#syncJoin');
    await guest.page.waitForFunction(() => !document.getElementById('syncTheirs').hidden, null, { timeout: 30000 });
    const theirs = await guest.page.textContent('#syncTheirsText');
    ok('the guest sees the host’s history', /Their history has 2 links, 2 new/.test(theirs), theirs);
    await host.page.waitForFunction(() => /Connected to/.test(document.getElementById('syncHostStatus').textContent), null, { timeout: 10000 });
    ok('the host names the guest', /Connected to Chrome/.test(await host.page.textContent('#syncHostStatus')));

    await guest.page.click('#syncTake');
    await guest.page.waitForTimeout(400);
    const gh = await guest.page.evaluate(() => JSON.parse(localStorage.getItem('uwufix_history')).map((e) => e.cleaned));
    ok('Add theirs to mine merges them in', gh.length === 3 && gh.includes('https://fixupx.com/i/status/1'), gh.join(' '));
    ok('the guest’s badge counts them', (await guest.page.textContent('#historyCountBadge')).trim() === '3');
    await host.page.waitForFunction(() => /added 2 of your links/.test(document.getElementById('syncHostNote').textContent), null, { timeout: 5000 });
    ok('the host hears they were taken', true);

    await guest.page.click('#syncSend');
    await host.page.waitForFunction(() => !document.getElementById('syncApprove').hidden, null, { timeout: 5000 });
    ok('the host is asked first', /Add 1 link from Chrome/.test(await host.page.textContent('#syncApproveText')));
    const before = await host.page.evaluate(() => JSON.parse(localStorage.getItem('uwufix_history')).length);
    ok('nothing is added before the host says yes', before === 2);
    await host.page.click('#syncApproveYes');
    await host.page.waitForTimeout(400);
    const hh = await host.page.evaluate(() => JSON.parse(localStorage.getItem('uwufix_history')).map((e) => e.cleaned));
    ok('the host adds the guest’s link', hh.length === 3 && hh.includes('https://fxspotify.com/track/x'), hh.join(' '));
    await guest.page.waitForFunction(() => /added 1 of your links/.test(document.getElementById('syncGuestNote').textContent), null, { timeout: 5000 });
    ok('the guest hears it was added', true);

    // Malformed messages from a guest are ignored (spec: validate everything).
    const hostOk = await host.page.evaluate(() => typeof window.HistoryMerge.merge([], [null, 1, 'x', { cleaned: 'javascript:1', date: '2026-01-01' }]).items.length === 'number');
    ok('junk entries are dropped, not thrown on', hostOk);

    // Leaving retires the code.
    await guest.page.click('#syncLeave');
    await host.page.waitForFunction((c) => document.getElementById('syncCode').textContent !== c && /^[A-Z0-9]{6}$/.test(document.getElementById('syncCode').textContent), code, { timeout: 20000 });
    ok('leaving on purpose retires the host’s code', true);

    // The page's own copy of PeerJS's options: STUN only.
    const p2p = fs.readFileSync(path.join(SITE, 'js', 'p2p.js'), 'utf8');
    ok('no TURN server anywhere in the pairing', !/turns?:/.test(p2p.replace(/\/\/.*$|\/\*[\s\S]*?\*\//gm, '')));
    await host.context.close();
    await guest.context.close();
  }

  // 6. Offline.
  {
    const { context, page } = await newPage(browser, { viewport: { width: 400, height: 800 }, storage: { 'tour.welcome': 'done', 'tour.pages': '["history","sync"]' } });
    await page.goto(`${ORIGIN}/`);
    await context.setOffline(true);
    await page.evaluate(() => window.HistorySync.open());
    await page.waitForTimeout(500);
    ok('offline, Share history says it needs a connection', /needs a connection/.test(await page.textContent('#syncHostStatus')));
    await context.close();
  }

  // 7. Report a bug: the form, Screenshot this page (the whole page), and the report's ID.
  {
    const { context, page } = await newPage(browser, { viewport: { width: 400, height: 760 }, storage: { 'tour.welcome': 'done', 'tour.pages': '["history","sync"]', uwufix_history: JSON.stringify(HISTORY) } });
    let sent = null;
    await context.route(`${ORIGIN}/api/bug-report`, (route) => {
      sent = route.request().postDataJSON();
      return route.fulfill({ status: 200, contentType: 'application/json', body: '{"id":"20261114-K7QM"}' });
    });
    await page.goto(`${ORIGIN}/`);
    ok('the Edge Tray has Report a bug', (await page.$('#bugBtn')) !== null);
    await page.evaluate(() => window.BugReport.open());
    await page.waitForFunction(() => !document.getElementById('bugModal').classList.contains('hidden'));
    ok('it says what’s sent with it', /uwuFix|web|site/i.test(await page.textContent('#bugDetails')), await page.textContent('#bugDetails'));
    await page.click('#bugSend');
    ok('an empty report isn’t sent', sent === null && /what went wrong/i.test(await page.textContent('#bugStatus')));
    await page.click('#bugScreenshot');
    await page.waitForFunction(() => document.querySelectorAll('#bugShots .bugShot').length === 1, null, { timeout: 20000 });
    ok('Screenshot this page adds a picture', true);
    await page.fill('#bugText', 'The Fix button does nothing on this link.');
    await page.fill('#bugContact', '@someone');
    await page.click('#bugSend');
    await page.waitForFunction(() => /20261114-K7QM/.test(document.getElementById('bugStatus').textContent), null, { timeout: 10000 });
    ok('it says the report’s ID', true);
    ok('the report carries its text, contact and picture', sent && sent.text.startsWith('The Fix button') && sent.contact === '@someone' && sent.images.length === 1 && /^data:image\/jpeg/.test(sent.images[0]));
    ok('the honeypot is empty', sent && sent.website === '');
    ok('the form is emptied after', (await page.inputValue('#bugText')) === '' && (await page.$$('#bugShots .bugShot')).length === 0);
    await page.keyboard.press('Escape');
    ok('Escape closes it', await page.$eval('#bugModal', (m) => m.classList.contains('hidden')));
    await context.close();
  }

  // The server's report ID: the day in Singapore, then four letters.
  {
    const api = await import(require('url').pathToFileURL(path.join(SITE, 'api', 'bug-report.js')).href);
    const id = api.reportId(new Date('2026-11-14T17:30:00Z'));
    ok('the report ID is the day in Singapore and four letters', /^20261115-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{4}$/.test(id), id);
  }

  await browser.close();
  console.log(`\n${passes} passed, ${failures} failed`);
  process.exit(failures ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
