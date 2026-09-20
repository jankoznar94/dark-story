#!/usr/bin/env python3
"""Click the HUD panel buttons in the REAL web build and prove the window closes.

Jan's report: *"opening any window from the top menu (hero, items, ...) freezes the
game"*. Every headless check passed while the build he was looking at had NO WAY
OUT: the panels are added to the HUD after the buttons, so the full-screen panel
swallowed the tap that was meant to close it. Neither `_draw` nor the GUI hit test
exists in a `--headless` run (`Viewport.push_input()` routes no GUI events there at
all), so the honest acceptance is a real browser.

MEASUREMENT TRAP, measured: do NOT read the Godot canvas back through the page.
`drawImage(canvas, ...)` on a WebGL canvas without `preserveDrawingBuffer` returns
an empty buffer, so a dark-fraction probe reads ~0.83 of a green field and its
readings are noise. The CDP screenshot is the composited frame and is the only
trustworthy pixel source here.

Usage:
    chromium --headless=new --remote-debugging-port=9223 --no-sandbox \
        --use-gl=swiftshader --enable-unsafe-swiftshader --user-data-dir=/tmp/ds-chrome
    python3 -m http.server 8099 --directory build/web
    python3 tools/web_panel_click.py http://127.0.0.1:8099/index.html [port]

Prints PANEL_CLICK_ALL_PASS=true/false; exit code 0 only when every panel opened
AND closed.
"""
import asyncio
import base64
import io
import json
import sys
import urllib.request

import websockets

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8099/index.html"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 9223

PROBE_JS = """
window.__raf = 0;
(function () {
  var orig = window.requestAnimationFrame;
  window.requestAnimationFrame = function (cb) {
    return orig(function (t) { window.__raf++; return cb(t); });
  };
})();
window.__canvas = function () {
  const cv = document.querySelector('canvas');
  const r = cv.getBoundingClientRect();
  return {l: r.left, t: r.top, w: r.width, h: r.height, cw: cv.width, ch: cv.height};
};
"""


def button_rects(w, h):
    """hud.gd::_layout(). Duplicated on purpose: the probe must not import the game."""
    m = min(w, h)
    margin = m * 0.055
    bw = max(56.0, m * 0.16)
    bh = max(28.0, m * 0.070)
    gap = m * 0.02
    bx = (w - (bw * 2.0 + gap)) * 0.5
    by = margin * 0.4
    # The LOWER part of the button, not its centre: the panels are vertically
    # centred, and on a phone-sized viewport the window's top edge cuts through the
    # bottom of the button row - which is exactly where a thumb lands. A centre
    # click reads "the button works" even on a build where the panel swallows the
    # tap, so it cannot see the defect this file exists to catch.
    low = by + bh * 0.80
    return {
        "inventory": (bx + bw * 0.5, low),
        "stats": (bx + bw + gap + bw * 0.5, low),
        "loot": (bx + (bw + gap) * 2.0 + bw * 0.5, low),
    }


def page_ws():
    with urllib.request.urlopen("http://127.0.0.1:%d/json" % PORT) as r:
        for t in json.load(r):
            if t["type"] == "page":
                return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target on port %d" % PORT)


