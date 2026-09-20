#!/usr/bin/env python3
"""Drive the DEPLOYED Dark Story web build over CDP and capture what it prints.

Why: Jan reported two things a headless GDScript test cannot answer - "the items
in the body cannot be taken and the game locks up" and "a second corpse object
appears next to the real model". Both are the WEB build in a browser, so they are
measured there.

Usage:
    python3 tools/web_console_probe.py <url> [seconds] [--click x,y ...] [--shot out.png]
"""
import asyncio
import base64
import json
import sys
import urllib.request

import websockets


def targets():
    with urllib.request.urlopen("http://127.0.0.1:9222/json") as r:
        return json.load(r)


class CDP:
    def __init__(self, ws):
        self.ws = ws
        self.n = 0
        self.pending = {}

    async def send(self, method, **params):
        self.n += 1
        mid = self.n
        await self.ws.send(json.dumps({"id": mid, "method": method, "params": params}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == mid:
                return msg
            await self._event(msg)

    async def _event(self, msg):
        m = msg.get("method", "")
        if m == "Runtime.consoleAPICalled":
            args = " ".join(
                str(a.get("value", a.get("description", "")))
                for a in msg["params"].get("args", []))
            print("[console:%s] %s" % (msg["params"].get("type"), args), flush=True)
        elif m == "Runtime.exceptionThrown":
            d = msg["params"]["exceptionDetails"]
            txt = d.get("text", "")
            ex = d.get("exception", {})
            print("[EXCEPTION] %s %s" % (txt, ex.get("description", "")), flush=True)
        elif m == "Log.entryAdded":
            e = msg["params"]["entry"]
            print("[log:%s] %s" % (e.get("level"), e.get("text")), flush=True)

    async def pump(self, seconds):
        end = asyncio.get_event_loop().time() + seconds
        while asyncio.get_event_loop().time() < end:
            try:
                msg = json.loads(await asyncio.wait_for(self.ws.recv(), 0.5))
            except asyncio.TimeoutError:
                continue
            except Exception:
                return
            await self._event(msg)


async def main():
    url = sys.argv[1]
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 40.0
    clicks = []
    shot = None
    argv = sys.argv[3:]
    i = 0
    while i < len(argv):
        if argv[i] == "--click":
            x, y = argv[i + 1].split(",")
            clicks.append((float(x), float(y)))
            i += 2
        elif argv[i] == "--shot":
            shot = argv[i + 1]
            i += 2
        else:
            i += 1

    t = targets()
    page = [x for x in t if x["type"] == "page"][0]
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=64 << 20) as ws:
        c = CDP(ws)
        await c.send("Runtime.enable")
        await c.send("Log.enable")
        await c.send("Page.enable")
        await c.send("Page.navigate", url=url)
        await c.pump(secs)

        for (x, y) in clicks:
            for kind in ("mousePressed", "mouseReleased"):
                await c.send("Input.dispatchMouseEvent", type=kind, x=x, y=y,
                             button="left", clickCount=1)
            await c.pump(1.5)
        await c.pump(4.0)

        # what the GAME says: the canvas plus any Godot console output
        r = await c.send("Runtime.evaluate", expression=(
            "JSON.stringify({title: document.title,"
            " canvas: !!document.querySelector('canvas'),"
            " nav: (performance.getEntriesByType('navigation')[0]||{}).transferSize,"
            " res: performance.getEntriesByType('resource').map(r=>[r.name.split('/').pop(),r.transferSize])})"
        ), returnByValue=True)
        print("PAGE_STATE", r.get("result", {}).get("result", {}).get("value"), flush=True)

        if shot:
            r = await c.send("Page.captureScreenshot", format="png")
            data = r.get("result", {}).get("data")
            if data:
                open(shot, "wb").write(base64.b64decode(data))
                print("SHOT", shot, flush=True)


asyncio.run(main())
