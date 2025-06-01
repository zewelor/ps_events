// Service Worker for PXO Pulse PWA
// Version 1.0.0

const CACHE_NAME = 'pxo-pulse-v1.1'; // Incremented version for cache update
const urlsToCache = [
  // Core PWA & Navigation
  '/',
  '/offline.html',
  '/assets/site.webmanifest',

  // Styles & Scripts
  '/assets/css/styles.css',
  '/assets/js/event-filter.js',
  '/assets/js/pwa-install.js',

  // Key Icons (ensure all manifest icons + apple-touch are here)
  '/assets/logo180.webp', // Main logo
  '/assets/logo120.webp', // Smaller logo
  '/assets/android-chrome-192x192.png',
  '/assets/android-chrome-512x512.png',
  '/assets/apple-touch-icon.png',
  '/assets/favicon-32x32.png',
  '/assets/favicon-16x16.png'
];

// Install Service Worker
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('Opened cache and caching urls:', urlsToCache);
        return cache.addAll(urlsToCache);
      })
      .catch(err => {
        console.error('Failed to cache urls during install:', err, urlsToCache);
      })
  );
});

// Fetch event - serve from cache when offline
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const requestUrl = new URL(request.url);

  // Strategy: Cache first, falling back to network.
  // For specific assets (like main CSS), ignore query params when matching in cache.
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
        // Optional: Cache new successful GET requests if needed (not for MVP)
        return networkResponse;
      });
    }).catch(() => {
      if (request.mode === 'navigate') {
        return caches.match('/offline.html');
      }
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
            console.log('Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  return self.clients.claim(); // Ensure new SW takes control immediately
});
