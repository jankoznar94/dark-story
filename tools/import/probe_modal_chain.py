#!/usr/bin/env python3
"""Why is the TALENTS modal 759.6 tall in the PWA and 717 in the port?

`character_modal.gd::_apply_panel_height` clamps the dialog to
`clampf(content_min, 85vh, 90vh)`. The port's talents tab comes out at 85vh (717) and the
PWA's at 90vh (759.6), so the port believes its content is SHORTER than the PWA's by more
than the clamp can hide. A percentage diff cannot say WHICH box is missing the height.

This prints the whole box chain from `.modal-overlay` down to the active pane on EACH of
the three tabs, with `getBoundingClientRect().height` AND `scrollHeight` (so a box clipped
by `max-height` is visible), plus the computed `height`/`min-height`/`max-height`/`flex`
of every step. One fresh page load per tab: `openModal()` moves the real screens into
wrappers inside itself and throws from the third open on.

  python3 tools/import/probe_modal_chain.py
"""

import asyncio
import json
import sys
import urllib.request

import websockets

CDP_PORT = 9222
URL = "http://127.0.0.1:8099/index.html"
TABS = {"inventory": 0, "talents": 1, "hero": 2}

CHAIN_JS = r"""
(() => {
  const rows = [];
  const el = (sel) => document.querySelector(sel);
  const box = (e) => {
    if (!e) return null;
    const r = e.getBoundingClientRect();
    const cs = getComputedStyle(e);
    return {y: +r.y.toFixed(1), h: +r.height.toFixed(1),
            scroll: e.scrollHeight, client: e.clientHeight,
            height: cs.height, minH: cs.minHeight, maxH: cs.maxHeight,
            flex: cs.flex, display: cs.display, pad: cs.padding,
            margin: cs.margin, overflow: cs.overflowY,
            minHeightComputed: cs.minHeight};
  };
  const chain = [
    ['#modalOverlay', '#modalOverlay'],
    ['.modal-content', '.modal-content'],
    ['.modal-body', '.modal-body'],
    ['.combined-tabs', '.combined-tabs'],
    ['screen', '.combined-screen.active'],
    ['screen.container', null],
  ];
  for (const [label, sel] of chain) {
    if (sel) rows.push([label, box(el(sel))]);
  }
  const scr = el('.combined-screen.active');
  if (scr) {
    rows.push(['screen>first', box(scr.firstElementChild)]);
    rows.push(['flex-between', box(scr.querySelector('.flex-between'))]);
    rows.push(['talent-schools', box(scr.querySelector('.talent-schools'))]);
    rows.push(['talent-tree', box(scr.querySelector('.talent-tree'))]);
    rows.push(['talent-tree-content', box(scr.querySelector('.talent-tree-content'))]);
    rows.push(['talents-reset-wrap', box(scr.querySelector('.talents-reset-wrap'))]);
    rows.push(['skill-info-panel', box(scr.querySelector('.skill-info-panel'))]);
  }
  // Does the page itself scroll? An overlay that scrolls is a different bug from a
  // box that is simply short.
  rows.push(['body', {y: 0, h: document.body.scrollHeight,
                      scroll: document.body.scrollHeight,
                      client: innerHeight, height: getComputedStyle(document.body).height,
                      minH: '0', maxH: 'none', flex: '-', display: 'block', pad: '0',
                      margin: '0', overflow: getComputedStyle(document.body).overflowY,
                      minHeightComputed: '0'}]);
  return {rows: rows, innerHeight: innerHeight, innerWidth: innerWidth};
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


async def one_tab(ws, mid_box, tab_name, index):
    await send(ws, mid_box[0], "Page.navigate", {"url": URL})
    mid_box[0] += 1
    await asyncio.sleep(4.0)

    async def ev(expr):
        r = await send(ws, mid_box[0], "Runtime.evaluate",
                       {"expression": expr, "returnByValue": True, "awaitPromise": True})
        mid_box[0] += 1
        if "exceptionDetails" in r:
            return {"__error__": str(r["exceptionDetails"])[:300]}
        return r.get("result", {}).get("value")

    # The class first: `showScreen` bounces to the class picker while it is unset.
    await ev("(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
             " if (b) { b.click(); return 'ok'; } return 'no-card'; })()")
    await asyncio.sleep(2.0)
    # Open the modal, then click the tab BY INDEX (a label lookup matches the badge span
    # and the click is swallowed — that is what made two of ten references wrong before).
    await ev("(() => { try { game.openModal('inventory'); } catch(e) { return 'ERR'; } return 'ok'; })()")
    for _ in range(20):
        if await ev("(() => { const m=document.getElementById('modalOverlay');"
                    " return !!m && !m.classList.contains('hidden'); })()") is True:
            break
        await asyncio.sleep(0.5)
    moved = await ev(f"""(() => {{
      const tabs = document.querySelectorAll('.combined-tab');
      if (tabs.length <= {index}) return 'no-tab';
      tabs[{index}].click();
      return 'clicked';
    }})()""")
    await asyncio.sleep(1.2)
    active = await ev("""(() => {
      const a = document.querySelector('.combined-screen.active');
      return a ? (a.id || a.className) : null;
    })()""")
    data = await ev(CHAIN_JS)
    return moved, active, data


async def main():
    targets = json.loads(urllib.request.urlopen(
        f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"],
                                  max_size=64 * 1024 * 1024) as ws:
        box = [1]
        await send(ws, box[0], "Page.enable")
        box[0] += 1
        await send(ws, box[0], "Runtime.enable")
        box[0] += 1
        await send(ws, box[0], "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        box[0] += 1
        for name, idx in TABS.items():
            moved, active, data = await one_tab(ws, box, name, idx)
            print(f"=== {name} (tab index {idx}) click={moved} active={active} ===")
            for label, b in data.get("rows", []):
                if b is None:
                    print(f"  {label:24s} ABSENT")
                    continue
                print(f"  {label:24s} y={b['y']:7.1f} h={b['h']:7.1f} "
                      f"scroll={b['scroll']:5d} client={b['client']:5d} "
                      f"css_h={b['height']:>8s} min={b['minH']:>8s} max={b['maxH']:>8s} "
                      f"flex={b['flex']:>8s} ovf={b['overflow']}")
            print(f"  viewport innerHeight={data.get('innerHeight')} "
                  f"85vh={0.85 * data.get('innerHeight', 0):.1f} "
                  f"90vh={0.9 * data.get('innerHeight', 0):.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
