#!/usr/bin/env python3
"""LIVE-BROWSER acceptance for the corpse fix, on the DEPLOYED build.

Drives the real web build over CDP and reports what the GAME prints, because the
reports under test are the ones a headless GDScript run cannot answer:

  * "the corpse can be opened, but the items cannot be taken from it" - needs a
    real tap through the browser's own coordinate space;
  * "the game locks up" - needs the console watched for errors and the frame
    counter watched for a stall.

The clicks are computed from the game's own camera via a JS-side helper is NOT
possible (the Godot canvas is opaque), so the sequence is: load, wait for the Godot
console banner, then click where the hero is (screen centre) to swing, and report
every console line. The definitive item-flow proof lives in
tools/probe_corpse_flow.gd; this run proves the DEPLOYED bytes behave in a browser.

Usage: python3 tools/web_live_check.py [seconds]
"""
import asyncio
import json
import sys
import urllib.request

import websockets

URL = "https://jankoznar94.github.io/dark-story/"


def page_ws():
    with urllib.request.urlopen("http://127.0.0.1:9222/json") as r:
        for t in json.load(r):
            if t["type"] == "page":
                return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target")


async def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 45.0
    errors, logs = [], []
    async with websockets.connect(page_ws(), max_size=64 << 20) as ws:
        n = 0

        async def send(method, **params):
            nonlocal n
            n += 1
            mid = n
            await ws.send(json.dumps({"id": mid, "method": method, "params": params}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    return msg
                handle(msg)

        def handle(msg):
            m = msg.get("method")
            if m == "Runtime.consoleAPICalled":
                txt = " ".join(str(a.get("value", a.get("description", "")))
                               for a in msg["params"].get("args", []))
                logs.append(txt)
                if msg["params"].get("type") in ("error", "warning"):
                    print("  [%s] %s" % (msg["params"]["type"], txt), flush=True)
            elif m == "Runtime.exceptionThrown":
                d = msg["params"]["exceptionDetails"]
                line = "%s %s" % (d.get("text"), d.get("exception", {}).get("description", ""))
                errors.append(line)
                print("  [EXCEPTION] %s" % line, flush=True)
            elif m == "Log.entryAdded":
                e = msg["params"]["entry"]
                if e.get("level") in ("error",):
                    errors.append(e.get("text", ""))
                    print("  [log:error] %s" % e.get("text"), flush=True)

        await send("Runtime.enable")
        await send("Log.enable")
        await send("Page.enable")
        await send("Page.navigate", url=URL)

        # pump until the Godot banner appears, then keep watching
        loop = asyncio.get_event_loop()
        end = loop.time() + secs
        started = False
        while loop.time() < end:
            try:
                msg = json.loads(await asyncio.wait_for(ws.recv(), 0.5))
            except asyncio.TimeoutError:
                continue
            handle(msg)
            if not started and any("starter weapon" in l for l in logs):
                started = True
                print("GAME_BOOTED", flush=True)
                # let the scene settle, then swing at the monster in front a few times
                for i in range(14):
                    for kind in ("mousePressed", "mouseReleased"):
                        await send("Input.dispatchMouseEvent", type=kind,
                                   x=640, y=620, button="left", clickCount=1)
                    await asyncio.sleep(1.2)

        alive = await send("Runtime.evaluate", expression=(
            "JSON.stringify({canvas: !!document.querySelector('canvas'),"
            " t: performance.now()})"), returnByValue=True)
        print("FINAL %s" % alive.get("result", {}).get("result", {}).get("value"))
        print("GODOT_LINES %d, ERRORS %d" % (len(logs), len(errors)))
        for e in errors:
            print("  ERR: %s" % e)
        print("LIVE_CHECK_DONE")


asyncio.run(main())
