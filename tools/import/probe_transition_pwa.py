#!/usr/bin/env python3
"""The PWA's TRANSITION screen, measured live and MID-animation.

Jan: "všechny transition obrazovky chybí — při přechodu do města, do divočiny, při
použití portal scrollu. Mezi jednotlivými obrazovkami je vždy vložená transition
obrazovka s obrázkem a lehkou animací."

So there are FOUR transition types and the port has none of them:

  'town'       -> assets/town.webp            a walk/portal back to town
  'wilderness' -> assets/map.webp             entering the map from the town
  'portal'     -> assets/items/town_portal_scroll.png
  'stop'       -> assets/stops/stop_act{act}_{zone}.webp
                  (act 0 and 1 have real art, 2-4 fall back to placeholder_actN.png)

What this prints, because none of it can be read off a still:

  * the overlay's own rect, background and z-index;
  * the image's 260x260 box, its border-radius and ITS RADIAL MASK;
  * the three CSS animations that make the "light animation": `transitionReveal`
    (a black ::after that fades 1.4s), the 1800ms hold, then `transitionScreenFadeOut`
    over 0.4s;
  * the LABEL — which is in the markup but which `showTransition` never writes, so it
    is empty and the screen is image-only (worth knowing before porting a label);
  * a screenshot taken MID-animation at ~0.15 s and at ~1.5 s, so the reveal is visible
    as a picture and not only as keyframes.

Usage:
    python3 -m http.server 8099   (in the PWA's dist/)
    chromium --headless=new --remote-debugging-port=9222
    python3 tools/import/probe_transition_pwa.py [town|wilderness|portal|stop]
"""

import asyncio
import base64
import json
import sys
import urllib.request

import websockets

URL = "http://127.0.0.1:8099/index.html"
CDP_PORT = 9222
OUT_DIR = "/tmp/transition_pwa"


def _ws():
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/list") as fh:
        for t in json.load(fh):
            if t.get("type") == "page":
                return t["webSocketDebuggerUrl"]
    raise SystemExit("no page target on 9222")


THE_PROBE = r"""
// The PWA's own `window.game` does not expose showTransition (it exposes 66 functions and
// that is not one of them), so the screen is driven the way the game drives it: the element
// is shown and the classes that carry the two animations are applied by hand.
window.__probe = (type) => {
  const R = el => { const r = el.getBoundingClientRect();
    return [+r.x.toFixed(1), +r.y.toFixed(1), +r.width.toFixed(1), +r.height.toFixed(1)]; };
  const cs = el => getComputedStyle(el);
  // ⚠️  `getComputedStyle(el, '::after')` is the ONLY way to read a pseudo-element, and the
  // helper above silently ignores a second argument — measuring the element instead and
  // reporting `content:"normal", animation:"none"` for a pseudo that has both. A separate
  // helper, so the mistake cannot be repeated.
  const pseudo = (el, p) => getComputedStyle(el, p);
  const screen = document.getElementById('transitionScreen');
  const img = document.getElementById('transitionImage');
  const content = screen.querySelector('.transition-content');
  const label = screen.querySelector('.transition-label');
  const out = {
    markup: screen.outerHTML.replace(/\s+/g, ' ').slice(0, 500),
    labelPresent: !!label,
    labelText: label ? label.textContent : null,
    viewport: [window.innerWidth, window.innerHeight],
  };
  if (type === 'portal') img.src = 'assets/items/town_portal_scroll.png';
  else if (type === 'town') img.src = 'assets/town.webp';
  else if (type === 'wilderness') img.src = 'assets/map.webp';
  else img.src = 'assets/stops/stop_act0_3.webp';
  screen.classList.remove('hidden');
  screen.classList.remove('fade-out');
  out.screen = {rect: R(screen), bg: cs(screen).backgroundColor, z: cs(screen).zIndex,
                display: cs(screen).display, position: cs(screen).position,
                alignItems: cs(screen).alignItems, justifyContent: cs(screen).justifyContent};
  out.content = {rect: R(content), gap: cs(content).gap, direction: cs(content).flexDirection,
                 after: (() => { const a = pseudo(content, '::after');
                   return {content: a.content, bg: a.backgroundColor, inset: a.inset,
                           radius: a.borderRadius, z: a.zIndex, animation: a.animation,
                           animationName: a.animationName, duration: a.animationDuration,
                           timing: a.animationTimingFunction, fill: a.animationFillMode,
                           opacity: a.opacity}; })()};
  out.image = {rect: R(img), src: img.getAttribute('src'), natural: [img.naturalWidth, img.naturalHeight],
               w: cs(img).width, h: cs(img).height, objectFit: cs(img).objectFit,
               radius: cs(img).borderRadius, z: cs(img).zIndex,
               mask: cs(img).maskImage, webkitMask: cs(img).webkitMaskImage,
               glowLow: cs(img).getPropertyValue('--glow-low'), glowHigh: cs(img).getPropertyValue('--glow-high')};
  return out;
};
// The fade-out phase: what the overlay looks like once `fade-out` is on.
window.__fadeOut = () => {
  const screen = document.getElementById('transitionScreen');
  const a = getComputedStyle(screen);
  return {classes: screen.className, animationName: a.animationName, duration: a.animationDuration,
          timing: a.animationTimingFunction, opacity: a.opacity};
};
"""


