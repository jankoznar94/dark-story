// Dark Story service worker — split caches so a code-only deploy does not
// re-download the 39 MB wasm engine.
//
// Godot's stock worker keys ONE cache by a build timestamp, so every deploy
// invalidates everything including index.wasm. Here the wasm lives in its own
// cache keyed by the wasm's CONTENT HASH, which does not change unless the
// engine itself changes.
//
// e10ff44d2ebab2cc and fc74679e3b97f768 are filled in at build time by
// tools/patch_web_sw.py.

const CODE_VERSION = 'e10ff44d2ebab2cc';
const ASSET_VERSION = 'fc74679e3b97f768';

const CODE_PREFIX = 'dark-story-code-';
const ASSET_PREFIX = 'dark-story-wasm-';

const CODE_CACHE = CODE_PREFIX + CODE_VERSION;
const ASSET_CACHE = ASSET_PREFIX + ASSET_VERSION;

const OFFLINE_URL = 'index.offline.html';
const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true;

// Small files: cheap to refetch, so they follow the code version.
const CODE_FILES = [
	"index.html",
	"index.js",
	"index.pck",
	"index.offline.html",
	"index.icon.png",
	"index.apple-touch-icon.png",
	"index.audio.worklet.js",
	"index.audio.position.worklet.js",
];
// The big one. Cached on first load, then kept across code deploys.
const ASSET_FILES = ["index.wasm"];

const ALL_FILES = CODE_FILES.concat(ASSET_FILES);

self.addEventListener('install', (event) => {
	// Only the small code files are pre-cached; the wasm is fetched on first
	// load so installing an update never costs 39 MB of mobile data.
	event.waitUntil(caches.open(CODE_CACHE).then((cache) => cache.addAll(CODE_FILES)));
});

self.addEventListener('activate', (event) => {
	event.waitUntil(
		caches.keys().then(function (keys) {
			return Promise.all(
				keys
					.filter(function (key) {
						// Drop superseded CODE caches, and only those WASM caches
						// whose content hash no longer matches the current engine.
						const staleCode = key.startsWith(CODE_PREFIX) && key !== CODE_CACHE;
						const staleAsset = key.startsWith(ASSET_PREFIX) && key !== ASSET_CACHE;
						return staleCode || staleAsset;
					})
					.map(function (key) {
						return caches.delete(key);
					})
			);
		}).then(function () {
			return ('navigationPreload' in self.registration)
				? self.registration.navigationPreload.enable()
				: Promise.resolve();
		})
	);
});

/** @param {Response} response */
function ensureCrossOriginIsolationHeaders(response) {
	if (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'
		&& response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin') {
		return response;
	}
	const headers = new Headers(response.headers);
	headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
	headers.set('Cross-Origin-Opener-Policy', 'same-origin');
	return new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers: headers,
	});
}

function cacheNameFor(local) {
	if (ASSET_FILES.indexOf(local) !== -1) {
		return ASSET_CACHE;
	}
	if (CODE_FILES.indexOf(local) !== -1) {
		return CODE_CACHE;
	}
	return null;
}

async function fetchAndCache(event, cache, cacheable) {
	let response = await event.preloadResponse;
	if (response == null) {
		response = await self.fetch(event.request);
	}
	if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
		response = ensureCrossOriginIsolationHeaders(response);
	}
	if (cacheable) {
		cache.put(event.request, response.clone());
	}
	return response;
}

self.addEventListener(
	'fetch',
	/** @param {FetchEvent} event */
	(event) => {
		const isNavigate = event.request.mode === 'navigate';
		const url = event.request.url || '';
		const referrer = event.request.referrer || '';
		const base = referrer.slice(0, referrer.lastIndexOf('/') + 1);
		const local = url.startsWith(base) ? url.replace(base, '') : '';
		const wanted = cacheNameFor(local);

		if (isNavigate || wanted !== null) {
			event.respondWith((async () => {
				const name = wanted !== null ? wanted : CODE_CACHE;
				const cache = await caches.open(name);

				if (isNavigate) {
					// Need the whole set present before we can go cache-first on
					// navigation, otherwise a first-ever visit would break.
					const present = await Promise.all(
						ALL_FILES.map((f) => caches.match(f).then((r) => r || null))
					);
					if (present.some((r) => r === null)) {
						try {
							return await fetchAndCache(event, cache, wanted !== null);
						} catch (e) {
							console.error('Network error: ', e); // eslint-disable-line no-console
							return caches.match(OFFLINE_URL);
						}
					}
				}

				let cached = await cache.match(event.request);
				if (cached == null && name !== CODE_CACHE) {
					// an asset cached under the other cache name
					cached = await caches.match(event.request);
				}
				if (cached != null) {
					return ENSURE_CROSSORIGIN_ISOLATION_HEADERS
						? ensureCrossOriginIsolationHeaders(cached)
						: cached;
				}
				return await fetchAndCache(event, cache, wanted !== null);
			})());
		} else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
			event.respondWith((async () => {
				let response = await fetch(event.request);
				return ensureCrossOriginIsolationHeaders(response);
			})());
		}
	}
);

self.addEventListener('message', (event) => {
	if (event.origin !== self.origin) {
		return;
	}
	const id = event.source.id || '';
	const msg = event.data || '';
	self.clients.get(id).then(function (client) {
		if (!client) {
			return;
		}
		if (msg === 'claim') {
			self.skipWaiting().then(() => self.clients.claim());
		} else if (msg === 'clear') {
			caches.delete(CODE_CACHE);
			caches.delete(ASSET_CACHE);
		} else if (msg === 'update') {
			self.skipWaiting()
				.then(() => self.clients.claim())
				.then(() => self.clients.matchAll())
				.then((all) => all.forEach((c) => c.navigate(c.url)));
		}
	});
});
