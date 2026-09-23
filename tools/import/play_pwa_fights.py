#!/usr/bin/env python3
"""Play real fights in the LIVE PWA and report what the result page and the bag show.

The static read says `rollLoot` is called on a win. Only a real fight says whether the
drops then reach the victory list and the inventory — which is the question.

  python3 tools/import/play_pwa_fights.py [fights]

Requires: `python3 -m http.server 8099` in the PWA's dist/, chromium on
--remote-debugging-port=9222.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(fights):
    targets = json.loads(urllib.request.urlopen("http://127.0.0.1:9222/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=64 * 1024 * 1024) as ws:
        mid = 0

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        await ev("localStorage.clear()")
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(6)
        await ev("(() => { window.game.selectClass('barbarian'); return true; })()")
        await asyncio.sleep(2)
        print("class set, level:", await ev(
            "(() => { const b = document.getElementById('mbPlayerArenaHp'); return b ? b.textContent : 'n/a'; })()"))

        for f in range(fights):
            await ev("(() => { window.game.enterStop(0, 0); return true; })()")
            await asyncio.sleep(3.0)
            taps = 0
            for _ in range(600):
                done = await ev(
                    "(() => { const r = document.getElementById('resultScreen');"
                    " return !!r && !r.classList.contains('hidden'); })()")
                if done:
                    break
                # The player's attack IS a tap on the arena's own click handler.
                await ev("(() => { const a = document.getElementById('mbArena');"
                         " if (a) a.dispatchEvent(new MouseEvent('click',"
                         " {bubbles:true, cancelable:true, view:window})); return true; })()")
                taps += 1
                await asyncio.sleep(0.02)
            print("fight %d (%d taps):" % (f, taps), await ev(
                "(() => { const r = document.getElementById('resultScreen');"
                " const l = document.getElementById('resultLootList');"
                " const img = document.querySelector('#resultIcon img');"
                " return JSON.stringify({shown: !!r && !r.classList.contains('hidden'),"
                " art: img ? img.getAttribute('src') : null,"
                " loot_rows: l ? l.querySelectorAll('.loot-scroll-item').length : -1,"
                " loot_text: l ? l.textContent.trim().slice(0,160) : null}); })()"))
            await ev("(() => { const r = document.getElementById('resultScreen');"
                     " if (r) r.click(); return true; })()")
            await asyncio.sleep(1.5)

        print("bag:", await ev(
            "(() => { const s = JSON.parse(localStorage.getItem('dungeonRecallSave') || '{}');"
            " return JSON.stringify({bag: (s.hero && s.hero.inventory || []).slice(0,12),"
            " gold: s.hero && s.hero.gold,"
            " lootItems: Object.keys(s.lootItems || {}).length,"
            " floorDrops: (s._floorLootDrops || []).length}); })()"))
        await ev("(() => { window.game.openModal('inventory'); return true; })()")
        await asyncio.sleep(1.5)


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 5))
