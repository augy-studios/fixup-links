/* Service worker registration and the "new version is ready" bar.
   The one place the site registers /sw.js. A new worker installs and waits;
   it only takes over when somebody presses Reload here. */
'use strict';

(function () {
  var SW_URL = '/sw.js';

  var COPY = {
    'update.label': 'Update',
    'update.ready': 'A new version of uwuFix is ready.',
    'update.reload': 'Reload',
    'update.later': 'Not now',
  };

  var registration = null;
  var waitingWorker = null;
  var reloading = false;
  // For this page view only. Never stored: "Not now" means not now.
  var dismissed = false;

  function t(key) {
    return COPY[key] || key;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  function render() {
    var existing = document.querySelector('.update-notice');

    if (!waitingWorker || dismissed) {
      if (existing) existing.remove();
      return;
    }

    var bar = existing || document.createElement('div');
    bar.className = 'update-notice';
    bar.setAttribute('role', 'status');
    bar.setAttribute('aria-label', t('update.label'));
    bar.innerHTML =
      '<div class="update-notice-inner">' +
        '<p>' + escapeHtml(t('update.ready')) + '</p>' +
        '<button type="button" class="btn btn-sm btn-primary" data-sw-update>' +
          escapeHtml(t('update.reload')) +
        '</button>' +
        '<button type="button" class="btn btn-sm btn-secondary" data-sw-later>' +
          escapeHtml(t('update.later')) +
        '</button>' +
      '</div>';

    bar.querySelector('[data-sw-update]').addEventListener('click', function () {
      // The only place anything asks for skipWaiting. The reload happens on
      // controllerchange, not here.
      if (waitingWorker) waitingWorker.postMessage('skip-waiting');
    });

    bar.querySelector('[data-sw-later]').addEventListener('click', function () {
      dismissed = true;
      render();
    });

    if (!existing) document.body.prepend(bar);
  }

  function watchForUpdate() {
    if (!registration) return;

    // A worker already waiting when the page opened: the ordinary case on the
    // next visit after a deploy.
    if (registration.waiting && navigator.serviceWorker.controller) {
      waitingWorker = registration.waiting;
      render();
    }

    registration.addEventListener('updatefound', function () {
      var installing = registration.installing;
      if (!installing) return;

      installing.addEventListener('statechange', function () {
        // `installed` with no controller is a first install, which has no
        // previous version on screen to protect and nothing to prompt about.
        if (installing.state === 'installed' && navigator.serviceWorker.controller) {
          waitingWorker = registration.waiting || installing;
          render();
        }
      });
    });

    // A tab left open for days never navigates, so the browser never looks for
    // a new worker on its own. Coming back to the tab is the moment to ask.
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState !== 'visible' || !navigator.onLine) return;
      registration.update().catch(function () {});
    });
  }

  function registerWorker() {
    if (!('serviceWorker' in navigator)) return;

    navigator.serviceWorker
      .register(SW_URL)
      .then(function (reg) {
        registration = reg;
        watchForUpdate();
      })
      .catch(function (cause) {
        // A refused registration is not a reason to break the page.
        console.warn('service worker registration failed:', cause);
      });

    // The swap, once somebody has accepted it. Reloading here rather than in
    // the click handler means the reload is served by the new worker.
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (reloading) return;
      reloading = true;
      window.location.reload();
    });
  }

  // On load, so precaching does not compete with the page's own first fetches.
  if (document.readyState === 'complete') registerWorker();
  else window.addEventListener('load', registerWorker, { once: true });
})();