async def shot(ws, path):
    msg = await send(ws, "Page.captureScreenshot", {"format": "png"})
    with open(path, "wb") as fh:
        fh.write(base64.b64decode(msg["result"]["data"]))
    return path


async def send(ws, method, params=None):
    await ws.send(json.dumps({"id": _next_id(), "method": method, "params": params or {}}))
    while True:
        raw = await asyncio.wait_for(ws.recv(), timeout=30)
        m = json.loads(raw)
        if m.get("id") == _id:
            return m


_id = 0


def _next_id():
    global _id
    _id += 1
    return _id


async def main():
    want = sys.argv[1] if len(sys.argv) > 1 else "town"
    import os
    os.makedirs(OUT_DIR, exist_ok=True)
    ws_url = _ws()
    async with websockets.connect(ws_url, max_size=40 * 1024 * 1024) as ws:
        await send(ws, "Page.enable")
        await send(ws, "Network.enable")
        await send(ws, "Network.setCacheDisabled", {"cacheDisabled": True})
        await send(ws, "Emulation.setDeviceMetricsOverride",
                   {"width": 390, "height": 844, "deviceScaleFactor": 1, "mobile": True})
        await send(ws, "Page.navigate", {"url": URL})
        await asyncio.sleep(4)
        await send(ws, "Runtime.evaluate", {"expression": THE_PROBE})
        res = await send(ws, "Runtime.evaluate",
                         {"expression": f"JSON.stringify(window.__probe('{want}'))",
                          "returnByValue": True})
        data = json.loads(res["result"]["result"]["value"])
        # MID-ANIMATION: the reveal is a 1.4 s fade of a black ::after, so a single frame
        # cannot see it. Shoot at 0.15 s and at 1.5 s and report the opacity of the ::after.
        await asyncio.sleep(0.15)
        early = await send(ws, "Runtime.evaluate", {
            "expression": "getComputedStyle(document.querySelector('.transition-content'),'::after').opacity",
            "returnByValue": True})
        await shot(ws, f"{OUT_DIR}/{want}_early.png")
        await asyncio.sleep(1.35)
        late = await send(ws, "Runtime.evaluate", {
            "expression": "getComputedStyle(document.querySelector('.transition-content'),'::after').opacity",
            "returnByValue": True})
        await shot(ws, f"{OUT_DIR}/{want}_late.png")
        # The hold is 1800 ms from the SHOW, then `fade-out` starts.
        fade = await send(ws, "Runtime.evaluate", {
            "expression": "(() => { const s=document.getElementById('transitionScreen');"
                          "s.classList.add('fade-out'); return JSON.stringify(window.__fadeOut()); })()",
            "returnByValue": True})
        data["revealOpacityEarly"] = early["result"]["result"]["value"]
        data["revealOpacityLate"] = late["result"]["result"]["value"]
        data["fadeOut"] = json.loads(fade["result"]["result"]["value"])
        print(json.dumps(data, indent=2, ensure_ascii=False))
        print(f"\nshots: {OUT_DIR}/{want}_early.png  {OUT_DIR}/{want}_late.png")


if __name__ == "__main__":
    asyncio.run(main())
