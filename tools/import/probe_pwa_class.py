#!/usr/bin/env python3
"""Probe the live PWA: what does the window expose, what does a real fight drop?"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main():
    targets = json.loads(urllib.request.urlopen("http://127.0.0.1:9222/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=64 * 1024 * 1024) as ws:
        mid = 0

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:400]}
            return r.get("result", {}).get("value")

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await ev("localStorage.clear()")
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(6)

        print("class cards:", await ev(
            "(() => document.querySelectorAll('.class-card').length)()"))
        print("class buttons:", await ev(
            "(() => Array.from(document.querySelectorAll('[onclick*=selectClass]'))"
            ".map(e => e.tagName + ':' + e.getAttribute('onclick')).slice(0,3))()"))
        print("game keys sample:", await ev(
            "(() => { const g = window.game || {}; return Object.keys(g).slice(0,80); })()"))
        print("selectClass is fn:", await ev(
            "(() => typeof (window.game && window.game.selectClass))()"))
        print("selectClass call:", await ev(
            "(() => { try { window.game.selectClass('barbarian'); } catch(e) { return 'err '+e; }"
            " return 'ok'; })()"))
        await asyncio.sleep(1)
        print("state after:", await ev(
            "(() => { const s = window.state || {}; return JSON.stringify({cls: s.heroClass,"
            " hp: s.hero && s.hero.maxHp, keys: Object.keys(s).slice(0,10)}); })()"))
        print("screens now:", await ev(
            "(() => Array.from(document.querySelectorAll('.screen'))"
            ".filter(e => !e.classList.contains('hidden')).map(e => e.id))()"))
        print("screen ids present:", await ev(
            "(() => Array.from(document.querySelectorAll('[id]')).map(e=>e.id)"
            ".filter(id => id.toLowerCase().includes('arena') || id.toLowerCase().includes('result')))()"))
        print("class screen visible:", await ev(
            "(() => { const e = document.getElementById('classScreen');"
            " return e ? !e.classList.contains('hidden') : 'missing'; })()"))


if __name__ == "__main__":
    asyncio.run(main())
