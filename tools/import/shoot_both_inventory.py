#!/usr/bin/env python3
"""Put an IDENTICAL loadout into the PWA and into the port's save, then shoot both.

Everything so far has compared a port frame against a PWA frame that had DIFFERENT
items on (the committed `inventory.png` shows a played save; a fresh port save shows
nothing at all), which makes every pixel diff meaningless. This script removes that
variable:

  1. builds one loadout from real ITEMS ids
  2. writes it into the PWA's save (localStorage `dungeonRecallV7`), reloads, shoots
     `tools/reference/pwa/inventory_gear.png`
  3. writes the same loadout into the port's save (`user://`), shoots the port
  4. prints the numbers from both, side by side

  python3 tools/import/shoot_both_inventory.py
"""

import asyncio
import base64
import json
import os
import subprocess
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
REF = os.path.join(ROOT, "tools", "reference")
GODOT = os.path.expanduser("~/tools/godot/godot4")
SAVE = os.path.expanduser(
    "~/.local/share/godot/app_userdata/Dungeon Recall/dungeon_recall_save.json")
LS_KEY = "dungeonRecallV7"

# ONE loadout for both. Every id exists in ITEMS.json (i.e. in the port's table too),
# and the set covers a tall slot, a square slot, a small slot, the belt row and the bag.
LOADOUT = {
    "equip": {
        "weapon": "blade_shortSword", "armor": "armor_leather",
        "helmet": "helm_cap", "shield": "shield_buckler",
        "ring1": "copperRing", "ring2": None, "amulet": "boneAmulet",
        "belt": "belt_sash", "gloves": "gloves_leather", "boots": "boots_boots",
        "beltPotionSlots": ["healingPotion", None, None, None],
    },
    "inventory": ["armor_ringMail", "helm_helm", "silverRing", "blade_scimitar"],
}


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def pwa_side():
    targets = json.loads(urllib.request.urlopen(
        f"http://127.0.0.1:{CDP_PORT}/json").read())
    page = next(t for t in targets if t["type"] == "page")
    out = {"measure": None, "shot": None, "fill": None}
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

        # 1. class on a fresh load, through the handler that actually works
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

        # 2. splice the loadout straight into the SAVED json, then reload so the game
        #    boots FROM it — much more reliable than patching window.state, which is only
        #    a snapshot and gets overwritten by the next save.
        payload = json.dumps(LOADOUT)
        patched = await ev(
            "(() => {"
            f" const s = JSON.parse(localStorage.getItem('{LS_KEY}') || 'null');"
            " if (!s || !s.hero) return 'no save';"
            f" const L = {payload};"
            " s.hero.equip = Object.assign(s.hero.equip || {}, L.equip);"
            " s.hero.inventory = L.inventory;"
            f" localStorage.setItem('{LS_KEY}', JSON.stringify(s));"
            " return 'patched'; })()")
        out["fill"] = patched
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4.5)
        # the save is loaded now; open the inventory tab
        check = await ev(
            "(() => { const s=JSON.parse(localStorage.getItem('" + LS_KEY + "')||'{}');"
            " return {weapon:(s.hero||{}).equip ? s.hero.equip.weapon : null,"
            "         invsz:(s.hero ? s.hero.inventory : []).length}; })()")
        out["saved"] = check
        # OPEN the modal and ASSERT it opened. `game.showScreen('inventory')` LOOKS like the
        # right call and prints nothing when it fails: the PWA's `showScreen` starts with a
        # guard that bounces everything to the class picker while `state.heroClass` is unset,
        # so a run that never picked a class leaves the modal `hidden`, every rect 0x0 and
        # the shot a CLASS-SELECT screen saved under `inventory_gear.png`. That is how this
        # script produced `diff 51.75 %` — a real frame of the wrong screen, which is a
        # confident number and a meaningless one.
        out["opened"] = await open_inventory(ev)
        out["measure"] = await ev(REPORT_JS)
        shot = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
        path = os.path.join(REF, "pwa", "inventory_gear.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(base64.b64decode(shot["data"]))
        out["shot"] = path
    return out


REPORT_JS = """
(() => {
  const box = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)];
  };
  const out = {slots: {}, bag: [], potion: null};
  document.querySelectorAll('.inv-equip-slot').forEach(el => {
    const cs = getComputedStyle(el);
    const img = el.querySelector('img');
    const ics = img ? getComputedStyle(img) : null;
    out.slots[el.id] = {
      box: box(el), overflow: cs.overflow, bg: cs.backgroundColor,
      border: cs.borderTopWidth + ' ' + cs.borderTopColor + ' ' + cs.borderTopStyle,
      radius: cs.borderRadius,
      icon_box: box(el.querySelector('.inv-slot-icon')),
      img_box: img ? box(img) : null,
      fit: ics ? ics.objectFit : null,
      img_bg: ics ? ics.backgroundColor : null,
    };
  });
  document.querySelectorAll('.inv-grid .chest-cell').forEach((el, i) => {
    if (i > 3) return;
    const cs = getComputedStyle(el);
    const img = el.querySelector('img');
    const ics = img ? getComputedStyle(img) : null;
    out.bag.push({box: box(el), bg: cs.backgroundColor, overflow: cs.overflow,
                  radius: cs.borderRadius,
                  border: cs.borderTopWidth + ' ' + cs.borderTopColor,
                  icon_box: box(el.querySelector('.cell-icon')),
                  img_box: img ? box(img) : null,
                  fit: ics ? ics.objectFit : null});
  });
  const p = document.querySelector('.inv-potion-slot');
  if (p) {
    const pcs = getComputedStyle(p);
    const pi = p.querySelector('img');
    const pics = pi ? getComputedStyle(pi) : null;
    out.potion = {box: box(p), bg: pcs.backgroundColor, overflow: pcs.overflow,
                  radius: pcs.borderRadius,
                  border: pcs.borderTopWidth + ' ' + pcs.borderTopColor,
                  img_box: pi ? box(pi) : null, fit: pics ? pics.objectFit : null};
  }
  return out;
})()
"""


async def open_inventory(ev):
    """Open the character modal on the Inventory tab and PROVE it is up.

    `game.showScreen('inventory')` is the call the PWA's own nav bar makes, and it is a
    silent no-op whenever `state.heroClass` is unset — `showScreen` bounces to the class
    picker instead. So the check is not "did the call return", it is "does a slot have a
    box", and a failure is reported rather than measured around.
    """
    await ev("(() => { try { game.showScreen('inventory'); }"
             " catch (e) { game.openModal('inventory'); } })()")
    for _ in range(24):
        if await ev("(() => { const m=document.getElementById('modalOverlay');"
                    " const s=document.querySelector('.inv-equip-slot');"
                    " return !!m && !m.classList.contains('hidden')"
                    "   && !!s && s.getBoundingClientRect().width > 0; })()") is True:
            return "open"
        # The fallback for a run whose class was restored from the save but whose class
        # cards never rendered: drive the handler the PWA itself wires.
        await ev("(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
                 " if (b) b.click(); })()")
        await ev("(() => { try { game.openModal('inventory'); } catch (e) {} })()")
        await asyncio.sleep(0.5)
    return "FAILED: the inventory never laid out — every rect would be 0"


def port_side():
    """Write the same loadout into the port's save and shoot it."""
    backup = SAVE + ".bak"
    if os.path.exists(SAVE):
        with open(SAVE) as fh:
            original = fh.read()
        with open(backup, "w") as fh:
            fh.write(original)
    with open(SAVE) as fh:
        data = json.load(fh)
    data["hero"]["equip"] = dict(LOADOUT["equip"])
    data["hero"]["inventory"] = list(LOADOUT["inventory"])
    with open(SAVE, "w") as fh:
        json.dump(data, fh, indent=1)

    out = os.path.join(ROOT, "tools", "reference", "port2", "inventory_gear.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)
    cmd = [GODOT, "--path", ROOT, "--rendering-driver", "opengl3",
           "--script", "res://tools/capture_screen.gd", "--",
           "--screen", "character@inventory", "--out", out, "--frames", "60"]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return {"error": "godot timed out"}
    tail = [l for l in proc.stdout.splitlines() if "capture:" in l]
    return {"shot": out if os.path.exists(out) else None,
            "stdout": tail, "rc": proc.returncode,
            "backup": backup if os.path.exists(backup) else None}


async def main():
    print("=== PWA ===")
    p = await pwa_side()
    print("  fill   :", p.get("fill"))
    print("  saved  :", p.get("saved"))
    print("  opened :", p.get("opened"))
    print("  shot   :", p.get("shot"))
    with open("/tmp/pwa_measure.json", "w") as fh:
        json.dump(p.get("measure"), fh, indent=1)
    print("  measure: /tmp/pwa_measure.json")

    print("=== PORT ===")
    q = port_side()
    print("  rc     :", q.get("rc"))
    for line in q.get("stdout", []):
        print(" ", line)
    print("  shot   :", q.get("shot"))
    print("  backup :", q.get("backup"))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
