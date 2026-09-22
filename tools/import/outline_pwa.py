#!/usr/bin/env python3
"""Dump the LIVE PWA's element tree for one screen — tag, classes, rect, key styles.

  python3 tools/import/outline_pwa.py map
  python3 tools/import/outline_pwa.py map chest shop

The CSS is the spec, but the CSS alone does not say which of 2 400 rules apply to the
screen that is actually up. This walks the visible subtree the way a browser lays it
out, so the port can be built against the REAL structure — the same lesson that showed
`inventory`/`talents`/`hero` are one modal with three tabs and not three screens.
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

ROOTS = {
    "town": "townScreen",
    "map": "mapScreen",
    "chest": "chestScreen",
    "shop": "shopScreen",
    "gamble": "gambleScreen",
    "craft": "craftScreen",
    "bestiary": "bestiaryScreen",
    "spellbook": "spellbookScreen",
}

# The modal is not a screen: openModal() builds one .modal-content with three panes.
MODAL_TABS = {"inventory": 0, "talents": 1, "hero": 2}

WALK = r"""
(() => {
  const root = document.querySelector(ARG_ROOT);
  if (!root) return {error: 'no root'};
  const out = [];
  const walk = (el, depth) => {
    if (depth > 6) return;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    if (r.width < 0.5 || r.height < 0.5) return;
    out.push({
      d: depth,
      t: el.tagName.toLowerCase(),
      c: el.className.toString().slice(0, 70),
      id: el.id || '',
      x: +r.x.toFixed(0), y: +r.y.toFixed(0),
      w: +r.width.toFixed(0), h: +r.height.toFixed(0),
      bg: cs.backgroundColor,
      bd: cs.borderTopWidth + ' ' + cs.borderTopColor,
      rad: cs.borderRadius,
      fs: cs.fontSize + '/' + cs.fontWeight,
      pad: cs.padding,
      txt: (el.children.length === 0 ? el.textContent.trim().slice(0, 40) : ''),
    });
    for (const k of el.children) walk(k, depth + 1);
  };
  walk(root, 0);
  return {items: out};
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
            if name in ROOTS:
                root = "#" + ROOTS[name]
                await evaluate(f"game.showScreen('{name}')")
                await asyncio.sleep(1.2)
            elif name in MODAL_TABS:
                idx = MODAL_TABS[name]
                await evaluate(
                    "(() => { game.showScreen('inventory');"
                    f" const t=[...document.querySelectorAll('.combined-tab')]; t[{idx}].click();"
                    " return 'ok'; })()")
                await asyncio.sleep(1.2)
                root = "#modalOverlay .modal-content"
            else:
                print(f"unknown screen {name}")
                continue
            val = await evaluate(WALK.replace("ARG_ROOT", json.dumps(root)))
            print(f"===== {name}  ({root}) =====")
            if isinstance(val, dict) and "items" in val:
                for it in val["items"]:
                    ind = "  " * it["d"]
                    print(f'{ind}{it["t"]}.{it["c"]} #{it["id"]} '
                          f'[{it["x"]},{it["y"]} {it["w"]}x{it["h"]}] '
                          f'bg={it["bg"]} bd={it["bd"]} r={it["rad"]} f={it["fs"]} p={it["pad"]}'
                          + (f' "{it["txt"]}"' if it["txt"] else ""))
            else:
                print(val)


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:] or ["map"]))
