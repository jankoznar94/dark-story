#!/usr/bin/env python3
"""Measure the LIVE PWA's inventory slots with the inventory actually OPEN and a real
save loaded — the specification for the port's slot rendering.

Two runs of this script produced `box: 0x0` for every slot, because the measurement
happened while the modal was still hidden. So it now asserts the modal is up (and one
slot has a non-zero box) BEFORE it reports, and exits non-zero if it is not:

  python3 tools/import/probe_slots_live.py

Requires `python3 -m http.server 8099` in the PWA's dist/ and chromium on 9222.
"""

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
HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.normpath(os.path.join(HERE, "..", "reference"))

LOADOUT = {
    "equip": {
        "weapon": "blade_shortSword", "armor": "armor_leather",
        "helmet": "helmet_linen_hood", "shield": "shield_wooden",
        "ring1": "ring_copper", "ring2": None, "amulet": "amulet_bone",
        "belt": "belt_cloth", "gloves": "gloves_leather", "boots": "boots_boots",
        "beltPotionSlots": ["healingPotion", None, None, None],
    },
    "inventory": ["armor_chainmail", "helmet_iron_helm", "ring_silver", "blade_scimitar"],
}

REPORT = """
(() => {
  const out = {slots: {}, bag: [], potion: null, modal: null,
               slots_visible: 0, first_slot_box: null};
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)];
  };
  const modal = document.querySelector('.modal-content');
  out.modal = box(modal);
  out.modal_visible = modal ? getComputedStyle(modal).display !== 'none' : false;
  document.querySelectorAll('.inv-equip-slot').forEach((el, i) => {
    const cs = getComputedStyle(el);
    const img = el.querySelector('img');
    const ics = img ? getComputedStyle(img) : null;
    const b = box(el);
    if (b && b[2] > 0) {
      out.slots_visible += 1;
      if (!out.first_slot_box) out.first_slot_box = b;
    }
    out.slots[el.id] = {
      box: b, overflow: cs.overflow, bg: cs.backgroundColor,
      border: cs.borderTopWidth + ' ' + cs.borderTopColor + ' ' + cs.borderTopStyle,
      radius: cs.borderRadius, pad: cs.padding,
      icon_box: box(el.querySelector('.inv-slot-icon')),
      img_box: img ? box(img) : null, fit: ics ? ics.objectFit : null,
      img_bg: ics ? ics.backgroundColor : null,
      img_css: ics ? ics.width + ' x ' + ics.height : null,
    };
  });
  document.querySelectorAll('.inv-grid .chest-cell').forEach((el, i) => {
    if (i > 4) return;
    const cs = getComputedStyle(el);
    const img = el.querySelector('img');
    const ics = img ? getComputedStyle(img) : null;
    out.bag.push({box: box(el), bg: cs.backgroundColor, overflow: cs.overflow,
                  radius: cs.borderRadius,
                  border: cs.borderTopWidth + ' ' + cs.borderTopColor,
                  icon_box: box(el.querySelector('.cell-icon')),
                  img_box: img ? box(img) : null, fit: ics ? ics.objectFit : null,
                  img_css: ics ? ics.width + ' x ' + ics.height : null,
                  img_bg: ics ? ics.backgroundColor : null,
                  border_color: cs.borderTopColor});
  });
  const p = document.querySelector('.inv-potion-slot');
  if (p) {
    const pcs = getComputedStyle(p);
    const pi = p.querySelector('img');
    const pics = pi ? getComputedStyle(pi) : null;
    out.potion = {box: box(p), bg: pcs.backgroundColor, overflow: pcs.overflow,
                  radius: pcs.borderRadius,
                  border: pcs.borderTopWidth + ' ' + pcs.borderTopColor,
                  img_box: pi ? box(pi) : null, fit: pics ? pics.objectFit : null,
                  img_bg: pics ? pics.backgroundColor : null};
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


async def main():
    targets = json.loads(urllib.request.urlopen(
        f"http://127.0.0.1:{CDP_PORT}/json").read())
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
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})

        async def ev(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True,
                            "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:300]}
            return r.get("result", {}).get("value")

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
        await asyncio.sleep(1.5)

        payload = json.dumps(LOADOUT)
        print("patch:", await ev(
            "(() => {"
            f" const s = JSON.parse(localStorage.getItem('{LS_KEY}') || 'null');"
            " if (!s || !s.hero) return 'no save';"
            f" const L = {payload};"
            " s.hero.equip = Object.assign(s.hero.equip || {}, L.equip);"
            " s.hero.inventory = L.inventory;"
            f" localStorage.setItem('{LS_KEY}', JSON.stringify(s));"
            " return 'patched'; })()"))

        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4.5)
        print("loaded:", await ev(
            "(() => { const s=JSON.parse(localStorage.getItem('" + LS_KEY + "')||'{}');"
            " return {weapon:(s.hero||{}).equip ? s.hero.equip.weapon : null,"
            "         inv:(s.hero||{}).inventory ? s.hero.inventory.length : 0}; })()"))

        # OPEN the modal and WAIT until a slot actually has a box — the guard the two
        # earlier runs were missing (every measurement came back 0x0 and meant nothing).
        await ev("game.showScreen('inventory')")
        ok = False
        for _ in range(20):
            if await ev("(() => { const s=document.querySelector('.inv-equip-slot');"
                        " return !!s && s.getBoundingClientRect().width > 0; })()") is True:
                ok = True
                break
            await asyncio.sleep(0.4)
        print("modal open:", ok)
        if not ok:
            print("REFUSING to report: the inventory never laid out, every rect would be 0",
                  file=sys.stderr)
            return 2

        data = await ev(REPORT)
        with open("/tmp/pwa_slots_live.json", "w") as fh:
            json.dump(data, fh, indent=1)
        print("slots_visible =", data.get("slots_visible"),
              "first_slot_box =", data.get("first_slot_box"))
        print(json.dumps(data, indent=1))

        shot = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
        path = os.path.join(REF, "pwa", "inventory_gear.png")
        with open(path, "wb") as fh:
            fh.write(base64.b64decode(shot["data"]))
        print("shot:", path)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
