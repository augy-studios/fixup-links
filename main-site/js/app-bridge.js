/* The channel to the Android app 1.0.x (the site in a WebView, before 1.1.0's flutter/), when the site is open in it: what the app can do
   for the page that a web page can't do for itself. The app is Capacitor: the site runs in its
   own WebView, which injects window.Capacitor before the page's scripts, and calls go straight
   to its plugin (its FixupPlugin.java, in git history before 1.1.0).

   In a browser or the PWA there's no window.Capacitor, and the page carries on as a website
   with everything it already has.

     AppBridge.native                   true in the app
     AppBridge.has('push')              whether the app says it can
     AppBridge.ready(milliseconds)      resolves true once the app's answered, false after
                                        that many milliseconds
     AppBridge.call(plugin, method, {}) a plugin's answer
     AppBridge.quick()                  { from: 'share' | 'select' | 'copied', replace } in the
                                        app's quick screen (a link shared to uwuFix, text
                                        highlighted in another app, or what's copied, from a
                                        widget), or null
     AppBridge.version()                the app's version, such as "1.0.0"

   Also, in the app: navigator.share opens Android's share sheet (the WebView has none), and the
   status bar's icons follow the page's light or dark mode, not the phone's. */
'use strict';

(function () {
  const capacitor = window.Capacitor;
  const native = Boolean(capacitor && typeof capacitor.nativePromise === 'function' && capacitor.getPlatform?.() === 'android');

  let info = null;
  const waiting = [];

  // A plugin method's answer from the app, or a rejection outside the app.
  function call(plugin, method, options = {}) {
    if (native) {
      return capacitor.nativePromise(plugin, method, options);
    }
    return Promise.reject(new Error('Not in the app.'));
  }

  // The app has answered Fixup.info: remember it and wake everyone waiting in ready().
  function heard(answer) {
    info = answer;
    const waitingResolvers = waiting.splice(0);
    for (const resolve of waitingResolvers) {
      resolve(true);
    }
    window.dispatchEvent(new CustomEvent('app:ready', { detail: info }));
  }

  function ready(milliseconds = 1500) {
    if (info) {
      return Promise.resolve(true);
    }
    if (!native) {
      return Promise.resolve(false);
    }
    return new Promise(function (resolve) {
      waiting.push(resolve);
      setTimeout(function () {
        resolve(false);
      }, milliseconds);
    });
  }

  // The site picks light or dark itself (js/theme.js), whatever the phone's set to, so the
  // status bar's icons are told which: dark icons on the light page, light on the dark.
  function syncStatusBars() {
    let style = 'LIGHT';
    if (document.documentElement.getAttribute('data-mode') === 'dark') {
      style = 'DARK';
    }
    call('SystemBars', 'setStyle', { style }).catch(function () {});
  }

  // Empty text for a share field the page left out, as the app expects strings.
  function textOrEmpty(value) {
    if (!value) {
      return '';
    }
    return value;
  }

  if (native) {
    document.documentElement.setAttribute('data-app', 'android');
    if (!navigator.share) {
      navigator.share = function (data = {}) {
        return call('Fixup', 'share', {
          title: textOrEmpty(data.title),
          text: textOrEmpty(data.text),
          url: textOrEmpty(data.url),
        });
      };
    }
    call('Fixup', 'info')
      .then(heard)
      .catch(function () {
        heard({ features: [], quick: null });
      });

    syncStatusBars();
    new MutationObserver(syncStatusBars).observe(document.documentElement, { attributes: true, attributeFilter: ['data-mode'] });
  }

  window.AppBridge = {
    native,
    has: function (feature) {
      return Boolean(info?.features?.includes(feature));
    },
    ready,
    call,
    quick: function () {
      if (!info?.quick) {
        return null;
      }
      return info.quick;
    },
    version: function () {
      if (!info?.version) {
        return null;
      }
      return info.version;
    },
  };
})();
