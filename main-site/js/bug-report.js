// Report a bug, from the Edge Tray: a small form for what went wrong, and a way to be reached if
// they'd like an answer, sent to Augy on Telegram by api/bug-report.js. As sgbus-timings' own,
// from which it's taken; the apps have the same (flutter/lib/features/bug/).
//
// The form adds what helps find the bug, and says so under the box before it's sent: which app
// and its version (the site's from sw.js; the WebView Android app's own too), the device as the
// browser describes it, the page on show (Home, History or Share history: never a link) and the
// language. Nothing else goes.
//
// What's typed stays while the app's open, closed or not, until it's sent. Offline it waits for
// the connection. If the site can't send it (not set up, or Telegram's down), it offers email
// instead, with the same words filled in.
//
// Pictures, up to MAX_SHOTS: picked from the device (any image), or Screenshot this page, which
// draws the page as it is under its windows (vendor/html-to-image, loaded the first time it's
// used): the whole page, top to bottom,
// not only the part on the screen. Each is made a JPEG of at most SHOT_SIDE pixels a side and
// about SHOT_BYTES here, before it's sent, and kept with what's typed until it's sent. A
// screenshot of a page taller than the screen is kept as tall as it is instead (shrinkPage),
// within what Telegram takes as a photo, and sent marked `full`, so it also reaches Augy as a
// file at its full size (api/bug-report.js).
//
// Once it's sent, the form says the report's ID (api/bug-report.js, reportId), to quote.
//
// Window.BugReport = { open() }. Plain script: exports go on window.
(function () {
  const $ = (sel) => document.querySelector(sel);
  const ID = 'bugModal';
  const EMAIL = 'augy@augystudios.com';
  const MIN_TEXT = 5;
  const VERSION_MS = 1500;

  let siteVersion = null;
  let details = null;
  let sending = false;
  // The pictures to send, as JPEG data URLs, and which of them are whole-page screenshots.
  let shots = [];
  let fullShots = new Set();
  const MAX_SHOTS = 3;
  const SHOT_SIDE = 1600;
  const SHOT_BYTES = 900 * 1024;
  // A whole-page screenshot: at most PAGE_WIDTH wide, and within Telegram's limits for a photo,
  // width and height PAGE_SUM at most together and the height PAGE_RATIO times the width at
  // most (any more is cut off at the bottom). Drawn at most PAGE_DRAW pixels tall, as a browser
  // won't make a canvas much taller.
  const PAGE_WIDTH = 1080;
  const PAGE_SUM = 10000;
  const PAGE_RATIO = 20;
  const PAGE_DRAW = 16000;
  const CAPTURE_LIB = '/vendor/html-to-image-1.11.13/html-to-image.js';

  // The site's version, from the service worker serving it ("v127"), or null without one.
  function askVersion() {
    const sw = navigator.serviceWorker?.controller;
    if (!sw) return Promise.resolve(null);
    return new Promise((resolve) => {
      const channel = new MessageChannel();
      const timer = setTimeout(() => resolve(null), VERSION_MS);
      channel.port1.onmessage = ({ data }) => { clearTimeout(timer); resolve(typeof data === 'string' ? data : null); };
      sw.postMessage({ type: 'version' }, [channel.port2]);
    });
  }

  // Which app this is: the WebView Android app (1.0.x), the site installed, or the site in a
  // browser. (The apps from 1.1.0 send their own reports.)
  function platform() {
    if (window.AppBridge?.native) return 'android';
    if (window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone) return 'pwa';
    return 'web';
  }
  const PLATFORM_NAMES = { web: 'Web', pwa: 'Web, installed', android: 'Android app', desktop: 'Desktop app' };

  // "1.0.1, site uwufix-v46": the app's own version where it has one, then the site's.
  function version() {
    const app = window.AppBridge?.version?.() || '';
    const site = siteVersion ? `site ${siteVersion}` : '';
    return [app, site].filter(Boolean).join(', ');
  }

  // The system and browser, and the window's size: "Android 14 · Chrome 130 · 412×915".
  // Each [pattern, name], the first that matches; a number caught is the version.
  const SYSTEMS = [[/Android ([\d.]+)/, 'Android'], [/(?:iPhone|iPad|iPod).*? OS (\d+)/, 'iOS'], [/Windows NT/, 'Windows'],
    [/CrOS/, 'ChromeOS'], [/Mac OS X/, 'macOS'], [/Linux/, 'Linux']];
  const BROWSERS = [[/SamsungBrowser\/(\d+)/, 'Samsung Internet'], [/Edg\/(\d+)/, 'Edge'], [/Firefox\/(\d+)/, 'Firefox'],
    [/(?:Chrome|CriOS)\/(\d+)/, 'Chrome'], [/Version\/(\d+).*Safari/, 'Safari']];
  function first(list, ua, none) {
    for (const [re, name] of list) {
      const m = re.exec(ua);
      if (m) return m[1] ? `${name} ${m[1]}` : name;
    }
    return none;
  }
  function device() {
    const ua = navigator.userAgent || '';
    return `${first(SYSTEMS, ua, 'Unknown system')} · ${first(BROWSERS, ua, 'Unknown browser')} · ${window.innerWidth}×${window.innerHeight}`;
  }

  // The page on show under this window: Home, History or Share history. Never a link.
  function page() {
    const shown = (id) => !document.getElementById(id)?.classList.contains('hidden');
    if (shown('syncModal')) return 'Share history';
    if (shown('historyModal')) return 'History';
    return 'Home';
  }

  function collect() {
    const p = platform();
    return { version: version(), platform: p, device: device(), page: page(), lang: (navigator.language || 'en').slice(0, 10), platformName: PLATFORM_NAMES[p] };
  }

  // Words with {name} filled in.
  const fill = (text, values) => text.replace(/\{(\w+)\}/g, (m, k) => (k in values ? String(values[k]) : m));

  function say(text, { email = false } = {}) {
    const el = $('#bugStatus');
    el.hidden = !text;
    el.textContent = text || '';
    if (email) {
      const body = `${$('#bugText').value.trim()}\n\n${detailsText()}`;
      const a = document.createElement('a');
      a.href = `mailto:${EMAIL}?subject=${encodeURIComponent('uwuFix bug report')}&body=${encodeURIComponent(body)}`;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      a.textContent = 'Email it instead.';
      el.append(' ', a);
    }
  }

  const detailsText = () => [details.platformName, details.version, details.device, details.page].filter(Boolean).join(' · ');

  function renderDetails() {
    $('#bugDetails').textContent = `${detailsText()}.`;
  }

  async function open() {
    details = collect();
    renderDetails();
    say('');
    window.openModal(ID);
    setTimeout(() => $('#bugText').focus(), 50);
    // The site's version arrives a moment later, the first time.
    if (!siteVersion) {
      siteVersion = await askVersion();
      if (siteVersion && details) { details.version = version(); renderDetails(); }
    }
  }

  // ---------- pictures ----------

  // An image (a File, or a data URL) as a JPEG data URL, at most SHOT_SIDE a side and about
  // SHOT_BYTES, smaller and rougher till it is.
  async function shrink(src) {
    const url = typeof src === 'string' ? src : URL.createObjectURL(src);
    try {
      const img = await new Promise((resolve, reject) => {
        const i = new Image();
        i.onload = () => resolve(i);
        i.onerror = () => reject(new Error('not an image'));
        i.src = url;
      });
      let side = SHOT_SIDE;
      for (let tries = 0; tries < 6; tries++) {
        const k = Math.min(1, side / Math.max(img.naturalWidth, img.naturalHeight));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(img.naturalWidth * k));
        canvas.height = Math.max(1, Math.round(img.naturalHeight * k));
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#fff';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        const out = canvas.toDataURL('image/jpeg', tries < 2 ? 0.82 : 0.7);
        if (out.length * 0.75 <= SHOT_BYTES || tries === 5) return out;
        side = Math.round(side * 0.8);
      }
    } finally {
      if (typeof src !== 'string') URL.revokeObjectURL(url);
    }
    return null;
  }

  // A whole-page screenshot (a data URL) as a JPEG data URL, as tall as the page, within
  // PAGE_WIDTH, PAGE_SUM and PAGE_RATIO and about SHOT_BYTES, smaller and rougher till it is.
  async function shrinkPage(src) {
    const img = await new Promise((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error('not an image'));
      i.src = src;
    });
    const w = img.naturalWidth;
    const h = Math.min(img.naturalHeight, w * PAGE_RATIO);
    let k = Math.min(1, PAGE_WIDTH / w, (PAGE_SUM - 2) / (w + h));
    for (let tries = 0; tries < 8; tries++) {
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.floor(w * k));
      // The height from the rounded-down width, so it stays within PAGE_RATIO.
      canvas.height = Math.max(1, Math.min(Math.floor(h * k), canvas.width * PAGE_RATIO));
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, 0, 0, w, h, 0, 0, canvas.width, canvas.height);
      const out = canvas.toDataURL('image/jpeg', tries < 2 ? 0.8 : 0.68);
      if (out.length * 0.75 <= SHOT_BYTES || tries === 7) return out;
      if (tries >= 1) k *= 0.82;
    }
    return null;
  }

  function renderShots() {
    const box = $('#bugShots');
    box.innerHTML = shots.map((s, i) => `<span class="bugShot"><img src="${s}" alt="${fill('Picture {n}', { n: i + 1 })}"><button type="button" class="bugShotX" data-bug-shot="${i}" aria-label="${fill('Remove picture {n}', { n: i + 1 })}">×</button></span>`).join('');
    box.hidden = !shots.length;
    const full = shots.length >= MAX_SHOTS;
    $('#bugAddPic').disabled = full;
    $('#bugScreenshot').disabled = full;
  }

  async function addShot(src) {
    if (shots.length >= MAX_SHOTS) return;
    try {
      const jpeg = await shrink(src);
      if (jpeg) shots.push(jpeg);
    } catch {
      say("Couldn't add that picture.");
    }
    renderShots();
  }

  // The script that draws the page, the first time it's wanted.
  let lib = null;
  function captureLib() {
    if (window.htmlToImage) return Promise.resolve(window.htmlToImage);
    lib ??= new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = CAPTURE_LIB;
      s.onload = () => (window.htmlToImage ? resolve(window.htmlToImage) : reject(new Error('no htmlToImage')));
      s.onerror = () => { lib = null; reject(new Error('could not load')); };
      document.head.appendChild(s);
    });
    return lib;
  }

  // The page as it is under this window, drawn: the whole page, from the top, however far down
  // it goes.
  async function screenshot() {
    if (shots.length >= MAX_SHOTS) return;
    const btn = $('#bugScreenshot');
    btn.disabled = true;
    say('Taking a screenshot…');
    try {
      const h2i = await captureLib();
      const bg = getComputedStyle(document.body).backgroundColor;
      const width = window.innerWidth;
      const height = Math.max(window.innerHeight, document.scrollingElement?.scrollHeight || 0, document.body.scrollHeight || 0);
      const tall = height > window.innerHeight + 4;
      const url = await h2i.toJpeg(document.body, {
        quality: 0.85,
        pixelRatio: Math.min(2, window.devicePixelRatio || 1, PAGE_DRAW / height),
        width,
        height,
        backgroundColor: bg && bg !== 'rgba(0, 0, 0, 0)' ? bg : '#ffffff',
        cacheBust: false,
        imagePlaceholder: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
        // The page under its windows: this one left out, as it's over it (History and Share
        // history stay, being where the bug may be). And what can't be drawn, which would spoil
        // the whole picture: an image with nothing in it yet.
        filter: (node) => !(node.id === 'bugModal' || (node.classList && (node.classList.contains('tour') || node.classList.contains('toast'))))
          && node.tagName !== 'VIDEO'
          && !(node.tagName === 'IMG' && (!node.currentSrc || !node.complete || !node.naturalWidth)),
      });
      if (tall) {
        const page = await shrinkPage(url);
        if (page && shots.length < MAX_SHOTS) {
          shots.push(page);
          fullShots.add(shots.length - 1);
        }
      } else {
        await addShot(url);
      }
      say('');
    } catch (err) {
      console.warn("couldn't take the screenshot:", err);
      say("Couldn't take a screenshot here. Take one with your phone and add it instead.");
    } finally {
      renderShots();
    }
  }

  async function send(e) {
    e.preventDefault();
    if (sending) return;
    const text = $('#bugText').value.trim();
    if (text.length < MIN_TEXT) {
      say('Please say what went wrong first.');
      $('#bugText').focus();
      return;
    }
    if (navigator.onLine === false) {
      say("You're offline. It's kept here: send it once you're back online.");
      return;
    }
    sending = true;
    $('#bugSend').disabled = true;
    say('Sending…');
    try {
      const { platformName, ...sent } = details;
      const r = await fetch('/api/bug-report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...sent, text, contact: $('#bugContact').value.trim(), website: $('#bugWebsite').value, images: shots, full: [...fullShots] }),
      });
      if (r.ok) {
        $('#bugText').value = '';
        $('#bugContact').value = '';
        shots = [];
        fullShots = new Set();
        renderShots();
        // Its ID, to quote (a site from before IDs answers with none).
        const id = await r.json().then((d) => (typeof d?.id === 'string' ? d.id : null)).catch(() => null);
        say(id ? fill('Sent as report {id}. Thank you! Augy will look into it.', { id }) : 'Sent. Thank you! Augy will look into it.');
        return;
      }
      const err = await r.json().then((d) => d?.error).catch(() => null);
      // Something about what was typed, or too many at once: said as it is. Otherwise, email.
      if (r.status === 400 || r.status === 413 || r.status === 429) say(err || "Couldn't send it right now.");
      else say(r.status === 503 ? "Bug reports can't be sent from the app yet." : "Couldn't send it right now.", { email: true });
    } catch {
      say("Couldn't send it right now.", { email: true });
    } finally {
      sending = false;
      $('#bugSend').disabled = false;
    }
  }

  function init() {
    if (!document.getElementById(ID)) return;
    document.getElementById('bugBtn')?.addEventListener('click', open);
    $('#bugForm').addEventListener('submit', send);
    $('#bugAddPic').addEventListener('click', () => $('#bugPicFile').click());
    $('#bugPicFile').addEventListener('change', async (e) => {
      const files = [...(e.target.files || [])].slice(0, MAX_SHOTS - shots.length);
      e.target.value = '';
      for (const f of files) await addShot(f);
    });
    $('#bugScreenshot').addEventListener('click', screenshot);
    $('#bugShots').addEventListener('click', (e) => {
      const x = e.target.closest('[data-bug-shot]');
      if (!x) return;
      const n = Number(x.dataset.bugShot);
      shots.splice(n, 1);
      fullShots = new Set([...fullShots].filter((i) => i !== n).map((i) => (i > n ? i - 1 : i)));
      renderShots();
    });
    renderShots();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
  else init();

  window.BugReport = { open };
})();
