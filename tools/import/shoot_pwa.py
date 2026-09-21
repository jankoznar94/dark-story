#!/usr/bin/env python3
"""Shoot the PWA (Dungeon Recall web build) at 390x844 over CDP.

The PWA's CSS is the specification for the Godot port, so this is the reference
generator: it drives the real dist/ build in headless Chromium and writes one PNG per
screen into tools/reference/pwa/.

  python3 tools/import/shoot_pwa.py                     # all screens
  python3 tools/import/shoot_pwa.py town shop           # only these

Requires: a `python3 -m http.server 8099` inside the PWA's dist/ and chromium on PATH.
"""

import asyncio
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "reference", "pwa")

# screen key -> JS that puts the game into that state. `game` is exposed on window and
# has showScreen(); the class must be picked once (selectClass is NOT exposed).
SCREENS = {
    "town": "game.showScreen('town')",
    "map": "game.showScreen('map')",
    "chest": "game.showScreen('chest')",
    "shop": "game.showScreen('shop')",
    "gamble": "game.showScreen('gamble')",
    "craft": "game.showScreen('craft')",
    "inventory": "game.showScreen('inventory')",
    "hero": "game.showScreen('hero')",
    "talents": "game.showScreen('talents')",
    "bestiary": "game.showScreen('bestiary')",
    "spellbook": "game.showScreen('spellbook')",
    "classSelect": "game.showScreen('classSelect')",
}

MODAL_SCREENS = {"inventory", "hero", "talents"}


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
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride", {
            "width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True,
        })
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4)

        async def evaluate(expr):
            r = await send(ws, nxt(), "Runtime.evaluate", {
                "expression": expr, "returnByValue": True, "awaitPromise": True,
            })
            return r.get("result", {}).get("value")

        # Pick the barbarian: the class card is the only way in (selectClass is not
        # exposed on window.game), and without a class showScreen() bounces everything
        # back to classSelect.
        ok = await evaluate(
            "(() => { const c = document.querySelector('.class-card');"
            " if (!c) return 'no-class-card'; c.click(); return 'clicked'; })()"
        )
        print("class:", ok)
        await asyncio.sleep(2)

        for name in names:
            js = SCREENS.get(name)
            if js is None:
                print(f"skip {name}: unknown screen")
                continue
            await evaluate(js)
            # The PWA scrolls to 0 on some transitions; a scrolled shot is not reference.
            await evaluate("window.scrollTo(0,0); document.documentElement.scrollTop = 0;")
            await asyncio.sleep(1.2)
            shot = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
            path = os.path.join(OUT_DIR, f"{name}.png")
            with open(path, "wb") as fh:
                fh.write(base64.b64decode(shot["data"]))
            h = await evaluate("document.documentElement.scrollHeight")
            print(f"{name}: {path} (page height {h})")


if __name__ == "__main__":
    want = sys.argv[1:] or list(SCREENS.keys())
    asyncio.run(main(want))
