#!/usr/bin/env python3
"""Measure the LIVE PWA's three inventory blocks AND their children — the specification for
the port's doll, potion row and bag grid.

`probe_pane_pwa.py inventory` walks to depth 7 and prints everything, which is a wall of
output; this prints the three blocks with their computed margins plus each block's own
children, so a height that is 6px off can be aimed at instead of guessed.

  python3 tools/import/probe_blocks_pwa.py
"""

import asyncio
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
LS_KEY = "dungeonRecallV7"

JS = r"""
(() => {
  const bx = el => { if (!el) return null; const r = el.getBoundingClientRect();
    return [Math.round(r.x*10)/10, Math.round(r.y*10)/10,
            Math.round(r.width*10)/10, Math.round(r.height*10)/10]; };
  const cs = el => { const c = getComputedStyle(el); return {
    display: c.display, mt: c.marginTop, mb: c.marginBottom,
    pt: c.paddingTop, pb: c.paddingBottom, pl: c.paddingLeft, pr: c.paddingRight,
    gap: c.gap, bt: c.borderTopWidth, bb: c.borderBottomWidth,
    cols: c.gridTemplateColumns, rows: c.gridTemplateRows, h: c.height }; };
  const out = {screen: null, blocks: {}, children: {}};
  const screen = document.getElementById('inventoryScreen');
  out.screen = {box: bx(screen), css: cs(screen)};
  const ids = ['invEquipPanel', 'invPotionSlots', 'invGridWrap'];
  const seen = {};
  [...screen.children].forEach((el, i) => { seen[i] = el; });
  ids.forEach((id, i) => {
    const el = seen[i];
    if (!el) return;
    out.blocks[id] = {cls: el.className, box: bx(el), css: cs(el)};
    out.children[id] = [...el.children].map(c => ({cls: c.className, box: bx(c), css: cs(c)}));
  });
  const doll = document.querySelector('.inv-doll');
  if (doll) { out.doll = {box: bx(doll), css: cs(doll),
    cells: [...doll.children].map(c => ({cls: c.className, box: bx(c)}))}; }
  const grid = document.querySelector('.inv-grid');
  if (grid) { out.grid = {box: bx(grid), css: cs(grid),
    cells: [...grid.children].slice(0,3).map(c => ({cls: c.className, box: bx(c)}))}; }
  const pots = document.querySelector('.inv-potion-slots');
  if (pots) { out.pots = {box: bx(pots), css: cs(pots),
    cells: [...pots.children].map(c => ({box: bx(c)}))}; }
  return JSON.stringify(out);
})()
"""


async def main():
    targets = json.loads(urllib.request.urlopen(
        f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    async with websockets.connect(page["webSocketDebuggerUrl"],
                                  max_size=64 * 1024 * 1024) as ws:
        mid = 0

        async def send(method, params=None):
            nonlocal mid
            mid += 1
            await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get("id") == mid:
                    return msg.get("result", {})

        async def ev(expr):
            r = await send("Runtime.evaluate", {"expression": expr, "returnByValue": True,
                                                "awaitPromise": True})
            if "exceptionDetails" in r:
                return None
            return r.get("result", {}).get("value")

        await send("Page.enable")
        await send("Runtime.enable")
        await send("Network.enable")
        await send("Network.setCacheDisabled", {"cacheDisabled": True})
        await send("Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        # A real save, so the doll has items in it — an empty doll measures the empty
        # branch and its heights say nothing about a played save.
        await send("Page.navigate", {"url": URL})
        await asyncio.sleep(4.0)
        for _ in range(20):
            if await ev("(() => { const c=document.querySelector('.class-card');"
                        " return !!c && c.getBoundingClientRect().width > 0; })()") is True:
                break
            await asyncio.sleep(0.5)
        await ev("(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
                 " if (b) { b.click(); return; } try { game.selectClass('barbarian'); }"
                 " catch (e) {} })()")
        await asyncio.sleep(1.5)

        # Open the modal and PROVE it: `showScreen('inventory')` is a silent no-op when no
        # class is set (it bounces to the class picker), which yields 0x0 rects.
        opened = False
        for _ in range(20):
            await ev("(() => { try { game.showScreen('inventory'); }"
                     " catch (e) { game.openModal('inventory'); } })()")
            if await ev("(() => { const m=document.getElementById('modalOverlay');"
                        " const s=document.querySelector('.inv-equip-slot');"
                        " return !!m && !m.classList.contains('hidden')"
                        "   && !!s && s.getBoundingClientRect().width > 0; })()") is True:
                opened = True
                break
            await asyncio.sleep(0.5)
        if not opened:
            print("REFUSING to report: the modal never opened, every rect would be 0",
                  file=sys.stderr)
            return 2

        data = json.loads(await ev(JS))
        with open("/tmp/pwa_blocks.json", "w") as fh:
            json.dump(data, fh, indent=1)
        print("screen", data["screen"]["box"], data["screen"]["css"])
        for key, val in data["blocks"].items():
            print(f"\n{key} {val['cls']} box={val['box']}")
            print(f"   css: mt={val['css']['mt']} mb={val['css']['mb']} "
                  f"pt={val['css']['pt']} pb={val['css']['pb']} gap={val['css']['gap']}")
            for c in data["children"].get(key, []):
                print(f"   child {c['cls'][:44]:44s} box={c['box']} "
                      f"gap={c['css']['gap']} cols={c['css']['cols'][:60]}")
        for key in ("doll", "grid", "pots"):
            if key in data:
                print(f"\n{key} box={data[key]['box']} gap={data[key]['css']['gap']} "
                      f"cols={data[key]['css']['cols']}")
                for c in data[key]["cells"]:
                    print(f"   cell {c['box']}")
        return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
