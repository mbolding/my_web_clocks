/* Plate — service worker.
   The whole app is a handful of static files, so precache all of them.
   Page navigations are network-first (falling back to the cached shell
   offline); every other same-origin GET is cache-first. Bump CACHE when you
   change any file.

   Note the 'plate-' prefix: this origin may host other apps with their own
   service workers, so cleanup only ever touches caches belonging to Plate. */

const PREFIX = 'plate-';
const CACHE = PREFIX + 'v2';

const SHELL = [
  'index.html',
  'manifest.webmanifest',
  'icon.svg',
  'icon-192.png',
  'icon-512.png',
  'icon-maskable-512.png',
  'apple-touch-icon-180.png',
  'favicon-32.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => Promise.all(
        // cache.addAll() is all-or-nothing: one flaky fetch fails the whole
        // precache silently, leaving the installed app with no offline shell
        // even though installation otherwise "succeeded". Cache each file on
        // its own so a single miss doesn't sink the rest.
        SHELL.map((url) => cache.add(url).catch(() => {}))
      ))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k.startsWith(PREFIX) && k !== CACHE).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  if (new URL(req.url).origin !== self.location.origin) return;

  // Navigations: network-first, so an installed launch (which goes through
  // this handler even when online) always gets the live page rather than
  // depending on the precache having succeeded. Falls back to the cached
  // shell when offline, and to index.html itself as a last resort so this
  // never resolves with no response at all.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put('index.html', copy));
          return res;
        })
        .catch(() => caches.match('index.html', { ignoreSearch: true }))
        .then((res) => res || caches.match('index.html'))
    );
    return;
  }

  event.respondWith(
    caches.match(req, { ignoreSearch: true }).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((res) => {
        if (res && res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put(req, copy));
        }
        return res;
      });
    })
  );
});
