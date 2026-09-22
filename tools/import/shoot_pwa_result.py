#!/usr/bin/env python3
"""Shoot the LIVE PWA's result page (`#resultScreen`) — the victory one or the defeat one.

The result page only exists at the END of a fight, so this drives a real fight and then
ends it the way a player does:

  * `win`  — kills the enemy's HP through the running fight loop.
  * `lose` — the PWA's own surrender route (`game.showSurrenderModal` +
    `game.confirmSurrender`), which is a real DEFEAT: death counter, consolation XP/gold,
    `areaFightProgress` reset, heal, `#resultScreen.centered`, defeat artwork, empty tiles
    and a page tap back to town. Nothing else reaches that branch, and `confirmSurrender`
    is the branch the player can actually take.

It prints the page's own geometry (`getBoundingClientRect` per element) next to the shot,
because "the defeat page is a black screen" is a LAYOUT claim and a PNG cannot say which
element lost its rect.

  python3 tools/import/shoot_pwa_result.py lose /tmp/pwa_result_lose.png
  python3 tools/import/shoot_pwa_result.py win  /tmp/pwa_result_win.png

Requires: `python3 -m http.server 8099` inside dist/, chromium on 9222.
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

# The page's own elements, in the PWA's own vocabulary. A missing one prints null rather
# than disappearing, so an element that stopped existing is visible in the output.
GEOMETRY = r"""
(() => {
  const r = (sel) => {
    const e = document.querySelector(sel);
    if (!e) return null;
    const b = e.getBoundingClientRect();
    const cs = getComputedStyle(e);
    return {x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height),
            fs: cs.fontSize, color: cs.color, disp: cs.display, pos: cs.position};
  };
  const txt = (sel) => { const e = document.querySelector(sel); return e ? e.textContent.trim().slice(0,80) : null; };
  return {
    visible: (() => { const e = document.getElementById('resultScreen');
                       return !!e && !e.classList.contains('hidden'); })(),
    centered: (() => { const e = document.getElementById('resultScreen');
                       return !!e && e.classList.contains('centered'); })(),
    screen: r('#resultScreen'), inner: r('#resultScreen .result-screen'),
    top: r('.result-top'), bottom: r('.result-bottom'),
    icon: r('#resultIcon'), iconImg: r('#resultIcon .result-icon-img'),
    defeatImg: r('#resultIcon img.large'),
    title: r('#resultTitle'), titleText: txt('#resultTitle'),
    msg: r('#resultMsg'), msgText: txt('#resultMsg'),
    status: r('#resultStatus'), loot: r('#resultLootList'), lootText: txt('#resultLootList'),
    actions: r('#resultActions'), tiles: document.querySelectorAll('.result-tile').length,
    tileLabels: Array.from(document.querySelectorAll('.result-tile-label')).map(e => e.textContent.trim()),
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


async def main(mode, out):
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

        cls = await evaluate("(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
                             " if (b) { b.click(); return 'card-handler'; }"
                             " try { game.selectClass('barbarian'); return 'selectClass()'; }"
                             " catch(e) { return 'ERR ' + e.message; } })()")
        await asyncio.sleep(1.0)
        kit = await evaluate("(() => { const s=JSON.parse(localStorage.getItem('dungeonRecallV7')||'{}');"
                             " return { cls: s.heroClass || '', maxHp: (s.hero||{}).maxHp }; })()")
        print("class ->", cls, kit)
        if not kit or kit.get("cls") != "barbarian" or int(kit.get("maxHp") or 0) <= 100:
            raise SystemExit("the class kit did not apply - refusing to shoot a level-1 hero's page")

        print("enterStop ->", await evaluate("(() => { game.enterStop(0, 0); return 'ok'; })()"))

        async def wait_until(expr, what, tries=24):
            for _ in range(tries):
                if await evaluate(expr):
                    return True
                await asyncio.sleep(0.5)
            raise SystemExit(f"timed out waiting for {what}")

        await wait_until("(() => { const t=(document.getElementById('mbHpLabel')||{}).textContent||'';"
                         " return t && !t.startsWith('0/'); })()", "the enemy to spawn")
        await wait_until("(() => { const f=document.getElementById('mbPlayerFigure');"
                         " return !!f && f.getBoundingClientRect().width > 0; })()",
                         "the hero sprite to render")

        if mode == "lose":
            # The player's own route to a defeat. `enterStop` starts the fight; the flag
            # asks for confirmation and the confirm IS the forfeit.
            await asyncio.sleep(1.0)
            print("surrender ->", await evaluate("(() => { game.showSurrenderModal(); return 'asked'; })()"))
            await asyncio.sleep(0.4)
            print("confirm   ->", await evaluate("(() => { game.confirmSurrender(); return 'confirmed'; })()"))
        else:
            # A WIN, through the fight's own attack handler. `mb` is module-private, so the
            # only honest way to zero the enemy is to keep hitting it: the arena's own click
            # handler is the player's attack and the fight resolves itself.
            await evaluate("(() => { const a=document.getElementById('mbArena'); return !!a; })()")
            clicks = 0
            for _ in range(300):
                await evaluate("(() => { const a=document.getElementById('mbArena');"
                               " if (a) a.click(); return 'hit'; })()")
                clicks += 1
                if await evaluate("(() => { const e=document.getElementById('resultScreen');"
                                  " return !!e && !e.classList.contains('hidden'); })()"):
                    break
                await asyncio.sleep(0.15)
            print("win -> arena clicks: %d" % clicks)
            await asyncio.sleep(0.6)   # let the 0.2 s bars and the loot list settle

        await wait_until("(() => { const e=document.getElementById('resultScreen');"
                         " return !!e && !e.classList.contains('hidden'); })()", "the result page")

        geo = await evaluate(GEOMETRY)
        print("geometry:", json.dumps(geo, ensure_ascii=False, indent=1))
        if not geo or not geo.get("visible"):
            raise SystemExit("the result page did not come up - refusing to save a frame of the arena")

        save = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
        with open(out, "wb") as fh:
            fh.write(base64.b64decode(save["data"]))
        print("shot:", out)


if __name__ == "__main__":
    m = sys.argv[1] if len(sys.argv) > 1 else "lose"
    o = sys.argv[2] if len(sys.argv) > 2 else "/tmp/pwa_result.png"
    asyncio.run(main(m, o))
