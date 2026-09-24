#!/usr/bin/env python3
"""Read the browser console while one touch flick is performed.

    python3 tools/import/diag_console.py

The port prints a line for every event the scroll driver receives, so this answers "does the web
build deliver the touch/drag/mouse events, and does the coast actually run" without guessing.

TWO traps this file exists to avoid, both of which produce a confident wrong answer:
  * console events arrive INTERLEAVED with command replies — a `send()` that discards anything
    it is not waiting for reads "0 console lines" from a page that prints constantly;
  * after the last command there is nothing left to read the socket, so any print emitted AFTER
    it is invisible — the coast's own output lands exactly there. Hence `drain()`, which reads
    with a timeout and sends nothing.
"""

import asyncio
import json
import urllib.request

import websockets

URL = "http://127.0.0.1:8100/index.html"
CDP_PORT = 9222
LINES = []


async def drain(ws, seconds):
    """Read whatever the page prints for `seconds`, sending nothing."""
    deadline = asyncio.get_event_loop().time() + seconds
    while True:
        left = deadline - asyncio.get_event_loop().time()
        if left <= 0:
            return
        try:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=left))
        except asyncio.TimeoutError:
            return
        if msg.get("method") == "Runtime.consoleAPICalled":
            args = msg["params"].get("args", [])
            LINES.append(" ".join(str(a.get("value", "")) for a in args))


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if "method" in msg:
            if msg["method"] == "Runtime.consoleAPICalled":
                args = msg["params"].get("args", [])
                LINES.append(" ".join(str(a.get("value", "")) for a in args))
            continue
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


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
        await asyncio.sleep(14)

        print("== one touch flick on the bestiary list ==")
        await send(ws, nxt(), "Input.dispatchTouchEvent",
                   {"type": "touchStart", "touchPoints": [{"x": 126, "y": 813, "id": 1}]})
        await asyncio.sleep(0.06)
        await send(ws, nxt(), "Input.dispatchTouchEvent",
                   {"type": "touchEnd", "touchPoints": []})
        await asyncio.sleep(3)
        LINES.clear()

        await send(ws, nxt(), "Input.dispatchTouchEvent",
                   {"type": "touchStart", "touchPoints": [{"x": 195, "y": 640, "id": 1}]})
        for i in range(8):
            await send(ws, nxt(), "Input.dispatchTouchEvent",
                       {"type": "touchMove",
                        "touchPoints": [{"x": 195, "y": 640 - 15.0 * (i + 1), "id": 1}]})
            await asyncio.sleep(0.03)
        await send(ws, nxt(), "Input.dispatchTouchEvent",
                   {"type": "touchEnd", "touchPoints": []})
        # The coast happens HERE, after the last command — nothing was reading the socket.
        await drain(ws, 2.5)

        print(f"  {len(LINES)} console lines from the scroll driver:")
        events = [l for l in LINES if not l.startswith("SWIPE PROC")]
        process = [l for l in LINES if l.startswith("SWIPE PROC")]
        for line in events[:6]:
            print("   ", line)
        print(f"    ... {len(events)} event lines in total")
        print(f"  {len(process)} `_process` frames with the coast running:")
        for line in process[:12]:
            print("   ", line)
        if not process:
            print("    (none — the node's `_process` never runs on this build)")


if __name__ == "__main__":
    asyncio.run(main())
