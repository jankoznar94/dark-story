#!/usr/bin/env python3
"""Watch the LIVE PWA's arena over time — the mechanical truth for the port.

The port's arena must reproduce the PWA's COMBAT, not just its pixels. This drives a
real fight in the reference build and samples the DOM every tick, so "hero has the
wrong HP / no mana / swing timers do not tick" becomes a number instead of an
impression.

  python3 tools/import/probe_arena.py            # act 1, stop 1, 8 s
  python3 tools/import/probe_arena.py 1 3 12     # act 1, stop 3, 12 s

Requires: `python3 -m http.server 8099` inside the PWA's dist/, chromium on
--remote-debugging-port=9222 (same prerequisites as shoot_pwa.py).
"""

import asyncio
import json
import sys
import time
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

SAMPLE = r"""
(() => {
  const t = (sel) => { const e = document.querySelector(sel); return e ? e.textContent.trim() : null; };
  const off = (id) => { const e = document.getElementById(id); return e ? Math.round(+e.style.strokeDashoffset || 0) : null; };
  const w = (sel) => { const e = document.querySelector(sel); return e ? e.style.width : null; };
  const fig = document.getElementById('mbPlayerFigure');
  const fr = fig ? fig.getBoundingClientRect() : null;
  return {
    screen: [...document.querySelectorAll('.screen')].filter(s => s.classList.contains('active')).map(s => s.id)[0] || '?',
    heroHp: t('#mbPlayerArenaHp span'),
    mana: t('#mbPlayerArenaMana span'),
    manaVisible: (() => { const e = document.getElementById('mbPlayerArenaMana'); return e ? !e.classList.contains('hidden') : null; })(),
    hpFillW: w('#mbPlayerArenaHpFill'),
    manaFillW: w('#mbPlayerArenaManaFill'),
    enemyHp: t('#mbHpLabel'),
    enemyName: t('#mbEnemyName'),
    enemyManaVis: (() => { const e = document.getElementById('mbEnemyManaBar'); return e ? !e.classList.contains('hidden') : null; })(),
    cPlayer: off('mbPlayerTimerCircle'),
    cOffhand: off('mbOffhandTimerCircle'),
    cEnemy: off('mbEnemyTimerCircle'),
    offhandOpacity: (() => { const e = document.getElementById('mbOffhandTimerCircle'); return e ? e.style.opacity : null; })(),
    heroX: fr ? +fr.x.toFixed(1) : null,
    heroY: fr ? +fr.y.toFixed(1) : null,
    heroCls: fig ? fig.className : null,
    comboDots: document.querySelectorAll('.mb-combo-dot').length,
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
        errors = []

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Log.enable")
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

        # Console errors arrive as events, not replies — drain them between sends.
        async def drain_events():
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=0.01)
            except Exception:
                return
            msg = json.loads(raw)
            if msg.get("method") in ("Runtime.consoleAPICalled", "Log.entryAdded"):
                params = msg.get("params", {})
                text = json.dumps(params)[:200]
                if '"error"' in text or '"warning"' in text or 'error' in text.lower():
                    errors.append(text)

        await evaluate("(() => { const c=document.querySelector('.class-card');"
                       " if(!c) return 'none'; c.click(); return 'ok'; })()")
        await asyncio.sleep(2)

        entered = await evaluate(f"(() => {{ try {{ game.enterStop({act}, {stop}); return 'ok'; }}"
                                 " catch (e) { return 'ERR ' + e.message; } })()")
        print(f"enterStop({act}, {stop}) -> {entered}")
        await asyncio.sleep(2.5)

        samples = []
        deadline = time.time() + seconds
        while time.time() < deadline:
            s = await evaluate(SAMPLE)
            s["t_ms"] = int((time.time() - (deadline - seconds)) * 1000)
            samples.append(s)
            await drain_events()
            await asyncio.sleep(0.1)

        for s in samples:
            print("t=%-5s screen=%-12s heroHp=%-10s mana=%-10s manavis=%-5s hpW=%-7s manaW=%-7s"
                  " enemyHp=%-9s cPl=%-5s cOff=%-5s cEn=%-5s offOp=%-4s heroX=%-6s heroY=%-6s cls=%s"
                  % (s["t_ms"], s["screen"], s["heroHp"], s["mana"], s["manaVisible"], s["hpFillW"],
                     s["manaFillW"], s["enemyHp"], s["cPlayer"], s["cOffhand"], s["cEnemy"],
                     s["offhandOpacity"], s["heroX"], s["heroY"], s["heroCls"]))
        print("first:", json.dumps(samples[0], ensure_ascii=False))
        print("errors:", len(errors))
        for e in errors[:5]:
            print("  ", e)


if __name__ == "__main__":
    a = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    st = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    sec = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
    asyncio.run(main(a, st, sec))
