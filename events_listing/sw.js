// Service Worker for PXO Pulse PWA
// Version 1.0.0

const CACHE_NAME = 'pxo-pulse-v1';
const urlsToCache = [
  '/',
  '/assets/css/styles.css',
  '/assets/js/event-filter.js',
  '/assets/js/pwa-install.js',
  '/assets/logo180.webp',
  '/assets/logo120.webp',
  '/assets/android-chrome-192x192.png',
  '/assets/android-chrome-512x512.png',
  '/offline.html'
];

// Install Service Worker
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        return cache.addAll(urlsToCache);
      })
  );
});

// Fetch event - serve from cache when offline
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const requestUrl = new URL(request.url);

  // Strategy: Cache first, falling back to network.
  // For specific assets (like main CSS), ignore query params when matching in cache
  // to ensure the version cached at install time is served.
  let cacheMatchPromise;

  if (requestUrl.pathname === '/assets/css/styles.css') {
    cacheMatchPromise = caches.match(request, { ignoreSearch: true });
  } else {
    cacheMatchPromise = caches.match(request);
  }

  event.respondWith(
    cacheMatchPromise.then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse; // Serve from cache
      }

      // Not in cache, fetch from network
      return fetch(request).then((networkResponse) => {
        // Optional: If you wanted to dynamically cache new successful GET requests,
        // you could add logic here. For an MVP, relying on install-time cache is often sufficient.
        // Example:
        // if (request.method === 'GET' && networkResponse.ok && networkResponse.type === 'basic') {
        //   const cache = await caches.open(CACHE_NAME);
        //   cache.put(request, networkResponse.clone());
        // }
        return networkResponse;
      });
    }).catch(() => {
      // This catch handles errors from caches.match or if fetch itself fails (e.g., offline).
      // If it's a navigation request, serve the offline page.
      if (request.mode === 'navigate') {
        return caches.match('/offline.html');
      }
      // For other types of failed requests (images, scripts not in cache and network fails),
      // let the browser handle the error (e.g., show a broken image icon).
    })
  );
});

// Activate Service Worker and clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});
