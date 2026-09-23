#!/usr/bin/env python3
"""Drive the PORT's own WEB build in a real browser and measure the scroll.

  python3 tools/import/probe_port_web.py scroll
  python3 tools/import/probe_port_web.py touch

Why a browser and not `--headless`: the web build is the build Jan plays, and the two
things reported about scrolling live in the browser only —

  * `DisplayServer.is_touchscreen_available()` is `'ontouchstart' in window`, which is
    FALSE in a desktop browser and TRUE on a phone, so the page behaves differently in
    each. A headless Godot run is a third case again.
  * `gui/common/drop_mouse_on_gui_input_disabled` / the touch emulation decide whether a
    TOUCH arrives at `Control._gui_input` as a mouse event at all.

Measures with real CDP input events at real coordinates, so what comes back is what a
finger does, not what a synthetic `push_input` does.
"""

import asyncio
import json
import sys
import time
import urllib.request

import websockets

URL = "http://127.0.0.1:8100/index.html"
CDP_PORT = 9222


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def mouse(ws, nxt, kind, x, y, button="left", click_count=1):
    await send(ws, nxt(), "Input.dispatchMouseEvent",
               {"type": kind, "x": x, "y": y, "button": button,
                "buttons": 1 if kind != "mouseReleased" else 0,
                "clickCount": click_count})


async def main(what):
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
        await send(ws, nxt(), "Emulation.setTouchEmulationEnabled",
                   {"enabled": what == "touch", "maxTouchPoints": 1})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        # The wasm is 40 MB and the engine has to boot; give it room.
        for _ in range(60):
            await asyncio.sleep(1)
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": "!!(window.engine && window.engine.canvas)",
                            "returnByValue": True})
            if r.get("result", {}).get("value"):
                break
        await asyncio.sleep(6)

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        # What the port THINKS its environment is. This alone decides which scroll path
        # is live, and it is the number no Godot-side test can report.
        print("canvas:", await ev("(() => { const c = document.querySelector('canvas');"
                                  " if (!c) return null; const b = c.getBoundingClientRect();"
                                  " return {w:c.width,h:c.height,css:[b.width,b.height],"
                                  " touch:'ontouchstart' in window}; })()"))

        # Click into the canvas first: Godot needs focus before it receives input.
        await mouse(ws, nxt, "mousePressed", 195, 400)
        await mouse(ws, nxt, "mouseReleased", 195, 400)
        await asyncio.sleep(4)
        print("shot0:", (await shot(ws, nxt, "/tmp/port_web_0.png")))

        # Reach the town: tap the first class card (the class screen is the boot screen).
        await mouse(ws, nxt, "mousePressed", 100, 300)
        await mouse(ws, nxt, "mouseReleased", 100, 300)
        await asyncio.sleep(3)
        print("shot1:", (await shot(ws, nxt, "/tmp/port_web_1.png")))

        if what == "touch":
            await send(ws, nxt(), "Input.dispatchTouchEvent",
                       {"type": "touchStart", "touchPoints":
                        [{"x": 195, "y": 600, "id": 1}]})
            for i in range(12):
                await send(ws, nxt(), "Input.dispatchTouchEvent",
                           {"type": "touchMove", "touchPoints":
                            [{"x": 195, "y": 600 - 12 * (i + 1), "id": 1}]})
                await asyncio.sleep(0.02)
            await send(ws, nxt(), "Input.dispatchTouchEvent",
                       {"type": "touchEnd", "touchPoints": []})
        else:
            await mouse(ws, nxt, "mousePressed", 195, 600)
            for i in range(12):
                await mouse(ws, nxt, "mouseMoved", 195, 600 - 12 * (i + 1))
                await asyncio.sleep(0.02)
            await mouse(ws, nxt, "mouseReleased", 195, 456)
        await asyncio.sleep(2)
        print("shot2 (after the drag):", (await shot(ws, nxt, "/tmp/port_web_2.png")))


async def shot(ws, nxt, path):
    r = await send(ws, nxt(), "Page.captureScreenshot", {"format": "png"})
    import base64
    with open(path, "wb") as fh:
        fh.write(base64.b64decode(r["data"]))
    return path


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "scroll"))
