// Bump on every change to anything this worker serves. It is the only thing
// the browser compares, so an unchanged version means nobody sees the update.
const CACHE = 'uwufix-v47';
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
self.addEventListener('install', function (event) {
  // Only this site's own files are cached up front; the Google Fonts entry is left out.
  const localAssets = ASSETS.filter(function (asset) {
    return !asset.startsWith('http');
  });
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      return cache.addAll(localAssets);
    })
  );
});

// No clients.claim() here either, for the same reason.
self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (cacheNames) {
      const deletions = [];
      for (const cacheName of cacheNames) {
        if (cacheName !== CACHE) {
          deletions.push(caches.delete(cacheName));
        }
      }
      return Promise.all(deletions);
    })
  );
});

self.addEventListener('message', function (event) {
  let type;
  if (typeof event.data === 'string') {
    type = event.data;
  } else {
    type = event.data?.type;
  }

  // The only place either of these is ever called.
  if (type === 'skip-waiting') {
    event.waitUntil(self.skipWaiting().then(function () {
      return self.clients.claim();
    }));
  }

  // Report a bug's "site uwufix-v46" (js/bug-report.js): which version of the site this is.
  if (type === 'version' && event.ports?.[0]) {
    event.ports[0].postMessage(CACHE);
  }
});

// Only ever this worker's own cache. A bare caches.match() searches every
// cache, including the one a waiting worker has just filled, which would leak
// the new version into a page the old worker is still serving.
function fromCache(request) {
  return caches.open(CACHE).then(function (cache) {
    return cache.match(request);
  });
}

/**
 * Answers the page's requests: the API and PeerJS always go to the network,
 * Google Fonts try the network first, and everything else is served from this
 * worker's cache when it has it, cached on first fetch when it doesn't, and
 * falls back to the cached home page when offline.
 */
self.addEventListener('fetch', function (event) {
  if (event.request.method !== 'GET') {
    return;
  }
  const url = new URL(event.request.url);

  // The API answers live: a cached /api/app-release would hide every new version of the
  // Android app, and /api/resolve's redirects and titles change. Offline, the page skips them.
  if (url.origin === self.location.origin && url.pathname.startsWith('/api/')) {
    return;
  }

  // Share history's pairing (js/p2p.js): PeerJS and its broker answer live. A cached copy of the
  // library buys nothing offline, as pairing needs the network anyway, and an old one talking to
  // a live broker is worse than a clear "could not load".
  if (url.hostname.endsWith('peerjs.com') || url.pathname.includes('/peerjs/')) {
    return;
  }

  // Network-first for Google Fonts
  if (url.hostname.includes('fonts.g')) {
    event.respondWith(
      fetch(event.request).catch(function () {
        return fromCache(event.request);
      })
    );
    return;
  }

  // Cache-first for local assets
  event.respondWith(
    fromCache(event.request).then(function (cached) {
      if (cached) {
        return cached;
      }
      return fetch(event.request).then(function (response) {
        if (response.ok && url.origin === self.location.origin) {
          const responseCopy = response.clone();
          caches.open(CACHE).then(function (cache) {
            return cache.put(event.request, responseCopy);
          });
        }
        return response;
      }).catch(function () {
        return fromCache('/index.html');
      });
    })
  );
});
