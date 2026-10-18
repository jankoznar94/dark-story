#!/usr/bin/env python3
"""Dokonci PWA export po Godotu: manifest pro Android + service worker, ktery
se opravdu aktivuje a opravdu servíruje novou verzi.

Prevzato z hry Zily (vetev `ley-lines`), kde vsechny ty veci staly jedno kolo
praxe. Rozdil je jediny: hra je na VYSKU, takze se orientace v manifestu
vynucuje natvrdo a stranka se zamyka na portrait.

Ctyri problemy, ktere se v praxi projevily:

1) MANIFEST. Godot generuje jen minimum poli a Androidu (WebAPK) to nestaci -
   chce short_name, theme_color, id, scope a hlavne ikonu 192x192, kterou
   export vubec neumi (umi jen 144/180/512).
2) SERVICE WORKER V `install`. Godot nevola skipWaiting(), takze nova verze
   zustane ve stavu "waiting" a aktivuje se, az se zavrou VSECHNY panely
   stranky. U nainstalovane PWA to nejde.
3) SERVICE WORKER VE `fetch`. Navigace se vyrizuje CACHE-FIRST, takze stary
   index.html z cache prebije novy ze site - hrac zustane na stare hre.
   Navigace MUSI byt network-first, offline rezim zustava jako zaloha.
4) CACHE_VERSION. Kdyz se pri novem nasazení nezmeni, prohlizec novy worker
   vubec nezaregistruje (bajtove stejny soubor = zadna zmena).

Skript je idempotentni.

Pouziti: python3 tools/fix_pwa_export.py build/web [otisk-commitu]
"""
import json
import os
import re
import shutil
import sys

ICON_192_SRC = "icons/icon_192.png"
ICON_192_DST = "index.192x192.png"

# Znacka, podle ktere poznáme, ze navigace uz je network-first.
NAV_MARK = "NAVIGACE JE VZDY ZE SITE"

# Orientace se NEPREBIRA z exportniho presetu: ciselnik toho nastaveni je
# v kazde verzi Godotu jiny a spatna hodnota se projevi jen tim, ze se PWA
# spusti na sirku (coz je u teto hry necitelna plocha). Zapisuje se proto
# natvrdo jako retezec.
ORIENTATION = "portrait"

# Hra je na VYSKU. Orientace se zamyka na strance, ne jen v manifestu:
# prohlizec pouzije manifest jen ve chvili spusteni nainstalovane aplikace,
# behem nacitani enginu se orientace vraci k senzoru. Kdyz displej zustane
# na sirku, je dole tenky pruh s jednou vetou - zadna podlozka pres hru,
# hra je hratelna i tak, jen je plocha mensi a barvy hur citelne.
PORTRAIT_MARK = "ZILY_NA_VYSKU"

# KONTROLA VERZE NA STRANCE. Service worker i network-first navigace jsou ve
# SW, ale prohlizec muze drzet STARY index.html i stary worker (a u
# nainstalovane PWA se to nema jak spravit samo). Hrac pak hlasi "porad je to
# stejne", i kdyz je novy build na serveru. Stranka proto po nacteni porovna
# svuj otisk s `version.txt`; kdyz se lisi, smaze cache, odregistruje workera
# a JEDNOU se reloadne (podruhe uz ne - `sessionStorage` brani smycce).
UPDATE_MARK = "VERZE_SE_KONTROLUJE"

UPDATE_JS = """
\t<!-- VERZE_SE_KONTROLUJE: stara verze v prohlizeci se sama ozve. -->
\t<script>
\t(function () {
\t  var BUILT = '__VER__';
\t  if (!('serviceWorker' in navigator)) { return; }
\t  try {
\t    navigator.serviceWorker.getRegistrations().then(function (rs) {
\t      rs.forEach(function (r) { r.update(); });
\t    });
\t  } catch (e) {}
\t  if (!BUILT) { return; }
\t  fetch('version.txt?ts=' + Date.now(), { cache: 'no-store' })
\t    .then(function (r) { return r.text(); })
\t    .then(function (v) {
\t      v = (v || '').trim();
\t      if (!v || v === BUILT) { return; }
\t      if (sessionStorage.getItem('zily_reload') === v) { return; }
\t      sessionStorage.setItem('zily_reload', v);
\t      var done = function () { location.reload(); };
\t      if (window.caches && caches.keys) {
\t        caches.keys().then(function (ks) {
\t          return Promise.all(ks.map(function (k) { return caches.delete(k); }));
\t        }).then(function () {
\t          return navigator.serviceWorker.getRegistrations();
\t        }).then(function (rs) {
\t          return Promise.all(rs.map(function (r) { return r.unregister(); }));
\t        }).then(done, done);
\t      } else { done(); }
\t    })
\t    .catch(function () {});
\t}());
\t</script>
"""

