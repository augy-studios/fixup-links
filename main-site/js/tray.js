/* The Edge Tray (edge-tray-spec.md): the column of links and global actions pinned top right.
   Its tab slides the column off the right edge, leaving only the tab. Remembered per browser;
   open unless this browser last left it collapsed.

   Also keeps it, and the sticky header, below an update bar while one shows (js/sw-update.js,
   js/app-update.js), by publishing the bar's height as --banner-h. */
'use strict';

(function () {
  // Same key as the pre-paint script in index.html's head. Change both together.
  const TRAY_KEY = 'uwufix.trayOpen';
  const BANNERS = '.update-notice, .app-update-notice';

  let tray;
  let trayTab;
  let trayButtons;

  function setTray(open, { save = true } = {}) {
    tray.classList.toggle('collapsed', !open);
    trayTab.setAttribute('aria-expanded', String(open));
    trayTab.setAttribute('aria-label', open ? 'Hide menu' : 'Show menu');
    // Off-screen buttons must not take focus or clicks.
    trayButtons.inert = !open;
    document.body.classList.toggle('tray-open', open);
    if (save) {
      try {
        localStorage.setItem(TRAY_KEY, open ? '1' : '0');
      } catch {
        // Remembered for this page view only.
      }
    }
  }

  function initTray() {
    tray = document.getElementById('tray');
    trayTab = document.getElementById('trayTab');
    trayButtons = document.getElementById('trayButtons');

    let open = true;
    try {
      open = localStorage.getItem(TRAY_KEY) !== '0';
    } catch {
      // Open, the default.
    }
    setTray(open, { save: false });

    // The head script painted a stored collapse without transitions. Hand back to the real
    // state a frame later, so later toggles animate.
    requestAnimationFrame(() => {
      document.documentElement.classList.remove('tray-start-collapsed');
    });

    trayTab.addEventListener('click', () => setTray(tray.classList.contains('collapsed')));
  }

  // The update bars are drawn into <body> by script whenever they're ready, and only one
  // shows at a time (style.css), so this watches for them coming and going and measures
  // whichever is on screen.
  function watchBanners() {
    const root = document.documentElement;
    const sizer = new ResizeObserver(measure);
    let watched = [];

    function measure() {
      const shown = watched.find((el) => el.offsetHeight > 0);
      root.style.setProperty('--banner-h', `${shown ? shown.offsetHeight : 0}px`);
    }

    function rewatch() {
      sizer.disconnect();
      watched = [...document.querySelectorAll(BANNERS)];
      watched.forEach((el) => sizer.observe(el));
      measure();
    }

    new MutationObserver(rewatch).observe(document.body, { childList: true });
    rewatch();
  }

  document.addEventListener('DOMContentLoaded', () => {
    initTray();
    watchBanners();
  });
})();
