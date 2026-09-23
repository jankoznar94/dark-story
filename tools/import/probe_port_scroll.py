#!/usr/bin/env python3
"""Does a drag actually move the port's page? Drive the WEB build and compare frames.

  python3 tools/import/probe_port_scroll.py

Jan's report: "scroll everywhere still behaves oddly. Jerky and irregular. Sometimes it works,
sometimes not. For example when I tap a button and want to scroll, it doesn't work at all. So I
have to hit somewhere where nothing is, which is sometimes a problem."

So the two cases are tested SEPARATELY — a drag that starts ON a tile and a drag that starts on
the empty background between tiles — because "it depends where I start" IS the bug.

A drag is judged by whether the CONTENT moved: the frames are compared row band by row band, and
a real scroll shows as the whole page shifted. Screenshot equality alone is not evidence (the
engine repaints a hover/animation and the frames differ either way).
"""

import asyncio
import base64
import json
import sys
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


async def shot(ws, mid_fn, path):
    r = await send(ws, mid_fn(), "Page.captureScreenshot", {"format": "png"})
    with open(path, "wb") as fh:
        fh.write(base64.b64decode(r["data"]))
    return path


async def drag(ws, nxt, x, y0, dy, steps=12, pause=0.02):
    """A real mouse drag: press, move up in steps, release."""
    await send(ws, nxt(), "Input.dispatchMouseEvent",
               {"type": "mousePressed", "x": x, "y": y0, "button": "left", "buttons": 1,
                "clickCount": 1})
    for i in range(steps):
        y = y0 - dy * (i + 1) / steps
        await send(ws, nxt(), "Input.dispatchMouseEvent",
                   {"type": "mouseMoved", "x": x, "y": y, "button": "left", "buttons": 1})
        await asyncio.sleep(pause)
    await send(ws, nxt(), "Input.dispatchMouseEvent",
               {"type": "mouseReleased", "x": x, "y": y0 - dy, "button": "left",
                "buttons": 0, "clickCount": 1})
    await asyncio.sleep(1.2)


def shift(a_path, b_path):
    """Vertical displacement between two frames, in pixels, by best row-correlation."""
    from PIL import Image
    a = Image.open(a_path).convert("L")
    b = Image.open(b_path).convert("L")
    w, h = a.size
    ap, bp = a.load(), b.load()
    # A band in the MIDDLE of the page, away from the nav bar and any animation.
    band = (200, 560)
    best, best_err = 0, None
    for d in range(-300, 301, 1):
        err, n = 0.0, 0
        for y in range(band[0], band[1], 4):
            yb = y - d
            if yb < 0 or yb >= h:
                continue
            for x in range(20, w - 20, 6):
                err += abs(ap[x, y] - bp[x, yb])
                n += 1
        if n == 0:
            continue
        err /= n
        if best_err is None or err < best_err:
            best_err, best = err, d
    return best, best_err


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
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        for _ in range(60):
            await asyncio.sleep(1)
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": "!!(window.engine && window.engine.canvas)",
                            "returnByValue": True})
            if r.get("result", {}).get("value"):
                break
        await asyncio.sleep(6)

        # Focus the canvas, then pick a class to reach the town (the boot screen).
        await send(ws, nxt(), "Input.dispatchMouseEvent",
                   {"type": "mousePressed", "x": 195, "y": 400, "button": "left",
                    "buttons": 1, "clickCount": 1})
        await send(ws, nxt(), "Input.dispatchMouseEvent",
                   {"type": "mouseReleased", "x": 195, "y": 400, "button": "left",
                    "buttons": 0, "clickCount": 1})
        await asyncio.sleep(4)
        await send(ws, nxt(), "Input.dispatchMouseEvent",
                   {"type": "mousePressed", "x": 100, "y": 300, "button": "left",
                    "buttons": 1, "clickCount": 1})
        await send(ws, nxt(), "Input.dispatchMouseEvent",
                   {"type": "mouseReleased", "x": 100, "y": 300, "button": "left",
                    "buttons": 0, "clickCount": 1})
        await asyncio.sleep(4)

        base = await shot(ws, nxt, "/tmp/scr_base.png")
        print("base:", base)

        reports = []
        # (a) drag starting ON a town tile (the grid button), (b) on the empty background
        # between tiles, (c) on the banner, (d) on an empty strip at the page's side.
        cases = [
            ("on a town tile",   100, 560),
            ("on the side gutter", 8, 560),
            ("on the banner art", 195, 200),
            ("on the bottom gap", 195, 700),
        ]
        for label, x, y in cases:
            before = await shot(ws, nxt, "/tmp/scr_before.png")
            await drag(ws, nxt, x, y, 240)
            after = await shot(ws, nxt, "/tmp/scr_after.png")
            d, err = shift(before, after)
            reports.append((label, x, y, d, err))
            print(f"  {label:22s} from ({x},{y}): content shifted {d:+4d} px (err {err:.1f})")
        print()
        for label, x, y, d, err in reports:
            verdict = "SCROLLED" if abs(d) >= 40 else "DID NOT MOVE"
            print(f"  {verdict:13s} {label}")


if __name__ == "__main__":
    asyncio.run(main())
