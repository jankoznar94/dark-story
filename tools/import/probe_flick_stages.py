#!/usr/bin/env python3
"""Localise the flick: does the page scroll at ALL, does the DRAG move it, does it COAST?

    python3 tools/import/diag_flick.py

Three questions, one gesture each, so a failure can be attributed instead of guessed:

  1. WHEEL: `gui_input`'s wheel branch runs before any deadzone logic, so a wheel notch proves
     the page is scrollable and where its range is. If the wheel moves nothing, the page cannot
     scroll and the flick question is meaningless.
  2. DRAG (frames sampled DURING the finger's movement): proves the driver is live and the page
     follows the finger. `motion()` between consecutive frames.
  3. AFTER THE LIFT: proves the coast.

`motion()` is the mean absolute pixel difference between consecutive frames: it needs no
landmark and cannot saturate (the previous landmark-based probe reported a confident "no
momentum" from a saturated reading).
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets
from PIL import Image

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


async def shoot(ws, nxt, path):
    r = await send(ws, nxt(), "Page.captureScreenshot", {"format": "png"})
    with open(path, "wb") as fh:
        fh.write(base64.b64decode(r["data"]))
    return path


def motion(a_path, b_path, region=(0, 40, 390, 700)):
    a = Image.open(a_path).convert("L").crop(region)
    b = Image.open(b_path).convert("L").crop(region)
    pa, pb = a.load(), b.load()
    w, h = a.size
    total = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            total += abs(pa[x, y] - pb[x, y])
    return total / float((w // 2) * (h // 2))


async def touch(ws, nxt, kind, x=None, y=None):
    pts = [{"x": x, "y": y, "id": 1}] if kind != "touchEnd" else []
    await send(ws, nxt(), "Input.dispatchTouchEvent", {"type": kind, "touchPoints": pts})


async def main():
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
        await send(ws, nxt(), "Network.enable")
        await send(ws, nxt(), "Network.setCacheDisabled", {"cacheDisabled": True})
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Emulation.setTouchEmulationEnabled",
                   {"enabled": True, "maxTouchPoints": 1})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        for _ in range(60):
            await asyncio.sleep(1)
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": "!!(window.engine && window.engine.canvas)",
                            "returnByValue": True})
            if r.get("result", {}).get("value"):
                break
        await asyncio.sleep(7)

        # The 3rd nav entry ("bestiary") — a long list, unlike the town's 56 px.
        await touch(ws, nxt, "touchStart", 126, 813)
        await asyncio.sleep(0.06)
        await touch(ws, nxt, "touchEnd")
        await asyncio.sleep(3)
        base = await shoot(ws, nxt, "/tmp/df_base.png")

        # 1) WHEEL — can this page scroll at all?
        print("== 1. can it scroll at all? (wheel, which bypasses every deadzone) ==")
        prev = base
        for i in range(3):
            await send(ws, nxt(), "Input.dispatchMouseEvent",
                       {"type": "mouseWheel", "x": 195, "y": 400, "deltaX": 0, "deltaY": 120})
            await asyncio.sleep(0.6)
            cur = await shoot(ws, nxt, f"/tmp/df_wheel{i}.png")
            print(f"  wheel notch {i + 1}: frame changed by {motion(prev, cur):7.2f}")
            prev = cur
        after_wheel = prev

        # 2) DRAG — sample frames WHILE the finger moves.
        print()
        print("== 2. does a DRAG move it? (frames taken during the movement) ==")
        await touch(ws, nxt, "touchStart", 195, 640)
        prev = after_wheel
        for i in range(10):
            await touch(ws, nxt, "touchMove", 195, 640 - 16.0 * (i + 1))
            await asyncio.sleep(0.03)
            cur = await shoot(ws, nxt, f"/tmp/df_drag{i}.png")
            print(f"  drag step {i + 1:2d}: frame changed by {motion(prev, cur):7.2f}")
            prev = cur

        # 3) THE LIFT — frames with NO finger on the screen.
        print()
        print("== 3. after the LIFT, is it still moving? ==")
        await touch(ws, nxt, "touchEnd")
        for i in range(10):
            cur = await shoot(ws, nxt, f"/tmp/df_lift{i}.png")
            print(f"  +{i * 100:4d} ms after the lift: frame changed by {motion(prev, cur):7.2f}")
            prev = cur
            await asyncio.sleep(0.1)

        print()
        print("READING: wheel 0 everywhere = the page cannot scroll from here (wrong screen or")
        print("         no range). drag 0 = the driver is not moving the page. lift > 0 with")
        print("         decaying steps = momentum.")


if __name__ == "__main__":
    asyncio.run(main())
