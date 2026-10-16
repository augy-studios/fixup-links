/* The Android app's update bar: in the app (android/), when GitHub has a newer version of it
   than the one running. The app says its version (js/app-bridge.js), and /api/app-release the
   newest one. Update opens the app's update window (UpdateActivity.java), which downloads the
   APK and hands it to Android's own installer.

   Looked up as the page opens, and again on coming back to it after UPDATE_CHECK_MS, as the
   app stays open for days. "Not now" lasts this page view only, like js/sw-update.js.

   The Edge Tray's download button ("Check for app updates") opens the same window to look
   whenever you like: it says if you have the newest version, and asks before downloading one.

   Not in the quick screen (a link shared to uwuFix), which is there for one link and gone. */
'use strict';

(function () {
  const UPDATE_CHECK_MS = 6 * 3600 * 1000;

  let checkedAt = 0;
  // For this page view only. Never stored: "Not now" means not now.
  let dismissed = false;

  // Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same
  // as newer() in api/app-release.js.
  function newer(a, b) {
    const x = String(a).split('.').map((n) => parseInt(n, 10) || 0);
    const y = String(b).split('.').map((n) => parseInt(n, 10) || 0);
    for (let i = 0; i < Math.max(x.length, y.length); i++) {
      const d = (x[i] || 0) - (y[i] || 0);
      if (d) return d > 0;
    }
    return false;
  }

  async function check() {
    checkedAt = Date.now();
    let latest;
    try {
      const res = await fetch('/api/app-release', { cache: 'no-store' });
      if (!res.ok) return;
      latest = await res.json();
    } catch {
      return; // Offline: next time.
    }
    const running = AppBridge.version();
    if (latest?.version && running && newer(latest.version, running)) render(latest);
  }

  function render(latest) {
    if (dismissed || document.querySelector('.app-update-notice')) return;

    const bar = document.createElement('div');
    bar.className = 'app-update-notice';
    bar.setAttribute('role', 'status');
    bar.setAttribute('aria-label', 'App update');
    bar.innerHTML = `
      <div class="update-notice-inner">
        <p></p>
        <button type="button" class="btn btn-sm btn-primary" data-app-update>Update</button>
        <button type="button" class="btn btn-sm btn-secondary" data-app-later>Not now</button>
      </div>
    `;
    bar.querySelector('p').textContent = `Version ${latest.version} of the uwuFix app is out.`;
    bar.querySelector('[data-app-update]').addEventListener('click', () => {
      AppBridge.call('Fixup', 'update', { check: false }).catch(() => {});
    });
    bar.querySelector('[data-app-later]').addEventListener('click', () => {
      dismissed = true;
      bar.remove();
    });
    document.body.prepend(bar);
  }

  if (!window.AppBridge?.native) return;
  AppBridge.ready(5000).then((inApp) => {
    if (!inApp || AppBridge.quick()) return;
    if (AppBridge.has('checkupdate')) {
      const btn = document.getElementById('appUpdateBtn');
      btn.hidden = false;
      btn.addEventListener('click', () => AppBridge.call('Fixup', 'update', { check: true }).catch(() => {}));
    }
    check();
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && Date.now() - checkedAt > UPDATE_CHECK_MS) check();
    });
  });
})();
