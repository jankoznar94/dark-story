#!/usr/bin/env python3
"""The PWA's shop BUILT-IN sizes: the tab strip, the category strip, the card's blocks and
the buy button — every rect plus the computed box model.

The port's card came out 140px tall against the PWA's 149 and its spacing 148 against 157,
and the port's button is a hardcoded 130x40 where the PWA's is `width:fit-content` with
8px/16px padding and `line-height:1`. Neither difference is visible in a 1px border scan,
so this asks the browser for each block's own box and the paddings/borders that make it.

  python3 tools/import/probe_shop_boxes.py
"""

import asyncio
import json
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222


def _ws():
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/list") as fh:
        for t in json.load(fh):
            if t.get("type") == "page":
                return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target on 9222")


DUMP = r"""
(() => {
  const R = el => { const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)]; };
  const cs = el => getComputedStyle(el);
  const box = el => el ? {rect: R(el), pad: cs(el).padding, border: cs(el).borderWidth,
                          margin: cs(el).margin, font: cs(el).fontSize,
                          line: cs(el).lineHeight, display: cs(el).display,
                          boxSizing: cs(el).boxSizing} : null;
  const out = {};

  // The page header (`.page-header`, 80px icon + title + gold on the right).
  const ph = document.querySelector('#shopScreen .page-header');
  out.pageHeader = box(ph);
  if (ph) {
    out.pageHeaderHtml = ph.outerHTML.slice(0, 700);
    out.pageHeaderKids = [...ph.querySelectorAll('*')].slice(0, 10).map(e => ({
      tag: e.tagName + (e.className ? '.' + String(e.className).split(' ')[0] : ''),
      text: e.textContent.trim().slice(0, 40), box: box(e)}));
  }
  // The screen's own container padding.
  out.container = box(document.querySelector('#shopScreen .container'));

  // The Buy/Sell strip and the category strip, on the shop screen.
  const tabs = document.querySelector('.shop-tabs');
  out.shopTabs = box(tabs);
  if (tabs) out.shopTabsKids = [...tabs.children].map(e => ({text: e.textContent.trim(), box: box(e)}));
  const cat = document.querySelector('.shop-cat-tabs');
  out.catTabs = box(cat);
  if (cat) out.catTabsKids = [...cat.children].map(e => ({text: e.textContent.trim(), box: box(e)}));

  // The potion-slot info line, which the port renders as a Label under the tabs.
  const info = document.querySelector('#shopPotionSlots, .shop-potion-info, #shopSlotInfo');
  out.potionInfo = info ? {id: info.id, cls: info.className, text: info.textContent.trim(),
                           box: box(info)} : null;

  // The first card, block by block.
  const card = document.querySelector('#shopList .shop-item');
  if (card) {
    out.card = box(card);
    out.header = box(card.querySelector('.shop-item-header'));
    out.icon = box(card.querySelector('.shop-item-icon'));
    out.iconImg = box(card.querySelector('.shop-item-icon img'));
    out.name = box(card.querySelector('.shop-item-name'));
    out.stats = box(card.querySelector('.shop-item-stats'));
    out.actions = box(card.querySelector('.shop-item-actions'));
    const b = card.querySelector('.shop-item-actions button, .shop-item-actions .btn');
    out.button = box(b);
    if (b) {
      out.buttonKids = [...b.children].map(e => ({text: e.textContent.trim(),
        font: cs(e).fontSize, box: box(e)}));
      out.buttonHtml = b.outerHTML.slice(0, 400);
    }
  }
  return out;
})()
"""


async def main():
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
                return {"__error__": str(r["exceptionDetails"])[:400]}
            return r.get("result", {}).get("value")

        await send("Page.enable"); await send("Runtime.enable")
        await send("Network.setCacheDisabled", {"cacheDisabled": True})
        await send("Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send("Page.navigate", {"url": URL})
        await asyncio.sleep(4.0)
        print("class:", await ev(
            "(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
            " if (b) { b.click(); return 'card'; }"
            " try { game.selectClass('barbarian'); return 'fn'; } catch(e){ return 'ERR'; } })()"))
        await asyncio.sleep(1.5)
        await ev("(() => { const t=document.getElementById('testToggle'); if (t) t.click(); })()")
        await asyncio.sleep(1.5)
        for item in ["helm_helm", "armor_ringMail", "blade_shortSword"]:
            await ev(f"(() => {{ try {{ game.buyItem('{item}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.4)
        await ev("game.showScreen('shop')"); await asyncio.sleep(1.5)
        await ev("(() => { const t=[...document.querySelectorAll('.shop-tab')]"
                 ".find(e => /Prodat|Sell/i.test(e.textContent)); if (t) t.click(); })()")
        await asyncio.sleep(1.2)
        await ev("(() => { const t=[...document.querySelectorAll('.shop-tab')]"
                 ".find(e => /Koupit|Buy/i.test(e.textContent)); if (t) t.click(); })()")
        await asyncio.sleep(1.2)
        print(json.dumps(await ev(DUMP), indent=1)[:10000])


asyncio.run(main())
