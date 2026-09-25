#!/usr/bin/env python3
"""Shoot the LIVE PWA's shop — the SELL tab with a real bag, and the stat block.

Jan's two shop reports:
  1. the SELL tab's content runs off the screen;
  2. the item stats look wrong — a strange border around them, too-small text, no
     line spacing.

⚠️  A FRESH HERO OWNS NOTHING SELLABLE, so `probe_shop_pwa.py sell` returns an empty
list (`items: []`, shopList 358x79) and any frame shot from it is empty — the measurement
proves nothing about the card that overflows. The bag has to be BUILT IN THE SESSION:
a reload after seeding `localStorage` throws inside `loadSave()` and silently drops the
page back to the class picker (there is no class, so `#shopScreen` is 0x0 — measured).
`#testToggle` is the page's own gold control and `game.buyItem` is the page's own route
into the bag, so this buys the gear and then measures.

  python3 tools/import/probe_shop_sell.py [out.png] [tab]

Requires: `python3 -m http.server 8099` inside the PWA's dist/, chromium on
--remote-debugging-port=9222.
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
LS_KEY = "dungeonRecallV7"

# Bought one at a time through `game.buyItem`; they land in the bag and are sellable.
SEED_ITEMS = ["helm_helm", "armor_ringMail", "silverRing", "blade_shortSword"]


def _ws():
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/list") as fh:
        for t in json.load(fh):
            if t.get("type") == "page":
                return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target on 9222")


MEASURE = r"""
(() => {
  const rect = el => { const r = el.getBoundingClientRect();
    return {x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1)}; };
  const out = {viewport: {w: innerWidth, h: innerHeight}};
  const cs = el => el ? getComputedStyle(el) : null;
  const screen = document.getElementById('shopScreen');
  out.shopScreen = screen ? {rect: rect(screen), scrollH: screen.scrollHeight,
                             clientH: screen.clientHeight} : null;
  const list = document.getElementById('shopList');
  out.shopList = list ? {rect: rect(list), scrollW: list.scrollWidth, clientW: list.clientWidth,
                         scrollH: list.scrollHeight} : null;
  // The container the shop lives in: THIS is what overflows when a card is too wide.
  const cont = document.querySelector('#shopScreen .container');
  out.container = cont ? {rect: rect(cont), scrollW: cont.scrollWidth, clientW: cont.clientWidth,
                          pad: cs(cont).padding} : null;
  out.items = [...document.querySelectorAll('#shopList .shop-item')].map(el => {
    const st = el.querySelector('.shop-item-stats');
    const rows = [...(st ? st.querySelectorAll('.stat-row') : [])].map(r => {
      const c = getComputedStyle(r);
      return {text: r.textContent.trim(), rect: rect(r), fontSize: c.fontSize,
              lineHeight: c.lineHeight, borderBottom: c.borderBottom, pad: c.padding};
    });
    return {rect: rect(el), scrollW: el.scrollWidth, clientW: el.clientWidth,
            scrollH: el.scrollHeight,
            bg: cs(el).backgroundColor, border: cs(el).border, pad: cs(el).padding,
            header: rect(el.querySelector('.shop-item-header') || el),
            actions: el.querySelector('.shop-item-actions')
                     ? rect(el.querySelector('.shop-item-actions')) : null,
            stats: st ? {rect: rect(st), fontSize: cs(st).fontSize, lineHeight: cs(st).lineHeight,
                         border: cs(st).border, bg: cs(st).backgroundColor,
                         textAlign: cs(st).textAlign, width: cs(st).width} : null,
            rows};
  });
  return out;
})()
"""


async def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/pwa_sell.png"
    tab = sys.argv[2] if len(sys.argv) > 2 else "sell"

    async with websockets.connect(_ws(), max_size=16_000_000) as w:
        n = 0

        async def send(method, params=None):
            nonlocal n
            n += 1
            await w.send(json.dumps({"id": n, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(await w.recv())
                if msg.get("id") == n:
                    if "error" in msg:
                        raise RuntimeError(f"{method}: {msg['error']}")
                    return msg.get("result", {})

        async def ev(expr):
            r = await send("Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        await send("Page.enable")
        await send("Runtime.enable")
        await send("Network.setCacheDisabled", {"cacheDisabled": True})
        await send("Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        await send("Page.navigate", {"url": URL})
        await asyncio.sleep(4.0)
        for _ in range(15):
            if await ev("(() => { const c=document.querySelector('.class-card');"
                        " return c && c.getBoundingClientRect().width > 0; })()") is True:
                break
            await asyncio.sleep(0.5)
        print("class:", await ev(
            "(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
            " if (b) { b.click(); return 'card-handler'; }"
            " try { game.selectClass('barbarian'); return 'selectClass()'; }"
            " catch(e) { return 'ERR '+e.message; } })()"))
        await asyncio.sleep(2.0)

        # Gold, then buy the gear IN THIS SESSION (see the docstring — no reload).
        await ev("(() => { const t=document.getElementById('testToggle'); if (t) t.click(); })()")
        await asyncio.sleep(1.5)
        for item in SEED_ITEMS:
            await ev(f"(() => {{ try {{ game.buyItem('{item}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.4)
        bag = await ev(f"(() => {{ const s=JSON.parse(localStorage.getItem('{LS_KEY}')||'{{}}');"
                       f" return JSON.stringify(((s.hero||{{}}).inventory)||[]); }})()")
        print("bag:", bag)

        await ev("(() => { try { game.showScreen('shop'); } catch(e) {} })()")
        await asyncio.sleep(1.5)
        if tab == "sell":
            print("sell tab:", await ev(
                "(() => { const t=[...document.querySelectorAll('.shop-tab')]"
                ".find(e => /Prodat|Sell/i.test(e.textContent));"
                " if (!t) return 'no-tab'; t.click(); return 'clicked'; })()"))
            await asyncio.sleep(1.5)

        m = await ev(MEASURE)
        print(f"=== {tab.upper()} TAB ===")
        print(json.dumps(m, indent=1)[:12000])

        shot = await send("Page.captureScreenshot", {"format": "png"})
        open(out_path, "wb").write(base64.b64decode(shot["data"]))
        print("shot ->", out_path)


if __name__ == "__main__":
    asyncio.run(main())
