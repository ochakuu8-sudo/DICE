// Caches the engine payload (index.wasm, index.js, and the font packed
// inside index.pck's own dependencies are NOT cached here — only files
// that never change between deploys) so a repeat visit skips the ~10MB
// wasm download entirely. index.pck holds the actual game — it changes
// on every deploy — so it is always fetched fresh from the network and
// never served from this cache.
//
// Bump CACHE_NAME whenever a file in CACHED_ASSETS changes (e.g. a Godot
// re-export produces a new index.wasm) so old clients pick up the new
// version instead of serving a stale cached copy forever.
const CACHE_NAME = 'dice-engine-v2';
const CACHED_ASSETS = [
	'index.wasm',
	'index.js',
	'index.audio.worklet.js',
];

self.addEventListener('install', (event) => {
	event.waitUntil(
		caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_ASSETS))
	);
	self.skipWaiting();
});

self.addEventListener('activate', (event) => {
	event.waitUntil(
		caches.keys().then((names) => Promise.all(
			names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name))
		))
	);
	self.clients.claim();
});

self.addEventListener('fetch', (event) => {
	const url = new URL(event.request.url);
	if (url.pathname.endsWith('.pck')) {
		// GitHub Pages sends static files with a ten-minute browser cache.
		// The pack is the game itself, so force a fresh request on every load.
		event.respondWith(fetch(event.request, { cache: 'no-store' }));
		return;
	}
	const isCachedAsset = CACHED_ASSETS.some((asset) => url.pathname.endsWith('/' + asset));
	if (!isCachedAsset) {
		// index.pck and everything else: normal network fetch, never
		// intercepted, so a new deploy is always seen immediately.
		return;
	}
	event.respondWith(
		caches.match(event.request).then((cached) => {
			if (cached) {
				return cached;
			}
			return fetch(event.request).then((response) => {
				if (response.ok) {
					const copy = response.clone();
					caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
				}
				return response;
			});
		})
	);
});
