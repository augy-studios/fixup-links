// Bump on every change to anything this worker serves. It is the only thing
// the browser compares, so an unchanged version means nobody sees the update.
const CACHE = 'uwufix-v46';
const ASSETS = [
  '/',
  '/index.html',
  '/style.css',
  '/script.js',
  '/js/icons.js',
  '/js/ui.js',
  '/js/app-bridge.js',
  '/js/theme.js',
  '/js/tray.js',
  '/js/sw-update.js',
  '/js/app-update.js',
  '/js/app-notify.js',
  '/js/history-merge.js',
  '/js/p2p.js',
  '/js/sync.js',
  '/js/tour.js',
  '/js/bug-report.js',
  '/manifest.json',
  '/UFX-main.png',
  '/UFX-192.png',
  '/UFX-512.png',
  'https://fonts.googleapis.com/css2?family=Jua&display=swap',
];

// No skipWaiting() here: a new worker installs and then waits until somebody
// presses Reload in the update bar (js/sw-update.js).
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(ASSETS.filter(a => !a.startsWith('http'))))
  );
});

// No clients.claim() here either, for the same reason.
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
});

self.addEventListener('message', (event) => {
  const type = typeof event.data === 'string' ? event.data : event.data?.type;

  // The only place either of these is ever called.
  if (type === 'skip-waiting') {
    event.waitUntil(self.skipWaiting().then(() => self.clients.claim()));
  }

  // Report a bug's "site uwufix-v46" (js/bug-report.js): which version of the site this is.
  if (type === 'version' && event.ports?.[0]) event.ports[0].postMessage(CACHE);
});

// Only ever this worker's own cache. A bare caches.match() searches every
// cache, including the one a waiting worker has just filled, which would leak
// the new version into a page the old worker is still serving.
const fromCache = request => caches.open(CACHE).then(c => c.match(request));

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);

  // The API answers live: a cached /api/app-release would hide every new version of the
  // Android app, and /api/resolve's redirects and titles change. Offline, the page skips them.
  if (url.origin === self.location.origin && url.pathname.startsWith('/api/')) return;

  // Share history's pairing (js/p2p.js): PeerJS and its broker answer live. A cached copy of the
  // library buys nothing offline, as pairing needs the network anyway, and an old one talking to
  // a live broker is worse than a clear "could not load".
  if (url.hostname.endsWith('peerjs.com') || url.pathname.includes('/peerjs/')) return;

  // Network-first for Google Fonts
  if (url.hostname.includes('fonts.g')) {
    e.respondWith(
      fetch(e.request).catch(() => fromCache(e.request))
    );
    return;
  }

  // Cache-first for local assets
  e.respondWith(
    fromCache(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(res => {
        if (res.ok && url.origin === self.location.origin) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      }).catch(() => fromCache('/index.html'));
    })
  );
});
