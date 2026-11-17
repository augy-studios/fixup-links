/* The Android app's update bar: in the app 1.0.x (the WebView app, before 1.1.0's flutter/), when GitHub has a newer version of it
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

  // Whether version `candidate` comes after version `current`, number by number: 1.10.0 after 1.9.0. The same
  // as newer() in api/app-release.js.
  function newer(candidate, current) {
    const candidateParts = versionNumbers(candidate);
    const currentParts = versionNumbers(current);
    for (let index = 0; index < Math.max(candidateParts.length, currentParts.length); index++) {
      const difference = numberAt(candidateParts, index) - numberAt(currentParts, index);
      if (difference) {
        return difference > 0;
      }
    }
    return false;
  }

  // "1.10.0" as [1, 10, 0]; anything that isn't a number counts as 0.
  function versionNumbers(version) {
    const numbers = [];
    for (const part of String(version).split('.')) {
      let number = parseInt(part, 10);
      if (!number) {
        number = 0;
      }
      numbers.push(number);
    }
    return numbers;
  }

  // The number at this position, or 0 past the end.
  function numberAt(numbers, index) {
    if (numbers[index]) {
      return numbers[index];
    }
    return 0;
  }

  /** Asks /api/app-release for the newest version and shows the bar if it's newer than this app. */
  async function check() {
    checkedAt = Date.now();
    let latest;
    try {
      const response = await fetch('/api/app-release', { cache: 'no-store' });
      if (!response.ok) {
        return;
      }
      latest = await response.json();
    } catch {
      return; // Offline: next time.
    }
    const running = AppBridge.version();
    if (latest?.version && running && newer(latest.version, running)) {
      render(latest);
    }
  }

  /** Shows the "version X is out" bar with Update and Not now, once per page view. */
  function render(latest) {
    if (dismissed || document.querySelector('.app-update-notice')) {
      return;
    }

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
    bar.querySelector('[data-app-update]').addEventListener('click', function () {
      AppBridge.call('Fixup', 'update', { check: false }).catch(function () {});
    });
    bar.querySelector('[data-app-later]').addEventListener('click', function () {
      dismissed = true;
      bar.remove();
    });
    document.body.prepend(bar);
  }

  if (!window.AppBridge?.native) {
    return;
  }
  AppBridge.ready(5000).then(function (inApp) {
    if (!inApp || AppBridge.quick()) {
      return;
    }
    if (AppBridge.has('checkupdate')) {
      const button = document.getElementById('appUpdateBtn');
      button.hidden = false;
      button.addEventListener('click', function () {
        AppBridge.call('Fixup', 'update', { check: true }).catch(function () {});
      });
    }
    check();
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible' && Date.now() - checkedAt > UPDATE_CHECK_MS) {
        check();
      }
    });
  });
})();
