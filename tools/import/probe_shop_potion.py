#!/usr/bin/env python3
"""The shop's remaining blocks, measured on the LIVE PWA: the potion-slot box inside
`#shopList`, the back-to-map button and the page header's own margin.

The port put the potion info as a BARE Label above the category strip; the PWA's is a
bordered `#111` box INSIDE the list, on the Misc tab only. That is a structural
difference, so it needs the box's own geometry rather than the text's.

  python3 tools/import/probe_shop_potion.py
"""

import asyncio
import json
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

MEASURE = r"""
(() => {
  const R = el => { const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)]; };
  const cs = el => getComputedStyle(el);
  const box = el => el ? {rect: R(el), pad: cs(el).padding, border: cs(el).borderWidth,
                          margin: cs(el).margin, font: cs(el).fontSize, radius: cs(el).borderRadius,
                          bg: cs(el).backgroundColor, display: cs(el).display} : null;
  const list = document.getElementById('shopList');
  const pot = document.querySelector('.shop-potion-slots');
  return {
    screen: box(document.getElementById('shopScreen')),
    back: box(document.querySelector('#shopScreen .shop-back-map')),
    backBtn: box(document.querySelector('#shopScreen .shop-back-map .btn')),
    // The screen's own markup before the list, so the port's order can be checked.
    screenTopHtml: document.getElementById('shopScreen').innerHTML.slice(0, 900),
    list: box(list),
    firstChild: list && list.children[0] ? {cls: list.children[0].className,
                                            box: box(list.children[0])} : null,
    potion: box(pot),
    potionHtml: pot ? pot.outerHTML.slice(0, 400) : null,
    potionKids: pot ? [...pot.children].map(e => ({text: e.textContent.trim(), box: box(e)})) : null,
    catTabs: box(document.querySelector('.shop-cat-tabs')),
    card: box(document.querySelector('.shop-item')),
  };
})()
"""


async def main():
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/list") as fh:
        page = next(t for t in json.load(fh) if t.get("type") == "page")
    mid = 0
    async with websockets.connect(page["webSocketDebuggerUrl"],
                                  max_size=64 * 1024 * 1024) as ws:

        async def send(method, params=None):
            nonlocal mid
            mid += 1
            await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    if "error" in msg:
                        raise RuntimeError(f"{method}: {msg['error']}")
                    return msg.get("result", {})

        async def ev(expr):
            r = await send("Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        await send("Page.enable"); await send("Runtime.enable")
        await send("Network.setCacheDisabled", {"cacheDisabled": True})
        await send("Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send("Page.navigate", {"url": URL})
        await asyncio.sleep(4.0)
        # ⚠️  `.class-card`'s click is a DEAD control in the current build (a synthetic click
        # never reaches its handler), so the class is picked through the inline handler with
        # `game.selectClass` as the fallback. Without a class the hero is null,
        # `#shopScreen` never leaves `hidden` and every rect reads 0x0 — which looks like a
        # broken probe rather than a missing class.
        print("class:", await ev(
            "(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
            " if (b) { b.click(); return 'card'; }"
            " try { game.selectClass('barbarian'); return 'fn'; } catch(e){ return 'ERR'; } })()"))
        await asyncio.sleep(1.5)
        await ev("(() => { const t=document.getElementById('testToggle'); if (t) t.click(); })()")
        await asyncio.sleep(1.5)
        await ev("game.showScreen('shop')")
        await asyncio.sleep(1.5)
        print("shopScreen:", await ev(
            "(() => { const e=document.getElementById('shopScreen'); const r=e.getBoundingClientRect();"
            " return {cls: e.className, w: r.width, h: r.height}; })()"))
        out = await ev(MEASURE)
        print(json.dumps(out, indent=1))


asyncio.run(main())
