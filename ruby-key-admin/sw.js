/* Ruby Key service worker - offline shell cache */
const CACHE = 'ruby-key-v1';
const CORE = [
  './',
  './index.html',
  './styles.css',
  './app.js',
  './firebase-config.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  // Firebase / Google APIs must always hit the network (live data).
  if (url.host.includes('googleapis.com') || url.host.includes('gstatic.com') ||
      url.host.includes('firebaseio.com') || url.host.includes('google.com')) {
    return;
  }
  // Same-origin shell: cache-first.
  if (url.origin === self.location.origin) {
    e.respondWith(
      caches.match(e.request).then((hit) => {
        return hit || fetch(e.request).then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy));
          return res;
        }).catch(() => caches.match('./index.html'));
      })
    );
  }
});
