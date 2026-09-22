#!/usr/bin/env python3
"""Shoot the LIVE PWA's arena at a chosen moment of a real fight.

The arena is the one screen whose look depends on TIME: the swing rings are mid-sweep,
the hero lunges, floating damage text is up. A screenshot taken on frame zero is not a
reference for a fight in progress, so this starts a real fight, waits, then shoots —
and prints the state it shot (HP, mana, ring offsets) so the port's frame can be compared
against the same moment instead of against a guess.

  python3 tools/import/shoot_pwa_arena.py 1 1 1.2 /tmp/pwa_arena.png

Requires: `python3 -m http.server 8099` inside dist/, chromium on 9222.
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

STATE = r"""
(() => {
  const t = (sel) => { const e=document.querySelector(sel); return e ? e.textContent.trim() : null; };
  const off = (id) => { const e=document.getElementById(id); return e ? Math.round(+e.style.strokeDashoffset||0) : null; };
  const w = (sel) => { const e=document.querySelector(sel); return e ? e.style.width : null; };
  return {
    heroHp: t('#mbPlayerArenaHp span'), hpW: w('#mbPlayerArenaHpFill'),
    mana: t('#mbPlayerArenaMana span'), manaW: w('#mbPlayerArenaManaFill'),
    enemyHp: t('#mbHpLabel'), enemyName: t('#mbEnemyName'),
    cPlayer: off('mbPlayerTimerCircle'), cOffhand: off('mbOffhandTimerCircle'),
    cEnemy: off('mbEnemyTimerCircle'),
    level: t('#mbLevelLabel'), xpW: w('#mbXpBarFill'),
    fight: (() => { const l = document.querySelector('.battle-header, #mbHeader'); return l ? l.textContent.trim() : null; })(),
  };
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


async def main(act, stop, seconds, out):
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

        # Pick a class. `game.selectClass()` is the ONLY route that still works here:
        # the `.class-card` click is a dead control in the current build — neither a
        # synthetic click nor a real CDP mouse event at the card's own centre runs the
        # handler, and the card is visible and not covered. `shoot_pwa.py` still clicks it,
        # so its "class: clicked" line is not evidence that a class was ever chosen.
        #
        # The proof of the kit is the save, read back AFTER the call. It is the app's own
        # persisted output and it is unambiguous: a level-1 hero with no class is 35 max HP,
        # the barbarian's VIT bonus makes it 160 (the same number the port's test asserts).
        # The DOM cannot be used for this — `#mbPlayerArenaHp` is the FIGHT's HP and reads a
        # hard-coded 100/100 until the arena screen takes over.
        cls = await evaluate("(() => { const b=document.querySelector('button[onclick*=\"selectClass\"]');"
                             " if (b) { b.click(); return 'card-handler'; }"
                             " try { game.selectClass('barbarian'); return 'selectClass()'; }"
                             " catch(e) { return 'ERR ' + e.message; } })()")
        await asyncio.sleep(1.0)
        kit = await evaluate("(() => { const s=JSON.parse(localStorage.getItem('dungeonRecallV7')||'{}');"
                             " return { cls: s.heroClass || '', hp: (s.hero||{}).hp,"
                             " maxHp: (s.hero||{}).maxHp, wpn: ((s.hero||{}).equip||{}).weapon }; })()")
        print("class ->", cls, kit)
        if not kit or kit.get("cls") != "barbarian" or int(kit.get("maxHp") or 0) <= 100:
            raise SystemExit("the class kit did not apply - refusing to shoot a frame that "
                             "is a monster fighting a level-1 hero")

        print("enterStop ->", await evaluate(f"(() => {{ game.enterStop({act}, {stop}); return 'ok'; }})()"))

        async def wait_until(expr, what, tries=24):
            for _ in range(tries):
                value = await evaluate(expr)
                if value:
                    return value
                await asyncio.sleep(0.5)
            raise SystemExit(f"timed out waiting for {what}")

        # `enterStop` runs a screen transition: the fight does not exist for ~2 s, and a
        # frame shot on a fixed sleep lands before it. Wait for the fight to be REAL —
        # both the enemy's HP bar and a hero sprite with a non-zero box.
        await wait_until("(() => { const t=(document.getElementById('mbHpLabel')||{}).textContent||'';"
                         " return t && !t.startsWith('0/'); })()", "the enemy to spawn")
        await wait_until("(() => { const f=document.getElementById('mbPlayerFigure');"
                         " return !!f && f.getBoundingClientRect().width > 0; })()",
                         "the hero sprite to render")
        if seconds > 0:
            await asyncio.sleep(seconds)
        state = await evaluate(STATE)
        print("state:", json.dumps(state, ensure_ascii=False))
        # The same guard for the fight itself: a reference whose enemy is 0/0 is not a
        # reference for anything.
        if not state or str(state.get("enemyHp", "")).startswith("0/"):
            raise SystemExit("the fight never started - refusing to shoot an empty arena")
        s = await send(ws, nxt(), "Page.captureScreenshot", {"captureBeyondViewport": False})
        with open(out, "wb") as fh:
            fh.write(base64.b64decode(s["data"]))
        print("shot:", out)


if __name__ == "__main__":
    a = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    st = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    sec = float(sys.argv[3]) if len(sys.argv) > 3 else 1.2
    o = sys.argv[4] if len(sys.argv) > 4 else "/tmp/pwa_arena.png"
    asyncio.run(main(a, st, sec, o))
