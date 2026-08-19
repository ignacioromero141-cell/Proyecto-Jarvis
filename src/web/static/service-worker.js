const JARVIS_CACHE = "jarvis-pwa-v24-phase0-backup";

const APP_SHELL = [
  "./",
  "./index.html",
  "./finance.html",
  "./organization.html",
  "./study.html",
  "./calendar.html",
  "./wellbeing.html",
  "./work.html",
  "./personal.html",
  "./settings.html",
  "./backup-compare.html",
  "./backup-sandbox.html",
  "./manifest.webmanifest",
  "./jarvis-theme.css",
  "./jarvis-local-store.js",
  "./jarvis-backup.js",
  "./jarvis-shared.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/apple-touch-icon.png",
  "./icons/icon.svg",
  "./icons/maskable.svg"
];

function scopeUrl(path) {
  return new URL(path, self.registration.scope).href;
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(JARVIS_CACHE)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== JARVIS_CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);

  if (url.origin !== self.location.origin) return;
  if (url.pathname.includes("/api/")) return;
  // Los datos privados y las copias seleccionadas por el usuario nunca forman
  // parte del app shell. Solo se cachean recursos publicos de la aplicacion.
  if (!["document", "script", "style", "image", "manifest", "font"].includes(request.destination)) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(JARVIS_CACHE).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || caches.match(scopeUrl("./index.html"))))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request).then((response) => {
      const copy = response.clone();
      caches.open(JARVIS_CACHE).then((cache) => cache.put(request, copy));
      return response;
    }))
  );
});
