#!/usr/bin/env python3
"""Ask the LIVE PWA what is actually visible — which elements are painted, and where.

  python3 tools/import/_ask.py hero

`shoot_pwa.py` proves what the reference frames ARE; this proves what the PWA was
DRAWN as. Use it when a diff band says "these rows differ" and the CSS does not settle
which of the two is right: `getBoundingClientRect` + `getComputedStyle` answer it, and a
PNG cannot (an anti-aliased edge is not a real edge).
"""

import asyncio
import json
import sys
import urllib.request

import websockets

CDP_PORT = 9222

# What puts the PWA into the state the frame is shot in — same JS shoot_pwa.py runs.
ENTRY = {
    "town": "game.showScreen('town')",
    "map": "game.showScreen('map')",
    "chest": "game.showScreen('chest')",
    "shop": "game.showScreen('shop')",
    "gamble": "game.showScreen('gamble')",
    "craft": "game.showScreen('craft')",
    "bestiary": "game.showScreen('bestiary')",
    "spellbook": "game.showScreen('spellbook')",
    "inventory": "game.showScreen('inventory')",
    "talents": "game.showScreen('inventory'); [...document.querySelectorAll('.combined-tab')][1].click()",
    "hero": "game.showScreen('inventory'); [...document.querySelectorAll('.combined-tab')][2].click()",
}

# What to report once the PWA is in that state.
REPORT = """
(() => {
  const out = {};
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return {x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width),
            h: Math.round(r.height), bg: cs.backgroundColor, op: cs.opacity,
            z: cs.zIndex, disp: cs.display, vis: cs.visibility};
  };
  out.screen_containers = [...document.querySelectorAll('.container')].map(e => ({
      id: e.id, ...box(e), vis: getComputedStyle(e).visibility,
      op: getComputedStyle(e).opacity}));
  out.overlay = box(document.querySelector('.modal-overlay'));
  out.overlay_hidden = document.querySelector('.modal-overlay')
      ? document.querySelector('.modal-overlay').classList.contains('hidden') : null;
  out.modal = box(document.querySelector('.modal-content'));
  out.nav = box(document.querySelector('.nav-bar'));
  out.nav_hidden = document.querySelector('.nav-bar')
      ? document.querySelector('.nav-bar').classList.contains('hidden') : null;
  out.nav_active = [...document.querySelectorAll('.nav-bar a')]
      .map(a => (a.classList.contains('active') ? 'ACTIVE:' : '-') +
                (a.dataset.screen || a.id || a.textContent.trim().slice(0, 6)));
  // which screen the router thinks is showing
  out.active_screens = [...document.querySelectorAll('.screen, [id$="Screen"]')]
      .filter(e => getComputedStyle(e).display !== 'none')
      .map(e => e.id).slice(0, 12);
  // a coarse vertical colour profile of the viewport, so the PNG can be tied to elements
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


async def main(name):
    targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"],
                                  max_size=64 * 1024 * 1024) as ws:
        mid = 0

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": "http://127.0.0.1:8099/index.html"})
        await asyncio.sleep(4)

        async def evaluate(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        for _ in range(15):
            ok = await evaluate(
                "(() => { const c = document.querySelector('.class-card');"
                " if (!c) return 'no-card';"
                " return c.getBoundingClientRect().width > 0 ? 'ready' : 'hidden'; })()")
            if ok == "ready":
                break
            await asyncio.sleep(0.5)
        await evaluate("(() => { const c = document.querySelector('.class-card');"
                       " if (c) c.click(); return 'clicked'; })()")
        await asyncio.sleep(2)
        await evaluate("window.scrollTo(0,0)")
        await evaluate(ENTRY[name])
        await asyncio.sleep(1.5)
        res = await evaluate(REPORT)
        print(json.dumps(res, indent=2))


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
