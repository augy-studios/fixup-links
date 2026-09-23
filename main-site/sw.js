// Bump on every change to anything this worker serves. It is the only thing
// the browser compares, so an unchanged version means nobody sees the update.
const CACHE = 'uwufix-v32';
const ASSETS = [
  '/',
  '/index.html',
  '/style.css',
  '/script.js',
  '/js/icons.js',
  '/js/ui.js',
  '/js/theme.js',
  '/js/sw-update.js',
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
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);

  // Network-first for Google Fonts
  if (url.hostname.includes('fonts.g')) {
    e.respondWith(
      fetch(e.request).catch(() => caches.match(e.request))
    );
    return;
  }

  // Cache-first for local assets
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(res => {
        if (res.ok && url.origin === self.location.origin) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      }).catch(() => caches.match('/index.html'));
    })
  );
});
