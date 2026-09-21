#!/usr/bin/env python3
"""Shoot the PWA (Dungeon Recall web build) at 390x844 over CDP — the reference generator.

The PWA's CSS is the specification for the Godot port, so every screen the port draws
needs a real reference frame. This drives the real dist/ build in headless Chromium.

  python3 tools/import/shoot_pwa.py                # all screens
  python3 tools/import/shoot_pwa.py town chest     # only these

Requires: `python3 -m http.server 8099` inside the PWA's dist/, and chromium on
--remote-debugging-port=9222.

WHY THIS IS NOT `game.showScreen('hero')`:
`inventory`, `talents` and `hero` are NOT screens in the PWA. `showScreen()` routes all
three into `openModal()`, which renders ONE modal and always opens it on the Inventory
tab — so `showScreen('hero')` produced a frame of the Inventory tab, and the old version
of this script recorded that as `hero.png`. The Skills and Stats tabs therefore had no
reference at all. The modal tabs are `.combined-tab`; click those to reach them.
"""

import asyncio
import base64
import json
import os
import sys
import time
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "reference", "pwa"))

# screen key -> JS that puts the game into that state. `game` is exposed on window.
# classSelect has no nav entry; the class card must be clicked, and it must be clicked
# AFTER the splash screen (2.5 s) or `showScreen` bounces back to classSelect.
SCREENS = {
    "town": "game.showScreen('town')",
    "map": "game.showScreen('map')",
    "chest": "game.showScreen('chest')",
    "shop": "game.showScreen('shop')",
    "gamble": "game.showScreen('gamble')",
    "craft": "game.showScreen('craft')",
    "bestiary": "game.showScreen('bestiary')",
    "spellbook": "game.showScreen('spellbook')",
}

# The three tabs of the ONE modal that the PWA calls inventory / talents / hero.
MODAL_TABS = {
    "inventory": "Inventory",
    "talents": "Skills",
    "hero": "Stats",
}


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(names):
    os.makedirs(OUT_DIR, exist_ok=True)
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
                return {"__error__": str(r["exceptionDetails"])[:200]}
            return r.get("result", {}).get("value")

        # Pick the barbarian AFTER the splash: the class card is the only way in
        # (selectClass is not exposed on window.game) and without a class every
        # showScreen() bounces back to classSelect.
        for _ in range(15):
            ok = await evaluate(
                "(() => { const c = document.querySelector('.class-card');"
                " if (!c) return 'no-card';"
                " const r = c.getBoundingClientRect();"
                " return r.width > 0 ? 'ready' : 'hidden'; })()"
            )
            if ok == "ready":
                break
            await asyncio.sleep(0.5)
        clicked = await evaluate(
            "(() => { const c = document.querySelector('.class-card');"
            " if (!c) return 'no-class-card'; c.click(); return 'clicked'; })()"
        )
        print("class:", clicked)
        await asyncio.sleep(2)

        async def shot(name):
            # The PWA scrolls to 0 on some transitions; a scrolled shot is not reference.
            await evaluate("window.scrollTo(0,0); document.documentElement.scrollTop = 0;")
            await asyncio.sleep(0.6)
            s = await send(ws, nxt(), "Page.captureScreenshot",
                           {"captureBeyondViewport": False})
            path = os.path.join(OUT_DIR, f"{name}.png")
            with open(path, "wb") as fh:
                fh.write(base64.b64decode(s["data"]))
            h = await evaluate("document.documentElement.scrollHeight")
            print(f"{name}: {path} (page height {h})")

        for name in names:
            if name in SCREENS:
                await evaluate(SCREENS[name])
                await asyncio.sleep(1.2)
                await shot(name)
            elif name in MODAL_TABS:
                # openModal() always lands on Inventory; then click the wanted tab.
                # Click by INDEX, not by label: the label lookup matched the badge span
                # for "Skills" and the click was swallowed, so talents.png came out
                # byte-identical to inventory.png while printing "tab-ok". Assert the
                # active class actually moved before shooting.
                index = list(MODAL_TABS.keys()).index(name)
                ok = await evaluate(
                    "(() => { game.showScreen('inventory');"
                    " const tabs=[...document.querySelectorAll('.combined-tab')];"
                    f" if (tabs.length < {index + 1}) return 'only ' + tabs.length + ' tabs';"
                    f" tabs[{index}].click();"
                    " const again=[...document.querySelectorAll('.combined-tab')];"
                    f" return again[{index}].classList.contains('active') ? 'active-ok' : 'NOT-ACTIVE';"
                    " })()"
                )
                print(f"{name}: tab #{index} -> {ok}")
                if ok != "active-ok":
                    print(f"{name}: SKIPPED — the tab did not activate")
                    continue
                await asyncio.sleep(1.2)
                await shot(name)
            else:
                print(f"skip {name}: unknown screen")


if __name__ == "__main__":
    want = sys.argv[1:] or (list(SCREENS.keys()) + list(MODAL_TABS.keys()))
    asyncio.run(main(want))
