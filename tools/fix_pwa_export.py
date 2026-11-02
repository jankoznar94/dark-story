#!/usr/bin/env python3
"""Dokonci PWA export po Godotu: service worker, ktery opravdu servíruje novou
verzi, a otisk buildu vedle `index.html`.

Prevzato z her Zily 2 a Thrower (`tools/fix_pwa_export.py`), kde ty veci staly
jedno kolo praxe. Vyhozena je jen cast o manifestu a zamceni orientace - tady
se nic z toho nemeni.

Tri problemy, ktere se v praxi projevily:

1) SERVICE WORKER V `install`. Godot nevola skipWaiting(), takze nova verze
   zustane ve stavu "waiting" a aktivuje se, az se zavrou VSECHNY panely
   stranky. U nainstalovane PWA to nejde - hrac zustane na stare hre.
2) SERVICE WORKER VE `fetch`. Navigace i KOD HRY (index.pck / index.wasm) se
   vyrizuji CACHE-FIRST, takze stary pack z cache prebije novy ze site. Hrac
   v menu vidi novy otisk buildu a hra bezi stara.
3) CACHE_VERSION. Kdyz se pri novem nasazení nezmeni, prohlizec novy worker
   vubec nezaregistruje (bajtove stejny soubor = zadna zmena).

Ctvrtá vec je otisk: `version.txt` se cte s `no-store` a hra ho kresli do menu
jako "build xxxxxxx". Bez nej se neda poznat, jestli hrac po aktualizaci vidi
novou verzi, nebo mu ji jeste drzi cache.

Skript je idempotentni.

Pouziti: python3 tools/fix_pwa_export.py build/web [otisk-commitu]
"""
import os
import re
import sys

# Znacka, podle ktere poznáme, ze navigace uz je network-first.
NAV_MARK = "NAVIGACE JE VZDY ZE SITE"
# Znacka pro KOD HRY (index.pck / index.wasm). Bez ni zustane v prohlizeci
# stara hra i po nasazeni: cache-first na .pck znamena, ze se novy kod nikdy
# nestahne, dokud se cache nesmaze.
PCK_MARK = "KOD HRY JE VZDY ZE SITE"

# Cely listener 'fetch' se nahrazuje jako celek. Patchovat generovany soubor po
# castech znamena, ze z nej jednou vznikne neplatna syntaxe.
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
\t\t// KOD HRY JE VZDY ZE SITE: pozname ho PODLE CESTY, ne podle referreru.
\t\t// V nainstalovane PWA byva referrer prazdny, `local` pak vyjde jako
\t\t// cela URL, .pck se nepoznal a spadl do HTTP cache (GitHub Pages:
\t\t// max-age=600) - hrac jeste deset minut hraje starou hru.
\t\tlet isCode = false;
\t\ttry {
\t\t\tconst path = new URL(url).pathname;
\t\t\tisCode = path.endsWith('/index.pck') || path.endsWith('/index.wasm');
\t\t} catch (e) {
\t\t\tisCode = local === 'index.pck' || local === 'index.wasm';
\t\t}
\t\tif (isNavigate || isCode || isCacheable) {
\t\t\tevent.respondWith((async () => {
\t\t\t\t// Try to use cache first
\t\t\t\tconst cache = await caches.open(CACHE_NAME);
\t\t\t\tif (isNavigate || isCode) {
\t\t\t\t\t// %s. Godot tu mel cache-first, takze
\t\t\t\t\t// hrac po nasazeni nove verze dostal stary index.html a stary
\t\t\t\t\t// pack. Kdyz sit neni, spadneme na cache a pak na offline
\t\t\t\t\t// stranku.
\t\t\t\t\ttry {
\t\t\t\t\t\t// KOD HRY SE NESMI PTAT HTTP CACHE. GitHub Pages posila
\t\t\t\t\t\t// cache-control: max-age=600, takze jeste deset minut po
\t\t\t\t\t\t// nasazeni vratil prohlizec stary .pck.
\t\t\t\t\t\tconst fresh = await fetch(event.request, { cache: isCode ? 'no-store' : 'default' });
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
    old_act = ("return ('navigationPreload' in self.registration) ? "
               "self.registration.navigationPreload.enable() : Promise.resolve();")
    new_act = (old_act + "\n\t\t}).then(function () {\n"
               "\t\t\treturn self.clients.claim();")
    if old_act in src and "self.clients.claim()" not in src.split("self.addEventListener('activate'")[-1][:1800]:
        src = src.replace(old_act, new_act)

    # 3) navigace + kod hry network-first. Vymenime cely listener 'fetch'.
    if NAV_MARK not in src or PCK_MARK not in src:
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

    ok = "self.skipWaiting()" in src and NAV_MARK in src and PCK_MARK in src
    if versioned and ("CACHE_VERSION = '%s'" % version) not in src:
        ok = False
    if not ok:
        print("PWA_SW=fail skipWaiting=%s networkFirst=%s codeFirst=%s"
              % ("self.skipWaiting()" in src, NAV_MARK in src, PCK_MARK in src))
        return False
    m = re.search(r"const CACHE_VERSION = '([^']*)';", src)
    print("PWA_SW=ok cacheVersion=%s skipWaiting=true networkFirst=true codeNetworkFirst=true claim=%s"
          % (m.group(1) if m else "?", "self.clients.claim()" in src))
    return True


def write_version(out: str, version: str) -> bool:
    """`version.txt` lezi VEDLE index.html, takze ho service worker neobsahuje
    a hra si ho muze precist cerstvy (`cache: 'no-store'`)."""
    if not version:
        print("PWA_VERSION=skip (bez otisku)")
        return True
    path = os.path.join(out, "version.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(version)
    got = open(path, "r", encoding="utf-8").read().strip()
    if got != version:
        print("PWA_VERSION=fail wrote=%r" % got)
        return False
    print("PWA_VERSION=ok %s" % got)
    return True


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    version = sys.argv[2] if len(sys.argv) > 2 else ""
    ok_v = write_version(out, version)
    ok_s = fix_service_worker(out, version)
    if not (ok_v and ok_s):
        print("FIX_PWA_EXPORT=false")
        return 1
    print("FIX_PWA_EXPORT=true")
    return 0


if __name__ == "__main__":
    sys.exit(main())
