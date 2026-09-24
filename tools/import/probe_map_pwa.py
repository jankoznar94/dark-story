#!/usr/bin/env python3
"""Probe the live PWA's map screen in depth: the act cards and the EXPANDED act's stop cards.

Jan's report (Sept 2026): "on the map page the area images still do not display correctly.
About 70 % of the image is normally coloured, the bottom 30 % is black-and-white."

That is a per-card vertical split, so this probe measures SATURATION PER ROW BAND inside
each `.map-location` card and each `.stop-card`, and prints each element's rect plus its
computed filter/opacity/mix-blend so the band's owner is unambiguous. It also lists
window.game's keys, because the expand route (`toggleActExpand`) is not documented.

  python3 tools/import/probe_map_pwa.py

Requires the same rig as shoot_pwa.py: `python3 -m http.server 8099` in the PWA's dist/
and chromium on --remote-debugging-port=9222.
"""
import asyncio
import base64
import json
import sys
import urllib.request

import websockets

CDP_PORT = 9222
URL = "http://127.0.0.1:8099/index.html"

JS = r"""
(() => {
  const out = {cards: [], stops: []};
  const measure = (el, label) => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return {label, cls: String(el.className).slice(0, 40),
            rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
            filter: cs.filter, opacity: cs.opacity,
            bg: cs.backgroundColor, bgImage: cs.backgroundImage.slice(0, 70),
            bgSize: cs.backgroundSize, bgRepeat: cs.backgroundRepeat,
            blend: cs.mixBlendMode, isolation: cs.isolation};
  };
  document.querySelectorAll('.map-location').forEach((el, i) => out.cards.push(measure(el, 'loc' + i)));
  document.querySelectorAll('.map-location-wrap').forEach((el, i) => out.cards.push(measure(el, 'wrap' + i)));
  document.querySelectorAll('.map-loc-bg').forEach((el, i) => out.cards.push(measure(el, 'bg' + i)));
  document.querySelectorAll('.map-loc-gate').forEach((el, i) => out.cards.push(measure(el, 'gate' + i)));
  document.querySelectorAll('.map-loc-info').forEach((el, i) => out.cards.push(measure(el, 'info' + i)));
  document.querySelectorAll('.stop-wrap').forEach((el, i) => out.stops.push(measure(el, 'stopwrap' + i)));
  document.querySelectorAll('.stop-card').forEach((el, i) => out.stops.push(measure(el, 'stopcard' + i)));
  document.querySelectorAll('.stop-card img, .stop-img, .stop-card > div').forEach((el, i) => out.stops.push(measure(el, 'stopchild' + i)));
  return out;
})()
"""


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main():
    targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=64 * 1024 * 1024) as ws:
        mid = 0

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        async def evaluate(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Network.setCacheDisabled", {"cacheDisabled": True})
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4)
        for _ in range(15):
            if await evaluate("document.querySelector('.class-card') ? 'yes' : 'no'") == "yes":
                break
            await asyncio.sleep(0.5)
        print("class click:", await evaluate(
            "(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
            " if (b) { b.click(); return 'card-handler'; }"
            " try { game.selectClass('barbarian'); return 'selectClass()'; }"
            " catch(e) { return 'ERR ' + e.message; } })()"))
        await asyncio.sleep(1.5)
        print("kit:", await evaluate(
            "(() => { const s=JSON.parse(localStorage.getItem('dungeonRecallV7')||'{}');"
            " return {cls: s.heroClass||'', maxHp:(s.hero||{}).maxHp}; })()"))
        await evaluate("game.showScreen('map')")
        await asyncio.sleep(1.2)
        print("=== COLLAPSED ===")
        print(json.dumps(await evaluate(JS), indent=1))

        print("expand:", await evaluate(
            "(() => { try { game.toggleActExpand(0); return 'toggleActExpand(0)'; }"
            " catch(e) { return 'ERR ' + e.message; } })()"))
        await asyncio.sleep(1.5)
        print("=== EXPANDED ===")
        print(json.dumps(await evaluate(JS), indent=1))
        print("stop count:", await evaluate("document.querySelectorAll('.stop-card').length"))
        for band in (0, 200, 400, 700):
            await evaluate(f"document.documentElement.scrollTop = {band};"
                           " window.dispatchEvent(new Event('scroll'));")
            await asyncio.sleep(0.5)
            s = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
            with open(f"/tmp/pwa_map_exp_{band}.png", "wb") as fh:
                fh.write(base64.b64decode(s["data"]))
            print("shot ->", f"/tmp/pwa_map_exp_{band}.png",
                  "scrollTop", await evaluate("document.documentElement.scrollTop"))


asyncio.run(main())
