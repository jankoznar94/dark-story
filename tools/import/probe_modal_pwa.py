#!/usr/bin/env python3
"""Measure the LIVE PWA's character modal, per tab — the geometry the port must match.

The modal has caused the worst layout bugs in the port, and a PNG cannot say WHY a block
sits where it does. This asks the browser: the dialog's own rect, the tab strip, the
`.modal-body`, the active `.combined-screen` and its direct children.

  python3 tools/import/probe_modal_pwa.py            # all three tabs
  python3 tools/import/probe_modal_pwa.py hero       # one tab

Each tab is shot from a FRESH page load: `openModal()` MOVES the real screens into
wrappers inside itself and throws from the third open on.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

CDP_PORT = 9222
URL = "http://127.0.0.1:8099/index.html"

TABS = [("inventory", 0), ("talents", 1), ("hero", 2)]

JS_MODAL = r"""
(() => {
  const q = s => document.querySelector(s);
  const rect = el => { if (!el) return null; const r = el.getBoundingClientRect();
    return {x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1)}; };
  const content = q('#modalContent');
  const body = q('#modalContent .modal-body');
  const screen = q('.combined-screen.active');
  const tabs = q('#modalContent .combined-tabs');
  const out = {
    content: rect(content),
    contentStyle: content ? (() => { const s = getComputedStyle(content);
      return {minH:s.minHeight, maxH:s.maxHeight, height:s.height, width:s.width,
              display:s.display, overflow:s.overflow}; })() : null,
    tabs: rect(tabs),
    body: rect(body),
    screen: rect(screen),
    screenStyle: screen ? (() => { const s = getComputedStyle(screen);
      return {display:s.display, flex:s.flex, minHeight:s.minHeight,
              padding:s.padding, overflowY:s.overflowY}; })() : null,
    children: [],
  };
  if (screen) {
    for (const c of screen.children) {
      const t = c.querySelector ? c.querySelector('.card-title') : null;
      out.children.push({
        tag: c.tagName, id: c.id, cls: (c.className || '').toString().slice(0, 40),
        rect: rect(c), title: t ? t.textContent.trim().slice(0, 24) : null,
      });
      for (const g of c.children) {
        out.children.push({tag: '  ' + g.tagName, id: g.id,
          cls: (g.className || '').toString().slice(0, 40), rect: rect(g), title: null});
      }
    }
  }
  return out;
})()
"""


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def probe(tab, index):
    targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"],
                                  max_size=64 * 1024 * 1024) as ws:
        mid = 0

        def nxt():
            nonlocal mid
            mid += 1
            return mid

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True})
            if "exceptionDetails" in r:
                ed = r["exceptionDetails"]
                return {"__exc__": (ed.get("exception") or {}).get("description", str(ed))[:300]}
            return r.get("result", {}).get("value")

        await send(ws, nxt(), "Page.enable")
        await send(ws, nxt(), "Runtime.enable")
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4)
        for _ in range(15):
            ok = await ev("(() => { const c = document.querySelector('.class-card');"
                          " return c && c.getBoundingClientRect().width > 0 ? 1 : 0; })()")
            if ok == 1:
                break
            await asyncio.sleep(0.5)
        # The PWA's `.class-card` click is dead in this build — drive the element that
        # carries the inline handler, then read the kit back out of the save.
        await ev("(document.querySelector('button[onclick*=\"selectClass\"]') ||"
                 " document.querySelector('.class-card')).click()")
        await asyncio.sleep(1.5)
        await ev("game.showScreen('inventory')")
        await asyncio.sleep(1.0)
        if index > 0:
            r = await ev(f"(() => {{ const t=[...document.querySelectorAll('.combined-tab')];"
                         f" if (t.length < {index+1}) return 'only ' + t.length;"
                         f" t[{index}].click(); return 'clicked'; }})()")
            await asyncio.sleep(1.2)
            if r != "clicked":
                print(f"  tab click failed: {r}")
        data = await ev(JS_MODAL)
        print(f"--- {tab} ---")
        print(json.dumps(data, indent=2, ensure_ascii=False))


async def main():
    wanted = sys.argv[1:]
    for tab, index in TABS:
        if wanted and tab not in wanted:
            continue
        await probe(tab, index)


if __name__ == "__main__":
    asyncio.run(main())