PORTRAIT_JS = """
\t<!-- ZILY_NA_VYSKU: hra je na vysku, orientace se drzi tady, ne jen v manifestu. -->
\t<style>
\t  #zily_vyska { display: none; position: fixed; left: 0; right: 0; bottom: 0;
\t    z-index: 2147483647; background: #14120f; color: #e8e2d4;
\t    font: 14px/1.5 sans-serif; text-align: center; padding: 8px 12px; }
\t  body.zily_landscape #zily_vyska { display: block; }
\t</style>
\t<div id="zily_vyska">Hraje se na výšku — otoč telefon.</div>
\t<script>
\t(function () {
\t  function landscape() { return window.innerWidth > window.innerHeight; }
\t  function lock() {
\t    try {
\t      if (screen.orientation && screen.orientation.lock) {
\t        var p = screen.orientation.lock('portrait');
\t        if (p && p.catch) { p.catch(function () {}); }
\t      }
\t    } catch (e) {}
\t  }
\t  function refresh() {
\t    if (document.body) {
\t      document.body.classList.toggle('zily_landscape', landscape());
\t    }
\t  }
\t  window.addEventListener('resize', refresh);
\t  window.addEventListener('orientationchange', refresh);
\t  document.addEventListener('pointerdown', function () { lock(); refresh(); }, { passive: true });
\t  lock();
\t  refresh();
\t}());
\t</script>
"""

# Cely listener 'fetch' se nahrazuje jako celek. Kdysi se tu patchoval po
# castech a vznikla z toho neplatna syntaxe - u generovaneho souboru se
# vyplati vymenit cely blok, ne v nem hledat radky.
FETCH_BLOCK = """self.addEventListener(
\t'fetch',
\t/**
\t * Triggered on fetch
\t * @param {FetchEvent} event
\t */
\t(event) => {
\t\tconst isNavigate = event.request.mode === 'navigate';
\t\tconst url = event.request.url || '';
\t\tconst referrer = event.request.referrer || '';
\t\tconst base = referrer.slice(0, referrer.lastIndexOf('/') + 1);
\t\tconst local = url.startsWith(base) ? url.replace(base, '') : '';
\t\tconst isCacheable = FULL_CACHE.some((v) => v === local) || (base === referrer && base.endsWith(CACHED_FILES[0]));
\t\tif (isNavigate || isCacheable) {
\t\t\tevent.respondWith((async () => {
\t\t\t\t// Try to use cache first
\t\t\t\tconst cache = await caches.open(CACHE_NAME);
\t\t\t\tif (isNavigate) {
\t\t\t\t\t// %s. Godot tu mel cache-first, takze
\t\t\t\t\t// hrac po nasazeni nove verze dostal stary index.html a z menu se
\t\t\t\t\t// dozvedel stary otisk buildu - hra vypadala, ze se neaktualizovala.
\t\t\t\t\t// Kdyz sit neni, spadneme na cache a pak na offline stranku.
\t\t\t\t\ttry {
\t\t\t\t\t\tconst fresh = await fetch(event.request);
\t\t\t\t\t\tif (fresh && fresh.ok) {
\t\t\t\t\t\t\tcache.put(event.request, fresh.clone());
\t\t\t\t\t\t\treturn fresh;
\t\t\t\t\t\t}
\t\t\t\t\t} catch (e) {
\t\t\t\t\t\tconsole.error('Network error: ', e); // eslint-disable-line no-console
\t\t\t\t\t}
\t\t\t\t\tconst cachedPage = await cache.match(event.request);
\t\t\t\t\tif (cachedPage != null) {
\t\t\t\t\t\treturn cachedPage;
\t\t\t\t\t}
\t\t\t\t\treturn caches.match(OFFLINE_URL);
\t\t\t\t}
\t\t\t\tlet cached = await cache.match(event.request);
\t\t\t\tif (cached != null) {
\t\t\t\t\tif (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
\t\t\t\t\t\tcached = ensureCrossOriginIsolationHeaders(cached);
\t\t\t\t\t}
\t\t\t\t\treturn cached;
\t\t\t\t}
\t\t\t\t// Try network if don't have it in cache.
\t\t\t\tconst response = await fetchAndCache(event, cache, isCacheable);
\t\t\t\treturn response;
\t\t\t})());
\t\t} else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
\t\t\tevent.respondWith((async () => {
\t\t\t\tlet response = await fetch(event.request);
\t\t\t\tresponse = ensureCrossOriginIsolationHeaders(response);
\t\t\t\treturn response;
\t\t\t})());
\t\t}
\t}
);
""" % NAV_MARK


