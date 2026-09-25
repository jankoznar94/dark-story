#!/usr/bin/env python3
"""Dump the PWA's SELL cards VERBATIM — innerHTML plus the block heights.

A 1px border says a card is 149px tall; it does not say WHY. The port's card for a static
`helm_helm` renders an EMPTY `.shop-item-stats` block (88px total against the PWA's 149),
and the reason is a rule in `buildItemStatsHtml`: a static armour item has
`defenseMin`/`defenseMax` and NO `defense` value — only a GENERATED item gets one. So the
question is what the PWA's own markup does with that item, and only the markup answers it.

  python3 tools/import/probe_shop_sell_html.py
"""

import asyncio
import json
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
LS_KEY = "dungeonRecallV7"
SEED_ITEMS = ["helm_helm", "armor_ringMail", "silverRing", "blade_shortSword"]


def _ws():
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/list") as fh:
        for t in json.load(fh):
            if t.get("type") == "page":
                return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target on 9222")


DUMP = r"""
(() => {
  const rect = el => { const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)]; };
  return [...document.querySelectorAll('#shopList .shop-item')].map(el => {
    const name = (el.querySelector('.shop-item-name') || {}).textContent || '';
    const head = el.querySelector('.shop-item-header');
    const st = el.querySelector('.shop-item-stats');
    const acts = el.querySelector('.shop-item-actions');
    return {
      name,
      card: rect(el),
      header: head ? rect(head) : null,
      stats: st ? rect(st) : null,
      actions: acts ? rect(acts) : null,
      rowCount: st ? st.querySelectorAll('.stat-row').length : 0,
      statsHtml: st ? st.innerHTML.slice(0, 600) : null,
    };
  });
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
        for item in SEED_ITEMS:
            await ev(f"(() => {{ try {{ game.buyItem('{item}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.4)
        print("bag:", await ev(f"(() => {{ const s=JSON.parse(localStorage.getItem('{LS_KEY}')||'{{}}');"
                              f" return JSON.stringify(((s.hero||{{}}).inventory)||[]); }})()"))
        await ev("game.showScreen('shop')"); await asyncio.sleep(1.5)
        await ev("(() => { const t=[...document.querySelectorAll('.shop-tab')]"
                 ".find(e => /Prodat|Sell/i.test(e.textContent)); if (t) t.click(); })()")
        await asyncio.sleep(1.5)
        print(json.dumps(await ev(DUMP), indent=1)[:8000])


asyncio.run(main())
