#!/usr/bin/env python3
"""Measure the LIVE PWA's `#invItemOverlay` — the item-info panel.

Jan's report: "the stats in the info windows are weirdly right-aligned". The CSS says
`.stat-row { display:flex; justify-content: space-between; gap:12px }` with
`.stat-label`/`.stat-value` as the two children, and the port reproduces it as an
HBoxContainer with an expanding left Label — which is NOT the same mechanism.

This drives the real page, opens the overlay on a real generated item, and prints
every row's rect plus the computed styles that decide where the text sits:

  python3 tools/import/probe_item_info_pwa.py [--shot /tmp/pwa_info.png]
"""

import argparse
import asyncio
import base64
import json
import os
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
LS_KEY = "dungeonRecallV7"

MEASURE_JS = r"""
(() => {
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)];
  };
  const ov = document.getElementById('invItemOverlay');
  const out = {visible: !!ov && !ov.classList.contains('hidden'), rows: [],
               content: null, contentStyle: null, close: null, closeStyle: null,
               name: null, nameStyle: null, stats: null, statsStyle: null};
  if (!ov) return out;
  const c = document.getElementById('invItemOverlayContent');
  out.content = box(c);
  if (c) {
    const cs = getComputedStyle(c);
    out.contentStyle = {padding: cs.padding, gap: cs.gap, display: cs.display,
                        alignItems: cs.alignItems, maxWidth: cs.maxWidth,
                        minWidth: cs.minWidth, border: cs.borderTopWidth + ' ' + cs.borderTopColor,
                        radius: cs.borderRadius};
  }
  const x = document.getElementById('invItemOverlayClose');
  out.close = box(x);
  if (x) {
    const xs = getComputedStyle(x);
    out.closeStyle = {width: xs.width, height: xs.height, fontSize: xs.fontSize,
                      padding: xs.padding, border: xs.borderTopWidth + ' ' + xs.borderTopColor,
                      radius: xs.borderRadius, display: xs.display};
  }
  const n = document.getElementById('invItemOverlayName');
  out.name = box(n);
  if (n) {
    const ns = getComputedStyle(n);
    out.nameStyle = {fontSize: ns.fontSize, fontWeight: ns.fontWeight,
                     textAlign: ns.textAlign, color: ns.color};
  }
  const s = document.getElementById('invItemOverlayStats');
  out.stats = box(s);
  if (s) {
    const ss = getComputedStyle(s);
    out.statsStyle = {fontSize: ss.fontSize, textAlign: ss.textAlign, lineHeight: ss.lineHeight,
                      width: ss.width, color: ss.color};
  }
  // Every row: the row itself, its two spans, and the properties that place them.
  document.querySelectorAll('#invItemOverlayStats .stat-row').forEach(el => {
    const rs = getComputedStyle(el);
    const lab = el.querySelector('.stat-label');
    const val = el.querySelector('.stat-value');
    const ls = lab ? getComputedStyle(lab) : null;
    const vs = val ? getComputedStyle(val) : null;
    out.rows.push({
      text: el.textContent.trim(),
      box: box(el),
      style: {display: rs.display, justifyContent: rs.justifyContent, gap: rs.gap,
              padding: rs.padding, textAlign: rs.textAlign, borderBottom: rs.borderBottomWidth},
      label: {text: lab ? lab.textContent.trim() : null, box: box(lab),
              width: ls ? ls.width : null, textAlign: ls ? ls.textAlign : null,
              color: ls ? ls.color : null, fontSize: ls ? ls.fontSize : null,
              flex: ls ? ls.flex : null, alignSelf: ls ? ls.alignSelf : null},
      value: {text: val ? val.textContent.trim() : null, box: box(val),
              width: vs ? vs.width : null, textAlign: vs ? vs.textAlign : null,
              color: vs ? vs.color : null, fontSize: vs ? vs.fontSize : null,
              flex: vs ? vs.flex : null, display: vs ? vs.display : null},
    });
  });
  return out;
})()
"""

IDS_JS = r"""
(() => {
  const out = {shop: [], bag: []};
  document.querySelectorAll('.shop-item').forEach(el => {
    const m = /showItemInfo\('([^']+)'\)/.exec(el.getAttribute('onclick') || '');
    if (m) out.shop.push({id: m[1], text: el.textContent.trim().slice(0, 40)});
  });
  const s = JSON.parse(localStorage.getItem('dungeonRecallV7') || '{}');
  out.bag = ((s.hero || {}).inventory || []).map(e => (e && e.id) || e);
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


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", default="/tmp/pwa_item_info.png")
    args = ap.parse_args()

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
        await send(ws, nxt(), "Network.setCacheDisabled", {"cacheDisabled": True})
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:400]}
            return r.get("result", {}).get("value")

        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(3.0)
        await ev(f"localStorage.removeItem('{LS_KEY}')")
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4.0)
        for _ in range(15):
            if await ev("(() => { const c=document.querySelector('.class-card');"
                        " return c && c.getBoundingClientRect().width > 0; })()") is True:
                break
            await asyncio.sleep(0.5)
        await ev("(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
                 " if (b) { b.click(); return 'card'; }"
                 " try { game.selectClass('barbarian'); return 'fn'; }"
                 " catch(e) { return 'ERR'; } })()")
        await asyncio.sleep(2.0)
        await ev("(() => { const t=document.getElementById('testToggle'); if (t) t.click(); })()")
        await asyncio.sleep(1.5)

        # The shop holds real GENERATED items (affixes and all) and each row carries the
        # id `showItemInfo` takes — the inventory overlay is the same element.
        await ev("(() => { try { game.showScreen('shop'); } catch(e) {} })()")
        await asyncio.sleep(2.0)
        ids = await ev(IDS_JS)
        print("shop ids:", (ids or {}).get("shop", [])[:12])
        print("bag ids :", (ids or {}).get("bag"))

        candidates = [e["id"] for e in (ids or {}).get("shop", [])]
        if not candidates:
            print("probe: FAIL no shop item ids found")
            return 1

        # Prefer an item with SEVERAL stat rows; the alignment question needs rows with a
        # short label and a longer value.
        best = None
        for i in candidates[:24]:
            await ev(f"(() => {{ try {{ game.showItemInfo('{i}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.12)
            m = await ev(MEASURE_JS)
            if not isinstance(m, dict) or not m.get("visible"):
                continue
            if best is None or len(m.get("rows", [])) > len(best[1].get("rows", [])):
                best = (i, m)
        if best is None:
            print("probe: FAIL the overlay never became visible")
            return 1
        item_id, m = best
        print(f"\n=== {item_id} ===")
        print(json.dumps(m, indent=1))

        shot = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
        with open(args.shot, "wb") as fh:
            fh.write(base64.b64decode(shot["data"]))
        print("shot:", args.shot)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
