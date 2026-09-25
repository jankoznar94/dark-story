#!/usr/bin/env python3
"""Measure the LIVE PWA's SHOP screen, both tabs, plus the item-stat block.

Jan's two shop reports:
  1. the SELL tab's content runs off the screen;
  2. the item stats look wrong — a strange border around them, too-small text, no
     line spacing.

Both are geometry questions, so this asks the browser rather than reading the CSS,
and prints the shop-list box, the shop-item boxes and the stat rows' own rects and
computed font-size / line-height / border.

  python3 tools/import/probe_shop_pwa.py            # both tabs
  python3 tools/import/probe_shop_pwa.py sell

Requires: `python3 -m http.server 8099` inside the PWA's dist/, and chromium on
--remote-debugging-port=9222. Loads a FRESH page per tab, because `openModal()`
moves the real screens and a second transition throws.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222


def _target_ws():
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/list") as fh:
        tabs = json.load(fh)
    for t in tabs:
        if t.get("type") == "page":
            return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target on 9222")


async def main():
    want = sys.argv[1] if len(sys.argv) > 1 else "both"
    mid = 0

    def nxt():
        nonlocal mid
        mid += 1
        return mid

    targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=64 * 1024 * 1024) as ws:

        async def send(method, params=None):
            await ws.send(json.dumps({"id": nxt(), "method": method, "params": params or {}}))
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

        await send("Page.enable")
        await send("Runtime.enable")
        await send("Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        async def load_with_class():
            await send("Page.navigate", {"url": URL})
            await asyncio.sleep(4)
            clicked = await ev(
                "(() => { const b = document.querySelector('button[onclick*=\"selectClass\"]');"
                " if (b) { b.click(); return 'card-handler'; }"
                " try { game.selectClass('barbarian'); return 'selectClass()'; }"
                " catch (e) { return 'ERR ' + e.message; } })()")
            await asyncio.sleep(1.5)
            kit = await ev("(() => { const s=JSON.parse(localStorage.getItem('dungeonRecallV7')||'{}');"
                           " return { cls: s.heroClass||'', maxHp:(s.hero||{}).maxHp,"
                           " inv:(s.hero||{}).inventory ? s.hero.inventory.length : 0 }; })()")
            print(f"  class: {clicked} -> {kit}")
            if not kit or kit.get("cls") != "barbarian":
                raise SystemExit("no class selected — the shop would be empty")

        async def measure(tab):
            await ev("game.showScreen('shop')")
            await asyncio.sleep(1.5)
            if tab == "sell":
                ok = await ev(
                    "(() => { const t=[...document.querySelectorAll('.shop-tab')]"
                    ".find(e => /Prodat|Sell/i.test(e.textContent));"
                    " if (!t) return 'no-tab'; t.click(); return 'clicked'; })()")
                await asyncio.sleep(1.5)
                print(f"  sell tab: {ok}")
            out = await ev(MEASURE)
            return out

        if want in ("both", "buy"):
            await load_with_class()
            print("=== BUY TAB ===")
            print(json.dumps(await measure("buy"), indent=1)[:7000])
        if want in ("both", "sell"):
            await load_with_class()
            print("\n=== SELL TAB ===")
            print(json.dumps(await measure("sell"), indent=1)[:9000])


MEASURE = r"""
(() => {
  const out = {};
  const rect = el => { const r = el.getBoundingClientRect();
    return {x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1)}; };
  out.viewport = {w: innerWidth, h: innerHeight,
                  docScrollH: document.documentElement.scrollHeight,
                  bodyScrollH: document.body.scrollHeight};

  const screen = document.getElementById('shopScreen');
  if (screen) { const cs = getComputedStyle(screen);
    out.shopScreen = {rect: rect(screen), scrollH: screen.scrollHeight,
      clientH: screen.clientHeight, clientW: screen.clientWidth,
      overflowY: cs.overflowY, overflowX: cs.overflowX, pad: cs.padding, display: cs.display}; }

  const list = document.getElementById('shopList');
  if (list) { const cs = getComputedStyle(list);
    out.shopList = {rect: rect(list), scrollH: list.scrollHeight, clientH: list.clientHeight,
      clientW: list.clientWidth, overflowX: cs.overflowX, overflowY: cs.overflowY,
      display: cs.display, pad: cs.padding}; }

  const container = list ? list.closest('.container') : null;
  if (container) { const cs = getComputedStyle(container);
    out.container = {rect: rect(container), pad: cs.padding, boxSizing: cs.boxSizing,
      overflowX: cs.overflowX, width: cs.width}; }

  out.items = [...document.querySelectorAll('.shop-item')].slice(0, 3).map(it => {
    const cs = getComputedStyle(it);
    // what actually escapes: the widest descendant's right edge
    let widest = null;
    for (const k of it.querySelectorAll('*')) {
      const r = k.getBoundingClientRect();
      if (!widest || r.x + r.width > widest.r.x + widest.r.w) {
        widest = {tag: (k.className || k.tagName).toString().slice(0, 40), r: rect(k)};
      }
    }
    return {rect: rect(it), bg: cs.backgroundColor, border: cs.border, pad: cs.padding,
      widest};
  });

  const stats = document.querySelector('.shop-item-stats');
  if (stats) { const cs = getComputedStyle(stats);
    out.stats = {rect: rect(stats), fontSize: cs.fontSize, lineHeight: cs.lineHeight,
      color: cs.color, textAlign: cs.textAlign, width: cs.width, border: cs.border,
      background: cs.backgroundColor};
    out.statRows = [...stats.querySelectorAll('.stat-row')].slice(0, 6).map(r => {
      const rcs = getComputedStyle(r);
      const lab = r.querySelector('.stat-label'), val = r.querySelector('.stat-value');
      return {rect: rect(r), pad: rcs.padding, borderBottom: rcs.borderBottom,
        gap: rcs.gap, justify: rcs.justifyContent,
        label: lab ? lab.textContent : null, labelRect: lab ? rect(lab) : null,
        labelFont: lab ? getComputedStyle(lab).fontSize : null,
        value: val ? val.textContent : null, valueRect: val ? rect(val) : null};
    });
  }
  return out;
})()
"""


asyncio.run(main())