class CDP:
    def __init__(self, ws):
        self.ws = ws
        self.n = 0
        self.logs = []
        self.errors = []

    async def send(self, method, **params):
        self.n += 1
        mid = self.n
        await self.ws.send(json.dumps({"id": mid, "method": method, "params": params}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == mid:
                return msg
            await self._event(msg)

    async def _event(self, msg):
        mth = msg.get("method", "")
        if mth == "Runtime.consoleAPICalled":
            self.logs.append(" ".join(str(a.get("value", a.get("description", "")))
                                      for a in msg["params"].get("args", [])))
        elif mth == "Runtime.exceptionThrown":
            d = msg["params"]["exceptionDetails"]
            self.errors.append("%s %s" % (d.get("text"),
                                          d.get("exception", {}).get("description", "")))
        elif mth == "Log.entryAdded":
            self.logs.append(msg["params"]["entry"].get("text", ""))

    async def pump(self, seconds):
        end = asyncio.get_event_loop().time() + seconds
        while asyncio.get_event_loop().time() < end:
            try:
                msg = json.loads(await asyncio.wait_for(self.ws.recv(), 0.2))
            except asyncio.TimeoutError:
                continue
            await self._event(msg)

    async def evaluate(self, expr):
        r = await self.send("Runtime.evaluate", expression=expr, returnByValue=True)
        return r["result"].get("result", {}).get("value")

    async def tap(self, x, y):
        for t in ("mousePressed", "mouseReleased"):
            await self.send("Input.dispatchMouseEvent", type=t, x=x, y=y, button="left",
                            clickCount=1, buttons=1 if t == "mousePressed" else 0)
            await asyncio.sleep(0.08)

    async def frame(self, path=None):
        """The COMPOSITED frame as a numpy array (the only honest pixel source)."""
        import numpy as np
        from PIL import Image
        r = await self.send("Page.captureScreenshot", format="png")
        raw = base64.b64decode(r["result"]["data"])
        if path:
            with open(path, "wb") as f:
                f.write(raw)
        return np.asarray(Image.open(io.BytesIO(raw)).convert("RGB")).astype("int16")


def dark_frac(img):
    """Fraction of DARK pixels in the middle fifth of the frame. The panel fill is
    (0.075, 0.065, 0.058) - near black - against a green field, so a window coming
    up is a step up in this number."""
    import numpy as np
    h, w, _ = img.shape
    box = img[int(h * 0.40):int(h * 0.60), int(w * 0.40):int(w * 0.60), :]
    return float((box.sum(axis=2) < 150).mean())


async def boot(c):
    await c.send("Page.navigate", url=URL)
    c.logs = []
    for _ in range(40):
        await c.pump(1.0)
        if any("starter weapon" in l for l in c.logs):
            await c.pump(1.5)
            return True
    return False


async def main():
    fails = []
    async with websockets.connect(page_ws(), max_size=64 << 20) as ws:
        c = CDP(ws)
        await c.send("Runtime.enable")
        await c.send("Log.enable")
        await c.send("Page.enable")
        # THE SERVICE WORKER WILL SERVE AN OLD BUILD. Godot's web export registers
        # one, so a freshly exported index.pck is ignored and the browser silently
        # runs the previous build - every measurement after an export then describes
        # code that is not in the repository. Disable the cache AND the worker.
        try:
            await c.send("Network.enable")
            await c.send("Network.setCacheDisabled", cacheDisabled=True)
            await c.send("Page.setBypassServiceWorker", bypass=True)
        except Exception as exc:  # older protocol: the reload path still works
            print("cache bypass unavailable:", exc)
        await c.send("Page.addScriptToEvaluateOnNewDocument", source=PROBE_JS)

        for which in ("inventory", "stats"):
            if not await boot(c):
                print("FAIL did not boot:", c.logs[-5:])
                fails.append("boot")
                continue
            ci = await c.evaluate("window.__canvas()")
            x, y = button_rects(ci["cw"], ci["ch"])[which]

            r0 = await c.evaluate("window.__raf")
            await c.pump(1.0)
            r1 = await c.evaluate("window.__raf")
            t_boot = await c.frame("/tmp/panel_%s_0_boot.png" % which)

            await c.tap(x, y)
            await c.pump(1.2)
            t_open = await c.frame("/tmp/panel_%s_1_open.png" % which)

            await c.tap(x, y)          # the same button is the documented way out
            await c.pump(1.2)
            t_close = await c.frame("/tmp/panel_%s_2_closed.png" % which)
            r2 = await c.evaluate("window.__raf")

            b, o, cl = dark_frac(t_boot), dark_frac(t_open), dark_frac(t_close)
            print("%-10s centre-dark  boot %.3f -> open %.3f -> closed %.3f | fps %.0f -> %.0f"
                  % (which, b, o, cl, r1 - r0, r2 - r1))
            # The boot readings repeat to ~0.001, so 0.05 is far above the noise;
            # 0.10 was too strict for the NARROWER stat sheet, whose step is 0.086.
            if o - b < 0.05:
                fails.append("%s: the window did not open" % which)
            if abs(cl - b) > 0.05:
                fails.append("%s: the window did not close (%.3f vs boot %.3f)" % (which, cl, b))
            if r2 - r1 < 1.0:
                fails.append("%s: the frame loop stopped" % which)

        print("JS exceptions:", c.errors if c.errors else "none")
        print("PANEL_CLICK_ALL_PASS=%s" % ("true" if not fails else "false"))
        for f in fails:
            print("  FAIL", f)
    sys.exit(1 if fails else 0)


asyncio.run(main())
