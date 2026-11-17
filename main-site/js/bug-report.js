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
  function select(selector) {
    return document.querySelector(selector);
  }
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
    const serviceWorker = navigator.serviceWorker?.controller;
    if (!serviceWorker) {
      return Promise.resolve(null);
    }
    return new Promise(function (resolve) {
      const channel = new MessageChannel();
      const timer = setTimeout(function () {
        resolve(null);
      }, VERSION_MS);
      channel.port1.onmessage = function ({ data }) {
        clearTimeout(timer);
        if (typeof data === 'string') {
          resolve(data);
        } else {
          resolve(null);
        }
      };
      serviceWorker.postMessage({ type: 'version' }, [channel.port2]);
    });
  }

  // Which app this is: the WebView Android app (1.0.x), the site installed, or the site in a
  // browser. (The apps from 1.1.0 send their own reports.)
  function platform() {
    if (window.AppBridge?.native) {
      return 'android';
    }
    if (window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone) {
      return 'pwa';
    }
    return 'web';
  }
  const PLATFORM_NAMES = { web: 'Web', pwa: 'Web, installed', android: 'Android app', desktop: 'Desktop app' };

  // "1.0.1, site uwufix-v46": the app's own version where it has one, then the site's.
  function version() {
    const parts = [];
    const appVersion = window.AppBridge?.version?.();
    if (appVersion) {
      parts.push(appVersion);
    }
    if (siteVersion) {
      parts.push(`site ${siteVersion}`);
    }
    return parts.join(', ');
  }

  // The system and browser, and the window's size: "Android 14 · Chrome 130 · 412×915".
  // Each [pattern, name], the first that matches; a number caught is the version.
  const SYSTEMS = [[/Android ([\d.]+)/, 'Android'], [/(?:iPhone|iPad|iPod).*? OS (\d+)/, 'iOS'], [/Windows NT/, 'Windows'],
    [/CrOS/, 'ChromeOS'], [/Mac OS X/, 'macOS'], [/Linux/, 'Linux']];
  const BROWSERS = [[/SamsungBrowser\/(\d+)/, 'Samsung Internet'], [/Edg\/(\d+)/, 'Edge'], [/Firefox\/(\d+)/, 'Firefox'],
    [/(?:Chrome|CriOS)\/(\d+)/, 'Chrome'], [/Version\/(\d+).*Safari/, 'Safari']];
  function first(list, userAgent, none) {
    for (const [pattern, name] of list) {
      const match = pattern.exec(userAgent);
      if (match) {
        if (match[1]) {
          return `${name} ${match[1]}`;
        }
        return name;
      }
    }
    return none;
  }
  function device() {
    let userAgent = navigator.userAgent;
    if (!userAgent) {
      userAgent = '';
    }
    return `${first(SYSTEMS, userAgent, 'Unknown system')} · ${first(BROWSERS, userAgent, 'Unknown browser')} · ${window.innerWidth}×${window.innerHeight}`;
  }

  // The page on show under this window: Home, History or Share history. Never a link.
  function page() {
    function shown(id) {
      return !document.getElementById(id)?.classList.contains('hidden');
    }
    if (shown('syncModal')) {
      return 'Share history';
    }
    if (shown('historyModal')) {
      return 'History';
    }
    return 'Home';
  }

  /** What's sent with the report, plus platformName for showing (not sent). */
  function collect() {
    const platformId = platform();
    let language = navigator.language;
    if (!language) {
      language = 'en';
    }
    return { version: version(), platform: platformId, device: device(), page: page(), lang: language.slice(0, 10), platformName: PLATFORM_NAMES[platformId] };
  }

  // Words with {name} filled in.
  function fill(text, values) {
    return text.replace(/\{(\w+)\}/g, function (wholeMatch, key) {
      if (key in values) {
        return String(values[key]);
      }
      return wholeMatch;
    });
  }

  /** Shows text under the form; with email, also a link to send the report by email instead. */
  function say(text, { email = false } = {}) {
    const statusElement = select('#bugStatus');
    statusElement.hidden = !text;
    if (text) {
      statusElement.textContent = text;
    } else {
      statusElement.textContent = '';
    }
    if (email) {
      const body = `${select('#bugText').value.trim()}\n\n${detailsText()}`;
      const link = document.createElement('a');
      link.href = `mailto:${EMAIL}?subject=${encodeURIComponent('uwuFix bug report')}&body=${encodeURIComponent(body)}`;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.textContent = 'Email it instead.';
      statusElement.append(' ', link);
    }
  }

  function detailsText() {
    const parts = [];
    for (const part of [details.platformName, details.version, details.device, details.page]) {
      if (part) {
        parts.push(part);
      }
    }
    return parts.join(' · ');
  }

  function renderDetails() {
    select('#bugDetails').textContent = `${detailsText()}.`;
  }

  async function open() {
    details = collect();
    renderDetails();
    say('');
    window.openModal(ID);
    setTimeout(function () {
      select('#bugText').focus();
    }, 50);
    // The site's version arrives a moment later, the first time.
    if (!siteVersion) {
      siteVersion = await askVersion();
      if (siteVersion && details) {
        details.version = version();
        renderDetails();
      }
    }
  }

  // ---------- pictures ----------

  /** Loads an image from a URL (or data URL), rejecting if it isn't one. */
  function loadImage(url) {
    return new Promise(function (resolve, reject) {
      const image = new Image();
      image.onload = function () {
        resolve(image);
      };
      image.onerror = function () {
        reject(new Error('not an image'));
      };
      image.src = url;
    });
  }

  // An image (a File, or a data URL) as a JPEG data URL, at most SHOT_SIDE a side and about
  // SHOT_BYTES, smaller and rougher till it is.
  async function shrink(source) {
    let url;
    if (typeof source === 'string') {
      url = source;
    } else {
      url = URL.createObjectURL(source);
    }
    try {
      const image = await loadImage(url);
      let side = SHOT_SIDE;
      for (let tries = 0; tries < 6; tries++) {
        const scale = Math.min(1, side / Math.max(image.naturalWidth, image.naturalHeight));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
        canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
        const context = canvas.getContext('2d');
        context.fillStyle = '#fff';
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.drawImage(image, 0, 0, canvas.width, canvas.height);
        let quality = 0.7;
        if (tries < 2) {
          quality = 0.82;
        }
        const jpeg = canvas.toDataURL('image/jpeg', quality);
        if (jpeg.length * 0.75 <= SHOT_BYTES || tries === 5) {
          return jpeg;
        }
        side = Math.round(side * 0.8);
      }
    } finally {
      if (typeof source !== 'string') {
        URL.revokeObjectURL(url);
      }
    }
    return null;
  }

  // A whole-page screenshot (a data URL) as a JPEG data URL, as tall as the page, within
  // PAGE_WIDTH, PAGE_SUM and PAGE_RATIO and about SHOT_BYTES, smaller and rougher till it is.
  async function shrinkPage(source) {
    const image = await loadImage(source);
    const width = image.naturalWidth;
    const height = Math.min(image.naturalHeight, width * PAGE_RATIO);
    let scale = Math.min(1, PAGE_WIDTH / width, (PAGE_SUM - 2) / (width + height));
    for (let tries = 0; tries < 8; tries++) {
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.floor(width * scale));
      // The height from the rounded-down width, so it stays within PAGE_RATIO.
      canvas.height = Math.max(1, Math.min(Math.floor(height * scale), canvas.width * PAGE_RATIO));
      const context = canvas.getContext('2d');
      context.fillStyle = '#fff';
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.drawImage(image, 0, 0, width, height, 0, 0, canvas.width, canvas.height);
      let quality = 0.68;
      if (tries < 2) {
        quality = 0.8;
      }
      const jpeg = canvas.toDataURL('image/jpeg', quality);
      if (jpeg.length * 0.75 <= SHOT_BYTES || tries === 7) {
        return jpeg;
      }
      if (tries >= 1) {
        scale *= 0.82;
      }
    }
    return null;
  }

  /** Shows the pictures added so far, each with a remove button, and disables adding at MAX_SHOTS. */
  function renderShots() {
    const box = select('#bugShots');
    let html = '';
    for (let shotIndex = 0; shotIndex < shots.length; shotIndex++) {
      const shot = shots[shotIndex];
      const pictureLabel = fill('Picture {n}', { n: shotIndex + 1 });
      const removeLabel = fill('Remove picture {n}', { n: shotIndex + 1 });
      html += `<span class="bugShot"><img src="${shot}" alt="${pictureLabel}"><button type="button" class="bugShotX" data-bug-shot="${shotIndex}" aria-label="${removeLabel}">×</button></span>`;
    }
    box.innerHTML = html;
    box.hidden = !shots.length;
    const full = shots.length >= MAX_SHOTS;
    select('#bugAddPic').disabled = full;
    select('#bugScreenshot').disabled = full;
  }

  async function addShot(source) {
    if (shots.length >= MAX_SHOTS) {
      return;
    }
    try {
      const jpeg = await shrink(source);
      if (jpeg) {
        shots.push(jpeg);
      }
    } catch {
      say("Couldn't add that picture.");
    }
    renderShots();
  }

  // The script that draws the page, the first time it's wanted.
  let library = null;
  function captureLib() {
    if (window.htmlToImage) {
      return Promise.resolve(window.htmlToImage);
    }
    if (library === null || library === undefined) {
      library = new Promise(function (resolve, reject) {
        const script = document.createElement('script');
        script.src = CAPTURE_LIB;
        script.onload = function () {
          if (window.htmlToImage) {
            resolve(window.htmlToImage);
          } else {
            reject(new Error('no htmlToImage'));
          }
        };
        script.onerror = function () {
          library = null;
          reject(new Error('could not load'));
        };
        document.head.appendChild(script);
      });
    }
    return library;
  }

  /**
   * Whether html-to-image should draw this node. Left out: this window (it's over the page; History
   * and Share history stay, being where the bug may be), tours and toasts, and what can't be drawn,
   * which would spoil the whole picture: videos, and images with nothing in them yet.
   */
  function shouldDraw(node) {
    if (node.id === 'bugModal') {
      return false;
    }
    if (node.classList && (node.classList.contains('tour') || node.classList.contains('toast'))) {
      return false;
    }
    if (node.tagName === 'VIDEO') {
      return false;
    }
    if (node.tagName === 'IMG' && (!node.currentSrc || !node.complete || !node.naturalWidth)) {
      return false;
    }
    return true;
  }

  // The page as it is under this window, drawn: the whole page, from the top, however far down
  // it goes.
  async function screenshot() {
    if (shots.length >= MAX_SHOTS) {
      return;
    }
    const button = select('#bugScreenshot');
    button.disabled = true;
    say('Taking a screenshot…');
    try {
      const htmlToImage = await captureLib();
      const background = getComputedStyle(document.body).backgroundColor;
      const width = window.innerWidth;
      let scrollingHeight = document.scrollingElement?.scrollHeight;
      if (!scrollingHeight) {
        scrollingHeight = 0;
      }
      let bodyHeight = document.body.scrollHeight;
      if (!bodyHeight) {
        bodyHeight = 0;
      }
      const height = Math.max(window.innerHeight, scrollingHeight, bodyHeight);
      const tall = height > window.innerHeight + 4;
      let devicePixelRatio = window.devicePixelRatio;
      if (!devicePixelRatio) {
        devicePixelRatio = 1;
      }
      let backgroundColor = '#ffffff';
      if (background && background !== 'rgba(0, 0, 0, 0)') {
        backgroundColor = background;
      }
      const url = await htmlToImage.toJpeg(document.body, {
        quality: 0.85,
        pixelRatio: Math.min(2, devicePixelRatio, PAGE_DRAW / height),
        width,
        height,
        backgroundColor,
        cacheBust: false,
        imagePlaceholder: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
        filter: shouldDraw,
      });
      if (tall) {
        const pageShot = await shrinkPage(url);
        if (pageShot && shots.length < MAX_SHOTS) {
          shots.push(pageShot);
          fullShots.add(shots.length - 1);
        }
      } else {
        await addShot(url);
      }
      say('');
    } catch (error) {
      console.warn("couldn't take the screenshot:", error);
      say("Couldn't take a screenshot here. Take one with your phone and add it instead.");
    } finally {
      renderShots();
    }
  }

  /** Reads a JSON reply, or null if it isn't JSON. */
  async function readJson(response) {
    try {
      return await response.json();
    } catch {
      return null;
    }
  }

  /**
   * Sends the report to api/bug-report.js: checks there's enough text and a connection first, then
   * says the report's ID on success, the server's reason for a bad request, or offers email.
   */
  async function send(event) {
    event.preventDefault();
    if (sending) {
      return;
    }
    const text = select('#bugText').value.trim();
    if (text.length < MIN_TEXT) {
      say('Please say what went wrong first.');
      select('#bugText').focus();
      return;
    }
    if (navigator.onLine === false) {
      say("You're offline. It's kept here: send it once you're back online.");
      return;
    }
    sending = true;
    select('#bugSend').disabled = true;
    say('Sending…');
    try {
      const { platformName, ...sent } = details;
      const response = await fetch('/api/bug-report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...sent, text, contact: select('#bugContact').value.trim(), website: select('#bugWebsite').value, images: shots, full: [...fullShots] }),
      });
      if (response.ok) {
        select('#bugText').value = '';
        select('#bugContact').value = '';
        shots = [];
        fullShots = new Set();
        renderShots();
        // Its ID, to quote (a site from before IDs answers with none).
        const reply = await readJson(response);
        let id = null;
        if (typeof reply?.id === 'string') {
          id = reply.id;
        }
        if (id) {
          say(fill('Sent as report {id}. Thank you! Augy will look into it.', { id }));
        } else {
          say('Sent. Thank you! Augy will look into it.');
        }
        return;
      }
      const reply = await readJson(response);
      const errorText = reply?.error;
      // Something about what was typed, or too many at once: said as it is. Otherwise, email.
      if (response.status === 400 || response.status === 413 || response.status === 429) {
        if (errorText) {
          say(errorText);
        } else {
          say("Couldn't send it right now.");
        }
      } else if (response.status === 503) {
        say("Bug reports can't be sent from the app yet.", { email: true });
      } else {
        say("Couldn't send it right now.", { email: true });
      }
    } catch {
      say("Couldn't send it right now.", { email: true });
    } finally {
      sending = false;
      select('#bugSend').disabled = false;
    }
  }

  /** Wires up the form: open, send, add a picture, screenshot, and remove a picture. */
  function init() {
    if (!document.getElementById(ID)) {
      return;
    }
    document.getElementById('bugBtn')?.addEventListener('click', open);
    select('#bugForm').addEventListener('submit', send);
    select('#bugAddPic').addEventListener('click', function () {
      select('#bugPicFile').click();
    });
    select('#bugPicFile').addEventListener('change', async function (event) {
      let picked = event.target.files;
      if (!picked) {
        picked = [];
      }
      const files = [...picked].slice(0, MAX_SHOTS - shots.length);
      event.target.value = '';
      for (const file of files) {
        await addShot(file);
      }
    });
    select('#bugScreenshot').addEventListener('click', screenshot);
    select('#bugShots').addEventListener('click', function (event) {
      const removeButton = event.target.closest('[data-bug-shot]');
      if (!removeButton) {
        return;
      }
      const removedIndex = Number(removeButton.dataset.bugShot);
      shots.splice(removedIndex, 1);
      // The later pictures move up one, so their full-page marks do too.
      const remainingFullShots = new Set();
      for (const shotIndex of fullShots) {
        if (shotIndex === removedIndex) {
          continue;
        }
        if (shotIndex > removedIndex) {
          remainingFullShots.add(shotIndex - 1);
        } else {
          remainingFullShots.add(shotIndex);
        }
      }
      fullShots = remainingFullShots;
      renderShots();
    });
    renderShots();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }

  window.BugReport = { open };
})();
