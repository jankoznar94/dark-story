#!/usr/bin/env python3
"""Dokonci PWA export po Godotu: manifest pro Android + service worker,
ktery se opravdu aktivuje a opravdu servíruje novou verzi.

Ctyri problemy, ktere se v praxi projevily (vsechny staly jedno kolo):

1) MANIFEST. Godot generuje jen minimum poli a Androidu (WebAPK) to nestaci -
   chce short_name, theme_color, id, scope a hlavne ikonu 192x192, kterou
   export vubec neumi (umi jen 144/180/512). Bez tech poli Chrome na Androidu
   nabidne jen zkratku ("Create shortcut"), pripadne se tvari, ze aplikace
   uz je nainstalovana.

2) SERVICE WORKER V `install`. Godot nevola skipWaiting(), takze nova verze
   zustane ve stavu "waiting" a aktivuje se, az se zavrou VSECHNY panely
   stranky. U nainstalovane PWA to nejde - hrac zustane navzdy na stare hre.

3) SERVICE WORKER VE `fetch`. Navigace se vyrizuje CACHE-FIRST: stary
   index.html z cache prebije novy ze site. Nova hra se stahne, ale stránka
   zustane stara - hrac vidi stary otisk buildu a ma dojem, ze se nic
   neaktualizovalo. Navigace MUSI byt network-first, offline rezim zustava
   jen jako zaloha.

4) CACHE_VERSION. Godot do ni zapisuje cas a velikost (napr. '1791557816|2245815').
   Kdyz se pri novem nasazení NEZMENI, prohlizec novy worker vubec nezaregistruje
   (bajtove stejny soubor = zadna zmena), takze hrac dostane starou hru.
   Skript proto umi CACHE_VERSION prepnout na otisk commitu.

Skript je idempotentni - kdyz jsou zmeny uz aplikovane, nic nezkazi.

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

# Cely listener 'fetch' se nahrazuje jako celek. Kdysi se tu patchoval po
# castech a vznikla z toho neplatna syntaxe - u generovaneho souboru se
# vyplati vymenit celý blok, ne v nem hledat radky.
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
	m.setdefault("short_name", m.get("name", "Zily"))
	# id musi byt stabilni a v ramci origin; bez nej si prohlizec muze myslet,
	# ze jde o jinou aplikaci, a nabidnout reinstalaci.
	m.setdefault("id", "./")
	m.setdefault("scope", "./")
	m.setdefault("theme_color", m.get("background_color", "#1a1816"))
	m.setdefault("prefer_related_applications", False)
	m.setdefault("categories", ["games"])

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
	# ikona je ctverec na ctyri ctvrty a maskable by ho oriznul.
	for i in m.get("icons", []):
		i.setdefault("purpose", "any")

	with open(mf, "w", encoding="utf-8") as f:
		json.dump(m, f, ensure_ascii=False)

	need = ["name", "short_name", "start_url", "display", "theme_color",
		"background_color", "id", "scope", "icons"]
	missing = [k for k in need if not m.get(k)]
	sizes = [i.get("sizes") for i in m.get("icons", [])]
	if missing or "192x192" not in sizes or "512x512" not in sizes:
		print("PWA_MANIFEST=fail missing=%s sizes=%s" % (missing, sizes))
		return False
	print("PWA_MANIFEST=ok sizes=%s" % sizes)
	return True


def fix_service_worker(out: str, version: str = "") -> bool:
	sw = os.path.join(out, "index.service.worker.js")
	if not os.path.isfile(sw):
		print("PWA_SW=fail (chybi %s)" % sw)
		return False
	with open(sw, "r", encoding="utf-8") as f:
		src = f.read()

	# 1) install: hned po naskladani cache se novy worker chytne rizeni.
	#    Bez skipWaiting() ceka na zavreni vsech panelu, coz u PWA nejde.
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

	# 3) NAVIGACE network-first. Vymenime cely listener 'fetch' jako blok -
	#    carkovani po radcich u generovaneho souboru vedlo k rozbite syntaxi.
	if NAV_MARK not in src:
		a = src.index("self.addEventListener(\n	'fetch',")
		b = src.index("self.addEventListener('message'")
		if not (0 < a < b):
			print("PWA_SW=fail (nepodarilo se najit fetch listener)")
			return False
		src = src[:a] + FETCH_BLOCK + "\n" + src[b:]

	# 4) CACHE_VERSION = otisk buildu. Bez zmeny tohohle retezce prohlizec
	#    novou verzi service workera vubec nezaregistruje.
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


def main() -> int:
	out = sys.argv[1] if len(sys.argv) > 1 else "build/web"
	version = sys.argv[2] if len(sys.argv) > 2 else ""
	ok_m = fix_manifest(out)
	ok_s = fix_service_worker(out, version)
	if not (ok_m and ok_s):
		print("FIX_PWA_EXPORT=false")
		return 1
	print("FIX_PWA_EXPORT=true")
	return 0


if __name__ == "__main__":
	sys.exit(main())