def fix_manifest(out: str) -> bool:
	mf = os.path.join(out, "index.manifest.json")
	if not os.path.isfile(mf):
		print("PWA_MANIFEST=fail (chybi %s)" % mf)
		return False
	with open(mf, "r", encoding="utf-8") as f:
		m = json.load(f)

	# Android pouziva short_name jako popisek pod ikonou.
	m.setdefault("short_name", m.get("name", "Zily 2"))
	# id musi byt stabilni a v ramci origin; bez nej si prohlizec muze myslet,
	# ze jde o jinou aplikaci, a nabidnout reinstalaci.
	m.setdefault("id", "./")
	m.setdefault("scope", "./")
	m.setdefault("theme_color", m.get("background_color", "#1a1816"))
	m.setdefault("prefer_related_applications", False)
	m.setdefault("categories", ["games"])
	m["orientation"] = ORIENTATION

	src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ICON_192_SRC)
	if os.path.isfile(src):
		shutil.copyfile(src, os.path.join(out, ICON_192_DST))
		icons = m.setdefault("icons", [])
		if not any(i.get("sizes") == "192x192" for i in icons):
			icons.append({"sizes": "192x192", "src": ICON_192_DST, "type": "image/png"})
		icons.sort(key=lambda i: int(str(i.get("sizes", "0x0")).split("x")[0]))
	else:
		print("PWA_MANIFEST=warn (chybi %s)" % ICON_192_SRC)

	# purpose "any" je pro instalaci povinny; maskable zamerne NEDAVAME -
	# ikona je ctverec a maskable by ho oriznul.
	for i in m.get("icons", []):
		i.setdefault("purpose", "any")

	with open(mf, "w", encoding="utf-8") as f:
		json.dump(m, f, ensure_ascii=False)

	need = ["name", "short_name", "start_url", "display", "theme_color",
		"background_color", "id", "scope", "orientation", "icons"]
	missing = [k for k in need if not m.get(k)]
	sizes = [i.get("sizes") for i in m.get("icons", [])]
	if missing or "192x192" not in sizes or "512x512" not in sizes:
		print("PWA_MANIFEST=fail missing=%s sizes=%s" % (missing, sizes))
		return False
	if m["orientation"] != ORIENTATION:
		print("PWA_MANIFEST=fail orientation=%s" % m["orientation"])
		return False
	print("PWA_MANIFEST=ok orientation=%s sizes=%s" % (m["orientation"], sizes))
	return True


