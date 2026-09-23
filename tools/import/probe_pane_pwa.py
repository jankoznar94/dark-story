#!/usr/bin/env python3
"""Walk the LIVE PWA's character modal ONE pane to full depth, with box metrics.

`probe_modal_pwa.py` stops two levels down, which is enough to see the dialog but not
enough to lay out a pane: the inventory's rows and the doll grid's cells all live deeper.
This prints every element's rect plus the four CSS numbers that decide it — display, gap,
padding, border — because a port that matches widths and misses a gap is 6px off per row.

  python3 tools/import/probe_pane_pwa.py inventory
  python3 tools/import/probe_pane_pwa.py talents
  python3 tools/import/probe_pane_pwa.py hero

Each run is a FRESH page load: `openModal()` moves the real screens into wrappers inside
itself and throws from the third open on, so a second tab on the same load is not the tab
that was asked for.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

CDP_PORT = 9222
URL = "http://127.0.0.1:8099/index.html"

TABS = {"inventory": 0, "talents": 1, "hero": 2}

JS = r"""
(() => {
  const rect = el => { const r = el.getBoundingClientRect();
    return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]; };
  const screen = document.querySelector('.combined-screen.active');
  if (!screen) return {error: 'no active pane'};
  const out = [];
  const walk = (el, depth) => {
    const s = getComputedStyle(el);
    out.push({
      d: depth, tag: el.tagName, cls: (el.className || '').toString().slice(0, 34),
      id: el.id, r: rect(el),
      display: s.display, gap: s.gap, pad: s.padding, mar: s.margin,
      cols: s.gridTemplateColumns, rows: s.gridTemplateRows,
      font: s.fontSize + '/' + s.fontWeight,
      text: (el.children.length === 0 ? el.textContent.trim().slice(0, 30) : null),
    });
    if (depth >= 7) return;
    for (const c of el.children) {
      if (c.getBoundingClientRect().width === 0 && c.getBoundingClientRect().height === 0)
        continue;
      walk(c, depth + 1);
    }
  };
  walk(screen, 0);
  return {pane: rect(screen), nodes: out};
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
        for _ in range(20):
            ok = await ev("(() => { const c = document.querySelector('.class-card');"
                          " return c && c.getBoundingClientRect().width > 0 ? 1 : 0; })()")
            if ok == 1:
                break
            await asyncio.sleep(0.5)
        await ev("(document.querySelector('button[onclick*=\"selectClass\"]') ||"
                 " document.querySelector('.class-card')).click()")
        await asyncio.sleep(1.5)
        await ev("game.showScreen('inventory')")
        await asyncio.sleep(1.2)
        if index > 0:
            r = await ev(f"(() => {{ const t=[...document.querySelectorAll('.combined-tab')];"
                         f" if (t.length < {index + 1}) return 'only ' + t.length;"
                         f" t[{index}].click(); return 'clicked'; }})()")
            await asyncio.sleep(1.4)
            if r != "clicked":
                print(f"  tab click failed: {r}")
        # The tab guard: a swallowed click leaves the previous pane up and every number
        # below describes the wrong screen.
        active = await ev("(() => { const t=[...document.querySelectorAll('.combined-tab')];"
                          " const i=t.findIndex(x=>x.classList.contains('active'));"
                          " return i; })()")
        print(f"--- {tab} (active tab index {active}, wanted {index}) ---")
        data = await ev(JS)
        if "error" in data:
            print("  " + data["error"])
            return
        print(f"pane {data['pane']}")
        for n in data["nodes"]:
            label = f"  {'  ' * n['d']}{n['tag']:<6} {n['cls'][:30]:<30} {str(n['r']):<26}"
            label += f" {n['display']:<14} gap={n['gap']:<12} pad={n['pad']:<14}"
            if n["mar"] != "0px":
                label += f" mar={n['mar']}"
            if n["cols"] != "none":
                label += f" cols={n['cols']}"
            if n["text"]:
                label += f"  '{n['text']}'"
            print(label)


async def main():
    wanted = sys.argv[1:] or ["inventory"]
    for tab in wanted:
        if tab not in TABS:
            print(f"unknown tab: {tab} (inventory|talents|hero)")
            continue
        await probe(tab, TABS[tab])


if __name__ == "__main__":
    asyncio.run(main())
