#!/usr/bin/env python3
"""Click the modal's tab #N and report what happened, WITHOUT letting a JS exception
abort the probe. `shoot_pwa.py` reports the exception as "tab did not activate" and
skips the shot; this says whether the tab really failed to activate or whether the
EXCEPTION is elsewhere and the frame is fine.
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets

CDP_PORT = 9222
OUT = "/tmp/tab_probe"


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(index):
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
        # Surface the page's own console errors instead of swallowing them.
        await send(ws, nxt(), "Log.enable")
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": "http://127.0.0.1:8099/index.html"})
        await asyncio.sleep(4)

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True})
            if "exceptionDetails" in r:
                ed = r["exceptionDetails"]
                return {"__exc__": (ed.get("exception") or {}).get("description",
                                                                  str(ed))[:400]}
            return r.get("result", {}).get("value")

        for _ in range(15):
            ok = await ev("(() => { const c = document.querySelector('.class-card');"
                          " return c && c.getBoundingClientRect().width > 0 ? 1 : 0; })()")
            if ok == 1:
                break
            await asyncio.sleep(0.5)
        await ev("document.querySelector('.class-card').click()")
        await asyncio.sleep(2)

        # `window.onerror` captures the exception that aborts the click handler.
        await ev("window.__err = [];"
                 " window.addEventListener('error', e => window.__err.push("
                 "   (e.message||'')+' @'+(e.lineno||'')+':'+(e.colno||'')));")

        print("open inventory:", await ev("game.showScreen('inventory'), 'ok'"))
        await asyncio.sleep(1.0)
        print("tabs:", await ev("[...document.querySelectorAll('.combined-tab')]"
                                ".map(t => t.textContent.trim())"))
        print("before active:", await ev(
            "[...document.querySelectorAll('.combined-tab')]"
            ".map(t => t.classList.contains('active'))"))

        r = await ev(f"(() => {{ const t=[...document.querySelectorAll('.combined-tab')];"
                     f" if (t.length < {index + 1}) return 'only ' + t.length;"
                     f" t[{index}].click(); return 'clicked'; }})()")
        print("click:", r)
        await asyncio.sleep(1.5)
        print("after active:", await ev(
            "[...document.querySelectorAll('.combined-tab')]"
            ".map(t => t.classList.contains('active'))"))
        print("active panes:", await ev(
            "[...document.querySelectorAll('.combined-screen')]"
            ".map((s,i) => i + ':' + (s.classList.contains('active') ? 'ACTIVE' : '-'))"))
        print("errors:", await ev("window.__err"))
        print("heroScreen children:", await ev(
            "(() => { const h=document.getElementById('heroScreen');"
            " if (!h) return 'no heroScreen';"
            " return h.innerHTML.length + ' chars, ' + h.children.length + ' children'; })()"))

        await ev("window.scrollTo(0,0)")
        await asyncio.sleep(0.6)
        s = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
        import os
        os.makedirs(OUT, exist_ok=True)
        p = f"{OUT}/tab{index}.png"
        with open(p, "wb") as fh:
            fh.write(base64.b64decode(s["data"]))
        print("shot:", p)


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1])))
