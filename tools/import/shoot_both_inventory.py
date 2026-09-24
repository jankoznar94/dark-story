#!/usr/bin/env python3
"""Put an IDENTICAL loadout into the PWA and into the port's save, then shoot both.

Everything so far has compared a port frame against a PWA frame that had DIFFERENT
items on (the committed `inventory.png` shows a played save; a fresh port save shows
nothing at all), which makes every pixel diff meaningless. This script removes that
variable:

  1. builds one loadout from real ITEMS ids
  2. builds the SAME loadout in the PWA the way a player does (buy -> equip), then
     shoots `tools/reference/pwa/inventory_gear.png`
  3. writes the same loadout into the port's save (`user://`), shoots the port
  4. prints the numbers from both, side by side

⚠️  THE PWA LOSES ITS SAVE ON EVERY RELOAD — so writing localStorage and reloading
    produces a CLASS-SELECT screen, not an inventory. `loadSave()` ends with

        if (s.hero) { s.hero.maxHp = getHeroMaxHp(); ... }

    and `getHeroMaxHp()` reads the GLOBAL `state`, which at that moment is still `{}`
    (`let state = {}`; `state = loadSave()` only runs after it returns). Every reload
    therefore throws `TypeError: Cannot read properties of undefined (reading 'equip')`
    inside `loadSave`'s own `try`, whose `catch {}` is EMPTY — it swallows the error and
    returns `defaultState()`. The game silently starts over with `heroClass: null`.

    That is why the committed `tools/reference/pwa/inventory_gear.png` is a nearly
    BLANK frame (0.25 % coloured pixels in the doll band against 14.59 % in the port)
    and why every inventory diff measured against it is meaningless.

    The loadout is therefore built IN ONE SESSION with the game's own controls:
    `#testToggle` gives gold (a real control in the page, not a cheat injected here),
    then `game.buyItem(id)` -> `game.equipItemToSlot(idx, slot)`. `saveGame()` runs on
    every change, so localStorage tracks the live state. Never reload between steps.

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
# ⚠️  THE PORT HAS NO ISOLATED `user://` BY DEFAULT — a Godot run reads AND writes
# `~/.local/share/godot/app_userdata/Dungeon Recall/`, which is the PLAYER'S OWN SAVE.
# Writing the measurement loadout there and forgetting to restore it deleted Jan's
# progress twice in one session (145 KB -> 1.4 KB skeletons). `XDG_DATA_HOME` redirects
# the whole app_userdata tree, which is the only isolation that actually holds — so every
# Godot invocation in this script runs under an isolated one and the real save is READ
# ONCE, as a seed, and never written.
ISO_DATA = os.environ.get("DR_ISO_DATA", "/tmp/dr_godot_iso")
ISO_SAVE = os.path.join(ISO_DATA, "godot", "app_userdata", "Dungeon Recall",
                        "dungeon_recall_save.json")
REAL_SAVE = os.path.expanduser(
    "~/.local/share/godot/app_userdata/Dungeon Recall/dungeon_recall_save.json")
SAVE = ISO_SAVE
LS_KEY = "dungeonRecallV7"

# The ONE loadout, in (item id, equip slot) order. Every id exists in ITEMS.json
# (i.e. in the port's table too) and the set covers a tall slot, a square slot, a
# small slot, the belt row and the bag.
#
# ⚠️  `beltPotionSlots` is deliberately NOT part of this: the PWA derives the potion row
# from the BELT (`getTotalPotionSlots()` = `beltRows * 4`, or 4 with no belt), so
# `belt_sash` (beltRows 2) produces EIGHT slots — the PWA's own item overlay says
# "Potion Slots  2 rows (8 slots)". The port's `beltRows * 4` matches. An earlier
# reference frame showed 4 only because its belt was not worn at all.
EQUIP_ORDER = [
    ("belt_sash", "belt"), ("armor_leather", "armor"), ("helm_cap", "helmet"),
    ("shield_buckler", "shield"), ("copperRing", "ring1"), ("boneAmulet", "amulet"),
    ("gloves_leather", "gloves"), ("boots_boots", "boots"), ("blade_scimitar", "weapon"),
]

# What stays in the bag, so the grid is not empty in either frame. Bought but not worn.
#
# ⚠️  `blade_shortSword` IS PART OF THIS LIST, and its absence made the bag unusable as
# evidence: the hero's class KIT equips the start weapon, so the PWA's own save carries it
# back in the bag the moment the scimitar replaces it (measured: `inv` =
# ["blade_shortSword", "armor_ringMail", "helm_helm", "silverRing"]). The port's save
# REPLACES `hero.equip` wholesale, so its bag was three items and every cell held a
# DIFFERENT icon from the PWA's corresponding cell — which makes each cell's pixel
# difference unattributable (a diff there can be the icon, the fill, the border or the
# backing). Same order on both sides, so cell i shows the same item.
#
# `healingPotion` is bought too, but it never lands in the bag: the PWA's `buyItem` puts a
# consumable straight into the first EMPTY BELT slot, which is the state the port's
# `beltPotionSlots` already describes. Without the buy the PWA's belt row is eight empty
# tiles against the port's seven-plus-a-potion, and the belt band reads as 5.9 % differ
# for no reason but the harness.
BAG_ITEMS = ["armor_ringMail", "helm_helm", "silverRing", "healingPotion"]

# The port's save is written directly (it has no shop to drive), and it uses the same
# ids — so the two frames show the same thing.
LOADOUT = {
    "equip": {
        "weapon": "blade_scimitar", "armor": "armor_leather",
        "helmet": "helm_cap", "shield": "shield_buckler",
        "ring1": "copperRing", "ring2": None, "amulet": "boneAmulet",
        "belt": "belt_sash", "gloves": "gloves_leather", "boots": "boots_boots",
        "beltPotionSlots": ["healingPotion", None, None, None,
                            None, None, None, None],
    },
    "inventory": ["armor_ringMail", "helm_helm", "silverRing"],
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

        # 1. class on a fresh load, through the handler that actually works.
        #    Start from a CLEAN save so the bag really holds what we put there and a
        #    leftover item from an earlier run cannot silently fill a slot.
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

        # 2. Build the loadout IN THIS SESSION. See the module docstring: a reload here
        #    would throw inside `loadSave` and silently reset the game to the class picker.
        #    `#testToggle` is the page's own gold/test control.
        await ev("(() => { const t=document.getElementById('testToggle'); if (t) t.click(); })()")
        await asyncio.sleep(1.5)
        # ⚠️  `toggleTestMode()` SETS `talentPoints = 50` AND `attrPoints = 150`, and that is
        # NOT a cosmetic side effect: it is what makes the two `.tab-badge` pills appear
        # (Skills "50", Stats "150"), and the pills are 1 733 differing pixels of the frame.
        # The PORT's save has 0 of each, so a frame shot after this leaves the port without
        # badges through no fault of its own — the diff would be measuring a state the port
        # was never told to reproduce. The loadout below therefore carries the same two
        # numbers, so both sides show what the player is shown.
        built = []
        for item, slot in EQUIP_ORDER:
            await ev(f"(() => {{ try {{ game.buyItem('{item}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.35)
            inv = await ev(f"(() => {{ const s=JSON.parse(localStorage.getItem('{LS_KEY}')||'{{}}');"
                          f" return JSON.stringify((s.hero||{{}}).inventory||[]); }})()")
            try:
                rows = json.loads(inv)
            except (TypeError, ValueError):
                rows = []
            idx = None
            for i, entry in enumerate(rows):
                eid = entry.get("id") if isinstance(entry, dict) else entry
                if eid == item:
                    idx = i
                    break
            if idx is None:
                built.append(f"{item}: NOT BOUGHT")
                continue
            await ev(f"(() => {{ try {{ game.equipItemToSlot({idx}, '{slot}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.35)
            got = await ev(f"(() => {{ const s=JSON.parse(localStorage.getItem('{LS_KEY}')||'{{}}');"
                           f" return (((s.hero||{{}}).equip)||{{}})['{slot}'] || null; }})()")
            built.append(f"{item} -> {slot}: {got}")
        # ...and what stays in the bag (bought, not worn)
        for item in BAG_ITEMS:
            await ev(f"(() => {{ try {{ game.buyItem('{item}'); }} catch(e) {{}} }})()")
            await asyncio.sleep(0.3)
        out["fill"] = built

        # the live save, which is what the renderer reads
        check = await ev(
            "(() => { const s=JSON.parse(localStorage.getItem('" + LS_KEY + "')||'{}');"
            " return {cls:s.heroClass,"
            "         weapon:(s.hero||{}).equip ? s.hero.equip.weapon : null,"
            "         belt:(s.hero||{}).equip ? s.hero.equip.belt : null,"
            "         invsz:(s.hero ? s.hero.inventory : []).length}; })()")
        out["bagIds"] = await ev(
            "(() => { const s=JSON.parse(localStorage.getItem('" + LS_KEY + "')||'{}');"
            " return ((s.hero||{}).inventory||[]).map(e => (e && e.id) || e); })()")
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
  const out = {slots: {}, bag: [], potion: null, wrap: null, grid: null,
               potionWrap: null, potionCount: 0};
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
  // The two containers the bag sits in, and the belt row's own box. Measured because a
  // cell that moved by 4px can be a cell, a grid or a wrap — and the diff cannot say which.
  const pw = document.querySelector('.inv-potion-slots');
  out.potionWrap = pw ? box(pw) : null;
  out.potionCount = document.querySelectorAll('.inv-potion-slot').length;
  const w = document.getElementById('invGridWrap');
  out.wrap = w ? box(w) : null;
  const g = document.getElementById('invGrid');
  out.grid = g ? box(g) : null;
  // The paper doll's own container and the pane it lives in. The port's whole doll sits a
  // uniform 4px above the PWA's, so the offset is ONE gap at the doll's top edge and not a
  // row height — these two rects are what say which of them carries it.
  const ep = document.querySelector('.inv-equip-panel');
  out.equipPanel = ep ? box(ep) : null;
  if (ep) {
    const ecs = getComputedStyle(ep);
    out.equipStyle = {display: ecs.display, gap: ecs.gap, padding: ecs.padding,
                      margin: ecs.margin,
                      rows: ecs.gridTemplateRows,
                      cols: ecs.gridTemplateColumns};
  }
  const pane = document.getElementById('invGridWrap') &&
               document.getElementById('invGridWrap').parentElement;
  out.paneParent = pane ? box(pane) : null;
  const scr = document.getElementById('inventoryScreen');
  out.invScreen = scr ? box(scr) : null;
  if (scr) {
    const scs = getComputedStyle(scr);
    out.invScreenStyle = {padding: scs.padding, margin: scs.margin, display: scs.display,
                          gap: scs.gap};
  }
  // The modal's own head: `.modal-content` and the `.combined-tabs` strip. `#inventoryScreen`
  // starts 4px lower in the PWA than in the port, and the tabs strip is the only thing above
  // it — so the strip's own height is the suspect, not the pane's contents.
  const mc = document.querySelector('.modal-content');
  out.modalContent = mc ? box(mc) : null;
  const ct = document.querySelector('.combined-tabs');
  out.tabs = ct ? box(ct) : null;
  if (ct) {
    const tcs = getComputedStyle(ct);
    out.tabsStyle = {display: tcs.display, padding: tcs.padding, margin: tcs.margin,
                     gap: tcs.gap, minHeight: tcs.minHeight, height: tcs.height,
                     alignItems: tcs.alignItems};
  }
  const tab = ct && ct.querySelector('.combined-tab, button, [data-tab]');
  out.tab0 = tab ? box(tab) : null;
  if (tab) {
    const bcs = getComputedStyle(tab);
    out.tab0Style = {padding: bcs.padding, margin: bcs.margin, fontSize: bcs.fontSize,
                     lineHeight: bcs.lineHeight, height: bcs.height, border: bcs.borderTopWidth,
                     display: bcs.display};
  }
  // WHO makes the strip 55 tall when its tallest declared child is 32? List every child's
  // own box, so the extra 3px is attributed instead of guessed at (the port's strip is 52).
  out.tabsChildren = [];
  if (ct) {
    for (const child of ct.children) {
      const ccs = getComputedStyle(child);
      out.tabsChildren.push({tag: child.tagName, cls: child.className,
                             box: box(child), h: ccs.height, lh: ccs.lineHeight,
                             mb: ccs.marginBottom, mt: ccs.marginTop,
                             pt: ccs.paddingTop, pb: ccs.paddingBottom,
                             fs: ccs.fontSize, flex: ccs.flex, alignSelf: ccs.alignSelf});
    }
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
    """Write the same loadout into an ISOLATED Godot save and shoot the port.

    The isolated tree is seeded from the REAL save when one exists, so the frame still
    shows a played state (`townPortalCount > 0` changes the result page, and an empty bag
    makes the grid read as invented) — but nothing this function writes can reach the
    player's own file. See the module-level `ISO_DATA` note: the earlier version wrote the
    real save and relied on restoring it, which cost Jan his progress twice.
    """
    os.makedirs(os.path.dirname(ISO_SAVE), exist_ok=True)
    # ⚠️  RE-SEEDED FROM THE REAL SAVE ON EVERY RUN, not only when the isolated file is
    # missing. A stale isolated save keeps whatever the last `--commit`-style run left in it,
    # so a measurement could silently show a previous loadout. The real save is only ever
    # READ (its size is asserted below), which is the property that matters.
    # `DR_ISO_RESET=0` keeps a hand-built isolated save for iterating on one number.
    if os.environ.get("DR_ISO_RESET", "1") != "0" or not os.path.exists(ISO_SAVE):
        if os.path.exists(REAL_SAVE):
            with open(REAL_SAVE) as fh:
                seed = fh.read()
            with open(ISO_SAVE, "w") as fh:
                fh.write(seed)
    if not os.path.exists(ISO_SAVE):
        return {"error": "no isolated save to seed — run the game once, or pass DR_SEED_SAVE"}
    with open(ISO_SAVE) as fh:
        data = json.load(fh)
    data.setdefault("hero", {})
    data["hero"]["equip"] = dict(LOADOUT["equip"])
    # ⚠️  THE BAG IS THE PWA'S OWN, NOT A HAND-WRITTEN THREE. `_can_equip` / the PWA's
    # `buyItem` decide where an item lands, and the class kit already put the start weapon
    # back into the bag — so a bag written by hand here shows different icons in the same
    # cells as the PWA (measured: `blade_shortSword` in the PWA's slot 0 where the port had
    # `armor_ringMail`). Read the PWA measurement the run just produced (`pwa_measure.json`
    # is written before this function runs) and use its own order; fall back to the declared
    # list only when there is no PWA side to copy.
    pwa = None
    try:
        with open("/tmp/pwa_measure.json") as fh:
            pwa = json.load(fh)
    except (OSError, ValueError):
        pwa = None
    bag = LOADOUT["inventory"]
    if isinstance(pwa, dict) and isinstance(pwa.get("bagIds"), list) and pwa["bagIds"]:
        bag = list(pwa["bagIds"])
    data["hero"]["inventory"] = bag
    # Match the PWA side, which runs the page's own `#testToggle`: `talentPoints = 50`,
    # `hero.attrPoints = 150`. Both are what raise the two `.tab-badge` pills.
    data["talentPoints"] = 50
    data["hero"]["attrPoints"] = 150
    data["hero"]["level"] = 50
    data["hero"]["maxHp"] = 255
    data["hero"]["maxMana"] = 49
    with open(ISO_SAVE, "w") as fh:
        json.dump(data, fh, indent=1)

    out = os.path.join(ROOT, "tools", "reference", "port2", "inventory_gear.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)
    cmd = [GODOT, "--path", ROOT, "--rendering-driver", "opengl3",
           "--script", "res://tools/capture_screen.gd", "--",
           "--screen", "character@inventory", "--out", out, "--frames", "60"]
    env = dict(os.environ)
    env["XDG_DATA_HOME"] = ISO_DATA
    try:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=180,
                              env=env)
    except subprocess.TimeoutExpired:
        return {"error": "godot timed out"}
    tail = [l for l in proc.stdout.splitlines() if "capture:" in l]
    return {"shot": out if os.path.exists(out) else None,
            "stdout": tail, "rc": proc.returncode,
            "isolated": ISO_SAVE,
            "real_save": os.path.getsize(REAL_SAVE) if os.path.exists(REAL_SAVE) else None}


def port_measure():
    """Measure the PORT's own boxes, so the two sides can be compared rect by rect.

    `probe_inventory_slots.gd` prints the doll and the bag cells but none of the CONTAINERS
    between them, and a cell measured 4px off its PWA counterpart is not evidence of which
    of the three (wrap / grid / cell) is wrong. This prints all three.
    """
    cmd = [GODOT, "--path", ROOT, "--rendering-driver", "opengl3",
           "--script", "res://tools/probe_bag_geometry.gd"]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return {"error": "godot timed out"}
    vals = {}
    for line in proc.stdout.splitlines():
        line = line.strip()
        if "=" in line and line.split("=")[0].isupper():
            k, _, v = line.partition("=")
            vals[k] = v.strip()
    return vals


async def main():
    print("=== PWA ===")
    p = await pwa_side()
    print("  fill   :", p.get("fill"))
    print("  saved  :", p.get("saved"))
    print("  opened :", p.get("opened"))
    print("  shot   :", p.get("shot"))
    # ⚠️  THE BAG IDS RIDE IN THE SAME FILE the port side reads, and they are the PWA's
    # OWN `hero.inventory` order — not REPORT_JS's output, which is the DOM measurement and
    # knows nothing about ids. Writing only `measure` here silently dropped them, the port
    # fell back to its hand-written three, and every bag cell then held a DIFFERENT icon
    # from its PWA counterpart (the class kit puts `blade_shortSword` back in the bag).
    measure = p.get("measure") or {}
    if isinstance(measure, dict):
        measure["bagIds"] = p.get("bagIds") or []
    with open("/tmp/pwa_measure.json", "w") as fh:
        json.dump(measure, fh, indent=1)
    print("  bag ids:", p.get("bagIds"))
    print("  measure: /tmp/pwa_measure.json")

    print("=== PORT ===")
    q = port_side()
    print("  rc     :", q.get("rc"))
    for line in q.get("stdout", []):
        print(" ", line)
    print("  shot   :", q.get("shot"))
    print("  isolated:", q.get("isolated"))
    print("  real save (must be unchanged):", q.get("real_save"), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
