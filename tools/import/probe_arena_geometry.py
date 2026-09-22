#!/usr/bin/env python3
"""One-off: read the LIVE PWA's arena geometry at contact.

`probe_arena.py` samples the state over time; this reads the LAYOUT the hero's
walk-in is projected onto — the arena box, the monster figure and the hero figure —
so the port's HERO_X_NEAR / HERO_Y_NEAR / size can be compared as numbers rather
than as percentages of an arena whose height nobody wrote down.

  python3 tools/import/probe_arena_geometry.py
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

EXPR = r"""
(() => {
  const r = (sel) => { const e = document.querySelector(sel); if (!e) return null;
    const b = e.getBoundingClientRect();
    return { x: +b.x.toFixed(1), y: +b.y.toFixed(1), w: +b.width.toFixed(1), h: +b.height.toFixed(1) }; };
  const fig = document.getElementById('mbPlayerFigure');
  return {
    arena: r('#mbArena'), figure: r('#mbFigure'), player: r('#mbPlayerFigure'),
    vw: window.innerWidth, vh: window.innerHeight,
    heroVars: fig ? { x: fig.style.getPropertyValue('--hero-x'),
                      y: fig.style.getPropertyValue('--hero-y'),
                      size: fig.style.getPropertyValue('--hero-size') } : null,
    gap: (window.mapBattleState && window.mapBattleState._gap !== undefined)
         ? +window.mapBattleState._gap.toFixed(3) : null,
  };
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


async def main(act, stop, seconds):
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

        async def evaluate(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        await evaluate("(() => { const c=document.querySelector('.class-card');"
                       " if(!c) return 'none'; c.click(); return 'ok'; })()")
        await asyncio.sleep(2)
        await evaluate(f"game.enterStop({act}, {stop})")
        await asyncio.sleep(seconds)
        print("at %.1fs:" % seconds, json.dumps(await evaluate(EXPR), ensure_ascii=False))


if __name__ == "__main__":
    a = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    st = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    sec = float(sys.argv[3]) if len(sys.argv) > 3 else 4.0
    asyncio.run(main(a, st, sec))
