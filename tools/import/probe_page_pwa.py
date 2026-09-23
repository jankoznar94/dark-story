#!/usr/bin/env python3
"""Measure the LIVE PWA's map / town / result page geometry — the numbers the port must match.

  python3 tools/import/probe_page_pwa.py map
  python3 tools/import/probe_page_pwa.py town
  python3 tools/import/probe_page_pwa.py result-win
  python3 tools/import/probe_page_pwa.py result-lose
  python3 tools/import/probe_page_pwa.py map-expanded

Why a second probe next to `probe_pwa.py`: these three pages carry the port's remaining
"buttons are crammed together / stacked differently" reports, and a percentage diff cannot
say WHICH rect is off. Everything printed here is `getBoundingClientRect` plus
`getComputedStyle`, i.e. what the browser actually laid out, not an estimate.

Requires: `python3 -m http.server 8099` inside the PWA's dist/, chromium on 9222.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

# One helper library, injected once, so every probe is short and reads the same.
HELPERS = r"""
window.__r = (sel) => {
  const e = document.querySelector(sel);
  if (!e) return null;
  const b = e.getBoundingClientRect();
  const s = getComputedStyle(e);
  return {x:+b.x.toFixed(1), y:+b.y.toFixed(1), w:+b.width.toFixed(1), h:+b.height.toFixed(1),
          disp:s.display, pos:s.position, pad:s.padding, mar:s.margin, gap:s.gap,
          bg:s.backgroundColor, bgImg:(s.backgroundImage||'').slice(0,90),
          bd:s.border, radius:s.borderRadius, opacity:s.opacity, filter:s.filter,
          color:s.color, fs:s.fontSize, fw:s.fontWeight, txt:(e.textContent||'').trim().slice(0,40)};
};
window.__rs = (sel) => [...document.querySelectorAll(sel)].map(e => {
  const b = e.getBoundingClientRect();
  const s = getComputedStyle(e);
  return {x:+b.x.toFixed(1), y:+b.y.toFixed(1), w:+b.width.toFixed(1), h:+b.height.toFixed(1),
          bg:s.backgroundColor, bd:s.border, radius:s.borderRadius, fs:s.fontSize,
          pad:s.padding, mar:s.margin, txt:(e.textContent||'').trim().slice(0,26)};
});
window.__actcard = (i) => {
  const loc = document.querySelectorAll('.map-location')[i];
  if (!loc) return null;
  const info = loc.querySelector('.map-loc-info');
  const badge = loc.querySelector('.map-loc-badge');
  const bg = loc.querySelector('.map-loc-bg');
  const gate = loc.querySelector('.map-loc-gate');
  const box = (e) => { if (!e) return null; const b = e.getBoundingClientRect();
    const s = getComputedStyle(e);
    return {x:+b.x.toFixed(1), y:+b.y.toFixed(1), w:+b.width.toFixed(1), h:+b.height.toFixed(1),
            bg:s.backgroundColor, bgImg:(s.backgroundImage||'').slice(0,80),
            bgSize:s.backgroundSize, bgPos:s.backgroundPosition, bgRepeat:s.backgroundRepeat,
            opacity:s.opacity, radius:s.borderRadius, z:s.zIndex}; };
  return {card: box(loc), cls: loc.className, info: box(info), badge: box(badge),
          badgeTxt: badge ? badge.textContent.trim() : null,
          bg: box(bg), gate: box(gate)};
};
window.__map = () => ({
  screen: window.__r('#mapScreen'),
  container: window.__r('#mapScreen .container') || window.__r('#mapScreen'),
  scroll: window.__r('#mapScroll'),
  diffs: window.__rs('.diff-selector .diff-btn'),
  selector: window.__r('.diff-selector'),
  card0: window.__actcard(0),
  card1: window.__actcard(1),
  wraps: window.__rs('.map-location-wrap'),
  actions: window.__r('.map-actions'),
  actionBtns: window.__rs('.map-actions .map-action-btn'),
  stops: window.__rs('.stop-card'),
  stopLabels: window.__rs('.stop-label'),
  arrows: window.__rs('.stop-arrow'),
  badges: window.__rs('.stop-badge'),
  dots: window.__rs('.map-loc-dot-scroll'),
  path: window.__r('.map-loc-dot-scroll'),
  wrapOpen: window.__r('.map-loc-dot-scroll-wrap'),
});
window.__town = () => ({
  screen: window.__r('#townScreen'),
  scroll: window.__r('#townScroll'),
  banner: window.__r('#townScreen .page-header'),
  kids: [...document.querySelectorAll('#townScroll > *')].map(e => {
    const b = e.getBoundingClientRect();
    return {cls: e.className.toString().slice(0,40), x:+b.x.toFixed(1), y:+b.y.toFixed(1),
            w:+b.width.toFixed(1), h:+b.height.toFixed(1), txt:(e.textContent||'').trim().slice(0,30)};
  }),
  tiles: window.__rs('#townScreen .town-tile, #townScreen .town-tiles > *'),
  btns: window.__rs('#townScreen button'),
});
window.__result = () => ({
  screen: window.__r('#resultScreen'),
  top: window.__r('.result-top'),
  bottom: window.__r('.result-bottom'),
  actions: window.__r('.result-actions'),
  tiles: window.__rs('.result-tile'),
  tileImgs: window.__rs('.result-tile-img'),
  tileLabels: window.__rs('.result-tile-label'),
  icon: window.__r('#resultIcon'),
  defeatImg: window.__r('#resultIcon img.large'),
  title: window.__r('#resultTitle'),
  msg: window.__r('#resultMsg'),
  loot: window.__r('#resultLootList'),
});
"""


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(what):
    targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=64 * 1024 * 1024) as ws:
        mid = 0

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4)

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:400]}
            return r.get("result", {}).get("value")

        await ev(HELPERS)
        # A class MUST exist: the hero sprite and the save's kits both hang off it.
        await ev("(() => { const c = document.querySelector('button[onclick*=\"selectClass\"]')"
                 " || document.querySelector('.class-card'); if (c) c.click(); return 'ok'; })()")
        await asyncio.sleep(2)

        if what.startswith("result"):
            lose = what.endswith("lose")
            await ev("game.enterStop(0, 0)")
            await asyncio.sleep(3)
            if lose:
                await ev("game.showSurrenderModal(); game.confirmSurrender();")
            else:
                await ev("(() => { const a = document.getElementById('mbArena');"
                         " let n = 0; while (!document.getElementById('resultScreen')"
                         " || document.getElementById('resultScreen').classList.contains('hidden'))"
                         " { a.click(); if (++n > 400) break; } return n; })()")
            await asyncio.sleep(1)
            print(json.dumps(await ev("window.__result()"), indent=1, ensure_ascii=False))
            return

        if what == "town":
            await ev("game.showScreen('town')")
            await asyncio.sleep(1)
            print(json.dumps(await ev("window.__town()"), indent=1, ensure_ascii=False))
            return

        await ev("game.showScreen('map')")
        await asyncio.sleep(1)
        if what == "map-expanded":
            await ev("game.toggleActExpand(0)")
            await asyncio.sleep(1)
        print(json.dumps(await ev("window.__map()"), indent=1, ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "map"))
