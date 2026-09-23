#!/usr/bin/env python3
"""Measure the port's PAGE SCROLL with real input, on BOTH platform profiles.

  python3 tools/import/probe_port_scroll.py

WHY THIS EXISTS
Jan plays on a PHONE. That matters more than anything else here, because the port has two
different scroll paths and the platform picks which one runs:

  * `scripts/ui/scroll_swipe.gd` drives the page by hand, but its FIRST statement is
        if DisplayServer.is_touchscreen_available(): return
    `is_touchscreen_available()` is `'ontouchstart' in window` on web — FALSE in a desktop
    browser, TRUE on a phone. So on the phone the driver stands down COMPLETELY and Godot's
    own `ScrollContainer` drag is what the player gets.
  * Godot's own drag lives in `ScrollContainer::gui_input` and only handles
    `InputEventMouseButton` / `InputEventMouseMotion` (there is NO ScreenTouch/ScreenDrag
    branch), so on a phone it works only through the touch->mouse emulation.

So the same gesture can take two different code paths, and a fix verified only in a desktop
browser proves nothing about the phone. This runs BOTH profiles through the same gesture and
compares.

HOW A DRAG IS JUDGED
Not by "did the screenshots differ" (an animation or a pressed-state pixel does that) and not
by a global correlation error (flat dark art makes many shifts score equally well, and a
rounded `err 0.0` hides that). It finds a HIGH-CONTRAST landmark — the banner's top edge — in
each frame's own column profile and reports the displacement. The landmark's own sharpness is
printed so a weak reading is visible instead of being trusted.
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


async def shot(ws, mid_fn, path):
    r = await send(ws, mid_fn(), "Page.captureScreenshot", {"format": "png"})
    with open(path, "wb") as fh:
        fh.write(base64.b64decode(r["data"]))
    return path


def landmark(path):
    """The y of the strongest horizontal edge in the upper half — the banner's own top.

    Returns (y, strength). A strength near 0 means the frame has no usable landmark and the
    reading must not be trusted.
    """
    im = Image.open(path).convert("L")
    w, h = im.size
    px = im.load()
    best_y, best_v = 0, -1.0
    for y in range(40, min(h - 60, 620)):
        s = 0.0
        for x in range(20, w - 20, 3):
            s += abs(px[x, y + 2] - px[x, y - 2])
        s /= float((w - 40) // 3)
        if s > best_v:
            best_v, best_y = s, y
    return best_y, best_v


def shift(a_path, b_path):
    ya, sa = landmark(a_path)
    yb, sb = landmark(b_path)
    return yb - ya, sa, sb, ya, yb


async def drag_touch(ws, nxt, x, y0, dy, steps=14):
    await send(ws, nxt(), "Input.dispatchTouchEvent",
               {"type": "touchStart", "touchPoints": [{"x": x, "y": y0, "id": 1}]})
    for i in range(steps):
        await send(ws, nxt(), "Input.dispatchTouchEvent",
                   {"type": "touchMove",
                    "touchPoints": [{"x": x, "y": y0 - dy * (i + 1) / steps, "id": 1}]})
        await asyncio.sleep(0.02)
    await send(ws, nxt(), "Input.dispatchTouchEvent",
               {"type": "touchEnd", "touchPoints": []})
    await asyncio.sleep(1.2)


async def drag_mouse(ws, nxt, x, y0, dy, steps=14):
    await send(ws, nxt(), "Input.dispatchMouseEvent",
               {"type": "mousePressed", "x": x, "y": y0, "button": "left",
                "buttons": 1, "clickCount": 1})
    for i in range(steps):
        await send(ws, nxt(), "Input.dispatchMouseEvent",
                   {"type": "mouseMoved", "x": x, "y": y0 - dy * (i + 1) / steps,
                    "button": "left", "buttons": 1})
        await asyncio.sleep(0.02)
    await send(ws, nxt(), "Input.dispatchMouseEvent",
               {"type": "mouseReleased", "x": x, "y": y0 - dy, "button": "left",
                "buttons": 0, "clickCount": 1})
    await asyncio.sleep(1.2)


async def run(ws, nxt, profile):
    """Boot the engine, reach the town, and drag from four places. Returns a report list."""
    await send(ws, nxt(), "Page.navigate", {"url": URL})
    for _ in range(60):
        await asyncio.sleep(1)
        r = await send(ws, nxt(), "Runtime.evaluate",
                       {"expression": "!!(window.engine && window.engine.canvas)",
                        "returnByValue": True})
        if r.get("result", {}).get("value"):
            break
    await asyncio.sleep(6)

    # Focus the canvas and pick a class (the class screen is the boot screen).
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

    env = await send(ws, nxt(), "Runtime.evaluate",
                     {"expression": "({touch:'ontouchstart' in window,"
                                    " points:navigator.maxTouchPoints})",
                      "returnByValue": True})
    print(f"  env: {env.get('result', {}).get('value')}")

    cases = [("on a town tile", 100, 560), ("side gutter", 8, 560),
             ("banner art", 195, 200), ("bottom gap", 195, 700)]
    out = []
    print("  NOTE: the town has only ~56px of scroll on a 390x844 canvas, so the FIRST case")
    print("        exhausts it and every case after it reads 0 for lack of anything to move,")
    print("        not because the drag was refused. The case that matters is the first.")
    for label, x, y in cases:
        before = await shot(ws, nxt, f"/tmp/scr_{profile}_before.png")
        if profile == "touch":
            await drag_touch(ws, nxt, x, y, 240)
        else:
            await drag_mouse(ws, nxt, x, y, 240)
        after = await shot(ws, nxt, f"/tmp/scr_{profile}_after.png")
        d, sa, sb, ya, yb = shift(before, after)
        out.append((label, d, sa, sb, ya, yb))
        print(f"  {label:16s} landmark y {ya:3d} -> {yb:3d}  shift {d:+4d} "
              f"(edge strength {sa:.1f}/{sb:.1f})")
    return out


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
        # A Godot web export ships a PWA service worker and caches `index.pck`. Without this
        # the browser serves the PREVIOUS build and a fix measures as "no change at all",
        # which is exactly how this probe lied once already.
        await send(ws, nxt(), "Network.enable")
        await send(ws, nxt(), "Network.setCacheDisabled", {"cacheDisabled": True})
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        for profile, touch in [("desktop", False), ("touch", True)]:
            # `maxTouchPoints` must be 1..16 — 0 is rejected, so it is only sent when the
            # emulation is actually ON and omitting it is what turns the profile off.
            params = {"enabled": touch}
            if touch:
                params["maxTouchPoints"] = 1
            await send(ws, nxt(), "Emulation.setTouchEmulationEnabled", params)
            print(f"== {profile} profile (touch emulation {touch}) ==")
            run_out = await run(ws, nxt, profile)
            print()
            for label, d, sa, sb, ya, yb in run_out:
                if d == 0:
                    print(f"    NO SCROLL   {label}")
                elif d < 0:
                    print(f"    SCROLLED {d}px (content moved up)  {label}")
                else:
                    print(f"    moved the WRONG way {d}px  {label}")
            print()


if __name__ == "__main__":
    asyncio.run(main())
