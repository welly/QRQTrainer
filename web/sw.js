// Service worker: keeps a copy of QRQ Trainer, so it opens and works without a connection.
//
// scripts/publish-web.sh replaces VERSION with the commit it publishes. The page (index.html) is fetched from
// the network first, so a new version is picked up whenever there is a connection; everything else is stamped
// with ?v=VERSION and served from the cache. A new version installs alongside and the old cache is dropped.

const VERSION = 'dev';
const CACHE = `qrq-${VERSION}`;
const v = `?v=${VERSION}`;
const FILES = [
  './',
  `app.js${v}`, `engine.js${v}`, `qrq.wasm${v}`,
  'icon.png', 'apple-touch-icon.png', 'icon-192.png', 'icon-512.png', 'manifest.webmanifest',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) if (key.startsWith('qrq-') && key !== CACHE) await caches.delete(key);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response.ok) (await caches.open(CACHE)).put('./', response.clone());
        return response;
      } catch {
        return (await caches.match('./', { cacheName: CACHE })) ?? Response.error();
      }
    })());
    return;
  }

  event.respondWith((async () => (await caches.match(request, { cacheName: CACHE })) ?? fetch(request))());
});
