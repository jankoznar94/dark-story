#!/usr/bin/env python3
"""Evaluate an arbitrary JS expression in the LIVE PWA and print the result.

The CSS is the spec but the computed style of the element that is actually up is the
tie-breaker. This is the smallest tool that gets at it:

  python3 tools/import/eval_pwa.py chest "getComputedStyle(document.querySelector('.chest-grid')).minHeight"
  python3 tools/import/eval_pwa.py chest "document.querySelector('.chest-cell').offsetHeight"
  python3 tools/import/eval_pwa.py --raw "document.title"

The first argument is a screen key (same vocabulary as shoot_pwa.py) or `-` to skip
navigation. The expression may be a function body returning a value.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

MODAL_TABS = {"inventory": 0, "talents": 1, "hero": 2}


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(screen, expr):
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

        async def evaluate(e):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": e, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:400]}
            return r.get("result", {}).get("value")

        await evaluate("(() => { const c=document.querySelector('.class-card');"
                       " if(!c) return 'none'; c.click(); return 'ok'; })()")
        await asyncio.sleep(2)

        if screen not in ("-", "", None):
            if screen in MODAL_TABS:
                idx = MODAL_TABS[screen]
                await evaluate("(() => { game.showScreen('inventory');"
                               f" const t=[...document.querySelectorAll('.combined-tab')];"
                               f" t[{idx}].click(); return 'ok'; }})()")
            else:
                await evaluate(f"game.showScreen('{screen}')")
            await asyncio.sleep(1.5)

        print(json.dumps(await evaluate(expr), indent=2, ensure_ascii=False, default=str))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "--raw":
        asyncio.run(main("-", sys.argv[2]))
    else:
        asyncio.run(main(sys.argv[1], sys.argv[2]))