def fix_service_worker(out: str, version: str = "") -> bool:
	sw = os.path.join(out, "index.service.worker.js")
	if not os.path.isfile(sw):
		print("PWA_SW=fail (chybi %s)" % sw)
		return False
	with open(sw, "r", encoding="utf-8") as f:
		src = f.read()

	# 1) install: hned po naskladani cache se novy worker chytne rizeni.
	old_install = "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));"
	new_install = ("event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES))"
		".then(() => self.skipWaiting()));")
	if old_install in src:
		src = src.replace(old_install, new_install)
	elif "self.skipWaiting()" not in src:
		print("PWA_SW=fail (nepodarilo se najit install handler)")
		return False

	# 2) activate: prevezmi i otevrene stranky, aby nova verze platila hned.
	old_act = "return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();"
	new_act = (old_act + "\n\t\t}).then(function () {\n"
		"\t\t\treturn self.clients.claim();")
	if old_act in src and "self.clients.claim()" not in src.split("self.addEventListener('activate'")[-1][:1500]:
		src = src.replace(old_act, new_act)

	# 3) NAVIGACE network-first. Vymenime cely listener 'fetch' jako blok.
	if NAV_MARK not in src:
		a = src.index("self.addEventListener(\n\t'fetch',")
		b = src.index("self.addEventListener('message'")
		if not (0 < a < b):
			print("PWA_SW=fail (nepodarilo se najit fetch listener)")
			return False
		src = src[:a] + FETCH_BLOCK + "\n" + src[b:]

	# 4) CACHE_VERSION = otisk buildu.
	versioned = False
	if version:
		src, n = re.subn(r"const CACHE_VERSION = '[^']*';",
			"const CACHE_VERSION = '%s';" % version, src, count=1)
		if n != 1:
			print("PWA_SW=fail (nepodarilo se najit CACHE_VERSION)")
			return False
		versioned = True

	with open(sw, "w", encoding="utf-8") as f:
		f.write(src)

	ok = "self.skipWaiting()" in src and NAV_MARK in src
	if versioned and ("CACHE_VERSION = '%s'" % version) not in src:
		ok = False
	if not ok:
		print("PWA_SW=fail skipWaiting=%s networkFirst=%s"
			% ("self.skipWaiting()" in src, NAV_MARK in src))
		return False
	m = re.search(r"const CACHE_VERSION = '([^']*)';", src)
	print("PWA_SW=ok cacheVersion=%s skipWaiting=true networkFirst=true claim=%s"
		% (m.group(1) if m else "?", "self.clients.claim()" in src))
	return True


def fix_index_html(out: str, version: str = "") -> bool:
	"""Vlozi do index.html zamceni orientace a kontrolu verze.

	Idempotentni: podle znacek PORTRAIT_MARK a UPDATE_MARK se pozná, ze uz je
	hotovo (druhy beh nic nezdvoji).
	"""
	html = os.path.join(out, "index.html")
	if not os.path.isfile(html):
		print("PWA_HTML=fail (chybi %s)" % html)
		return False
	with open(html, "r", encoding="utf-8") as f:
		src = f.read()
	if PORTRAIT_MARK not in src:
		if "</body>" not in src:
			print("PWA_HTML=fail (v index.html neni </body>)")
			return False
		src = src.replace("</body>", PORTRAIT_JS + "\t</body>", 1)
		with open(html, "w", encoding="utf-8") as f:
			f.write(src)
	if UPDATE_MARK not in src:
		if "</body>" not in src:
			print("PWA_HTML=fail (v index.html neni </body>)")
			return False
		src = src.replace("</body>", UPDATE_JS.replace("__VER__", version) + "\t</body>", 1)
		with open(html, "w", encoding="utf-8") as f:
			f.write(src)
	# Kontrola je na to, co se opravdu pise do souboru.
	missing = [m for m in [PORTRAIT_MARK, 'id="zily_vyska"',
		"screen.orientation.lock('portrait')", UPDATE_MARK, "version.txt"] if m not in src]
	if missing:
		print("PWA_HTML=fail missing=%s" % missing)
		return False
	print("PWA_HTML=ok (orientace se drzi na strance)")
	return True


def main() -> int:
	out = sys.argv[1] if len(sys.argv) > 1 else "build/web"
	version = sys.argv[2] if len(sys.argv) > 2 else ""
	ok_m = fix_manifest(out)
	ok_s = fix_service_worker(out, version)
	ok_h = fix_index_html(out, version)
	if not (ok_m and ok_s and ok_h):
		print("FIX_PWA_EXPORT=false")
		return 1
	print("FIX_PWA_EXPORT=true")
	return 0


if __name__ == "__main__":
	sys.exit(main())
