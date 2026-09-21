#!/usr/bin/env python3
"""Measure the LIVE PWA (not a PNG) — computed styles and geometry via CDP.

  python3 tools/import/probe_pwa.py navbar
  python3 tools/import/probe_pwa.py background
  python3 tools/import/probe_pwa.py all

PNG measurement has a floor: an anti-aliased edge is not a real edge, and a
screenshot cannot say whether a colour came from a background or a border. This asks
the browser directly, so the CSS values the port has to match come out exact.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

PROBES = {
    # name -> JS returning a plain object of measurements
    "navbar": r"""
    (() => {
      const bar = document.querySelector('.nav-bar');
      const cs = getComputedStyle(bar);
      const r = bar.getBoundingClientRect();
      const items = [...bar.querySelectorAll('a')].map(a => {
        const s = getComputedStyle(a);
        const b = a.getBoundingClientRect();
        return {
          id: a.dataset.screen || a.id || '?',
          img: a.querySelector('img') ? a.querySelector('img').getAttribute('src') : null,
          text: a.textContent.trim().slice(0, 6),
          x: +b.x.toFixed(1), y: +b.y.toFixed(1),
          w: +b.width.toFixed(1), h: +b.height.toFixed(1),
          bg: s.backgroundColor, color: s.color, radius: s.borderRadius,
        };
      });
      const inner = bar.querySelector('a');
      const ics = getComputedStyle(inner);
      return {
        bar: {x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1)},
        barBg: cs.backgroundColor, barBorderTop: cs.borderTopWidth + ' ' + cs.borderTopColor,
        barPadding: cs.padding, barGap: cs.gap,
        itemBg: ics.backgroundColor, itemW: inner.getBoundingClientRect().width,
        items,
        bodyBg: getComputedStyle(document.body).backgroundColor,
        htmlBg: getComputedStyle(document.documentElement).backgroundColor,
      };
    })()
    """,
    "background": r"""
    (() => {
      const out = { body: getComputedStyle(document.body).backgroundColor,
                    html: getComputedStyle(document.documentElement).backgroundColor };
      const sel = ['#townScreen','#chestScreen','#shopScreen','#craftScreen','#gambleScreen',
                   '#mapScreen','#bestiaryScreen','#spellbookScreen','.container','.card',
                   '.inv-grid-wrap','#modalOverlay','.modal-content'];
      out.els = {};
      for (const s of sel) {
        const el = document.querySelector(s);
        if (!el) { out.els[s] = null; continue; }
        const cs = getComputedStyle(el);
        const r = el.getBoundingClientRect();
        out.els[s] = { bg: cs.backgroundColor, border: cs.border, radius: cs.borderRadius,
                       margin: cs.margin, padding: cs.padding,
                       x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1) };
      }
      return out;
    })()
    """,
    "screens": r"""
    (() => {
      const out = {};
      for (const id of ['townScreen','chestScreen','shopScreen','craftScreen','gambleScreen',
                        'mapScreen','bestiaryScreen','spellbookScreen','townScreen']) {
        const el = document.getElementById(id);
        if (!el) { continue; }
        const kids = [...el.children].map(c => {
          const r = c.getBoundingClientRect();
          return { cls: c.className.toString().slice(0,40),
                   y:+r.y.toFixed(1), h:+r.height.toFixed(1), w:+r.width.toFixed(1),
                   bg: getComputedStyle(c).backgroundColor };
        });
        out[id] = { pad: getComputedStyle(el).padding, kids: kids.slice(0, 8) };
      }
      return out;
    })()
    """,
}


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(names):
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

        async def evaluate(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

        await evaluate("(() => { const c=document.querySelector('.class-card');"
                       " if(!c) return 'none'; c.click(); return 'ok'; })()")
        await asyncio.sleep(2)

        for name in names:
            js = PROBES.get(name)
            if js is None:
                print(f"unknown probe {name}")
                continue
            val = await evaluate(js)
            print(f"===== {name} =====")
            print(json.dumps(val, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    want = sys.argv[1:] or ["navbar"]
    asyncio.run(main(want))
