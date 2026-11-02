#!/usr/bin/env python3
"""Read the LIVE PWA's reaction row (Dodge / Block / Counter) and shoot it.

The port's Dodge button renders as a half-drawn circle. The PWA is the reference, so this
forces an opportunity window on a real fight (`mapBattleState._oppType`) and reads:

  * the bounding box of `#mbPsDefBtns` and each `.ps-def-btn`
  * the button's own computed width/height/border/padding and the `getBoundingClientRect`
    of the inner `<img class="ps-def-img">` and the `<span>` label
  * every CSS rule the browser actually applies to `.ps-def-btn` (via the applied styles)
  * `#mbActionInfo`'s box and the size of the `<img>` inside the middle icon

and writes a PNG of the row, cropped, so the shape can be looked at.

  python3 tools/import/probe_reaction_pwa.py dodge /tmp/pwa_opp.png

Requires: `python3 -m http.server 8099` inside the PWA's dist/, chromium on 9222.
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222

BOX = r"""
(sel) => { const e = document.querySelector(sel); if (!e) return null;
  const b = e.getBoundingClientRect(); const c = getComputedStyle(e);
  return { x:+b.x.toFixed(1), y:+b.y.toFixed(1), w:+b.width.toFixed(1), h:+b.height.toFixed(1),
    border:c.border, radius:c.borderRadius, bg:c.backgroundColor, overflow:c.overflow,
    display:c.display, padding:c.padding, position:c.position, objectFit:c.objectFit }; }
"""

PROBE = """
(() => {
  const box = %s;
  // ⚠️  `mapBattleState` is NOT a window global in the current PWA build (measured:
  // `Object.keys(window)` has `game` and nothing else battle-shaped, while the old
  // `probe_arena_geometry.py` still reads `window.mapBattleState`). So the window cannot be
  // ARMED from here — the row is simply UNHIDDEN and given the same innerHTML
  // `showOpportunityPrompt` writes. What this probe measures is the LAYOUT and the CSS of
  // the row, which is what the port's broken Dodge button is about; the rules stay untested.
  const info = document.querySelector('#mbActionInfo');
  if (info) {
    info.classList.remove('hidden');
    info.innerHTML = '<img src="assets/ps/ps_dodge.png" style="width:64px;height:64px;' +
      'object-fit:cover;border-radius:50%%;border:2px solid #e67e22">';
  }
  const def = document.querySelector('#mbPsDefBtns');
  if (def) def.classList.remove('hidden');
  const wrap = box('#mbPsDefBtns');
  const out = { wrap };
  ['Dodge', 'Block', 'Counter'].forEach(n => {
    const sel = '.ps-def-' + n.toLowerCase();
    const btn = document.querySelector(sel);
    if (!btn) { out[n] = null; return; }
    const img = btn.querySelector('img');
    const span = btn.querySelector('span');
    out[n] = { btn: box(sel), hidden: btn.classList.contains('hidden'),
      img: img ? box(sel + ' img') : null,
      span: span ? box(sel + ' span') : null };
  });
  out.actionInfo = info ? { box: box('#mbActionInfo'), img: box('#mbActionInfo img'),
    hidden: info.classList.contains('hidden') } : null;
  out.arrow = box('#mbArrow');
  return out;
})()
""" % BOX


async def send(ws, mid, method, params=None):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(await ws.recv())
        if msg.get("id") == mid:
            if "error" in msg:
                raise RuntimeError(f"{method}: {msg['error']}")
            return msg.get("result", {})


async def main(kind, out_png):
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
        await send(ws, nxt(), "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, nxt(), "Page.navigate", {"url": URL})
        await asyncio.sleep(4)

        async def evaluate(expr):
            r = await send(ws, nxt(), "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            if "exceptionDetails" in r:
                return {"__error__": str(r["exceptionDetails"])[:400]}
            return r.get("result", {}).get("value")

        print("select class:", await evaluate(
            "(() => { if (window.game && game.selectClass) { game.selectClass('barbarian');"
            " return 'barbarian'; } return 'no game.selectClass'; })()"))
        await asyncio.sleep(1.5)
        kit = await evaluate("(() => { const s=JSON.parse(localStorage.getItem('dungeonRecallV7')||'{}');"
                             " return { cls: s.heroClass || '', maxHp: (s.hero||{}).maxHp }; })()")
        print("kit ->", kit)
        if not kit or kit.get("cls") != "barbarian":
            raise SystemExit("the class kit did not apply - the fight would be a level-1 hero")
        print("enter stop:", await evaluate("(() => { game.enterStop(0, 0); return 'ok'; })()"))

        async def wait_until(expr, what, tries=24):
            for _ in range(tries):
                value = await evaluate(expr)
                if value:
                    return value
                await asyncio.sleep(0.5)
            raise SystemExit(f"timed out waiting for {what}")

        # `enterStop` runs a screen transition, so the fight does not exist for ~2 s and a
        # frame shot on a fixed sleep lands before it. The port skill's own rule: wait for
        # the fight to be REAL, never for a duration.
        await wait_until("(() => { const t=(document.getElementById('mbHpLabel')||{}).textContent||'';"
                         " return t && !t.startsWith('0/'); })()", "the enemy to spawn")
        state = await evaluate(PROBE)
        print(json.dumps(state, indent=1, ensure_ascii=False))
        shot = await send(ws, nxt(), "Page.captureScreenshot", {"format": "png"})
        with open(out_png, "wb") as fh:
            fh.write(base64.b64decode(shot["data"]))
        print("wrote", out_png)


if __name__ == "__main__":
    k = sys.argv[1] if len(sys.argv) > 1 else "dodge"
    o = sys.argv[2] if len(sys.argv) > 2 else "/tmp/pwa_opp.png"
    asyncio.run(main(k, o))
