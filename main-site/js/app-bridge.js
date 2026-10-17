/* The channel to the Android app (android/), when the site is open in it: what the app can do
   for the page that a web page can't do for itself. The app is Capacitor: the site runs in its
   own WebView, which injects window.Capacitor before the page's scripts, and calls go straight
   to its plugin (android/native/app/src/main/java/org/uwuapps/fixup/FixupPlugin.java).

   In a browser or the PWA there's no window.Capacitor, and the page carries on as a website
   with everything it already has.

     AppBridge.native                   true in the app
     AppBridge.has('push')              whether the app says it can
     AppBridge.ready(ms)                resolves true once the app's answered, false after ms
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
  const cap = window.Capacitor;
  const native = !!(cap && typeof cap.nativePromise === 'function' && cap.getPlatform?.() === 'android');

  let info = null;
  const waiting = [];

  const call = (plugin, method, options = {}) =>
    native ? cap.nativePromise(plugin, method, options) : Promise.reject(new Error('Not in the app.'));

  function heard(answer) {
    info = answer;
    waiting.splice(0).forEach((resolve) => resolve(true));
    window.dispatchEvent(new CustomEvent('app:ready', { detail: info }));
  }

  function ready(ms = 1500) {
    if (info) return Promise.resolve(true);
    if (!native) return Promise.resolve(false);
    return new Promise((resolve) => {
      waiting.push(resolve);
      setTimeout(() => resolve(false), ms);
    });
  }

  // The site picks light or dark itself (js/theme.js), whatever the phone's set to, so the
  // status bar's icons are told which: dark icons on the light page, light on the dark.
  function syncBars() {
    const style = document.documentElement.getAttribute('data-mode') === 'dark' ? 'DARK' : 'LIGHT';
    call('SystemBars', 'setStyle', { style }).catch(() => {});
  }

  if (native) {
    document.documentElement.setAttribute('data-app', 'android');
    if (!navigator.share) {
      navigator.share = (data = {}) => call('Fixup', 'share', { title: data.title || '', text: data.text || '', url: data.url || '' });
    }
    call('Fixup', 'info')
      .then(heard)
      .catch(() => heard({ features: [], quick: null }));

    syncBars();
    new MutationObserver(syncBars).observe(document.documentElement, { attributes: true, attributeFilter: ['data-mode'] });
  }

  window.AppBridge = {
    native,
    has: (feature) => !!info?.features?.includes(feature),
    ready,
    call,
    quick: () => info?.quick || null,
    version: () => info?.version || null,
  };
})();
