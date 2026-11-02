extends RefCounted
class_name UpdateCheck
## Manual update of the PWA's service worker — the same button Zily 2 and Thrower carry.
##
## Jan (Nov 2026): "Přidáme do ní stejné tlačítko jako je ve hrách Zily2 a Thrower.
## Tlačítko pro ruční update service workera pro stažení všech změn. Abych nemusel
## stále hru otevírat v anonymním okně."
##
## Why the button cannot be a plain `registration.update()`: the generated worker
## serves `index.pck` cache-first, so `update()` alone only refreshes the worker
## script. The page then reloads into the SAME cached pack and the game looks
## unchanged. What actually works is: refresh the registration, let the freshly
## installed worker take over (`skipWaiting` — see `tools/fix_pwa_export.py`), drop
## the caches and reload with a cache-busting query in the address.
##
## Three porting rules, learned the hard way in Zily 2 and Thrower (see
## `godot-web-pwa-delivery`):
##
##   1. Talk to JS through GLOBAL VARIABLES the game polls (`poll`), NOT through
##      `JavaScriptBridge.create_callback`. The callback registers fine and is
##      visible in the browser, but the call from JS into GDScript never arrives.
##   2. NEVER `unregister()` the worker. During a first install that leaves the
##      browser waiting for a worker that never finishes.
##   3. The reload is the fix, so it must never hang behind an async call — always
##      arm a `setTimeout` watchdog.
##
## Outside a web export (`OS.has_feature("web")` false) there is nothing to update
## and the town does not even draw the section.

## Global variables in the page that carry the state back into the game.
const JS_BUILD := "__dr_build"
const JS_UPDATE := "__dr_update"

## True only in a web export. Everything else is a no-op there.
var web: bool = false
## Preview/test hook: a desktop run cannot be a web export, so a headless test or an
## offscreen preview sets this to TRUE before the town is built to see the section the
## phone really draws. A real web build never touches it.
static var force_web: bool = false
## Build stamp read from `version.txt` — the only honest statement about what the
## device really runs. `?` until the first fetch lands, `dev` off the web.
var build_id: String = "dev"
## The last update result, drawn under the button.
var note: String = ""
## Throttle for the poll — reading a JS global every frame is pointless.
var _ticks: int = 0


func _init() -> void:
	web = OS.has_feature("web") or force_web
	if not web:
		build_id = "dev"


## The JavaScriptBridge singleton. NEVER referenced as a global identifier: a
## desktop export must not notice the web class at all.
##
## ⚠️  `Engine.has_singleton("JavaScriptBridge")` is TRUE even in a plain desktop/headless
## run — the singleton is there, `eval` is a silent no-op that returns null and leaves
## every global unset. Measured here: a tap on the update button then set NO note at all,
## which reads exactly like a dead button. `web` is the only trustworthy gate, so the
## singleton alone is never enough.
func _js_bridge() -> Object:
	if not web:
		return null
	if not Engine.has_singleton("JavaScriptBridge"):
		return null
	return Engine.get_singleton("JavaScriptBridge")


func _window() -> Object:
	var jb: Object = _js_bridge()
	if jb == null:
		return null
	return jb.call("get_interface", "window")


## Reads the build stamp next to `index.html`. The result is PICKED UP later by
## `poll()` — not delivered by a callback (rule 1 above).
func load_build_id() -> void:
	if not web:
		return
	var jb: Object = _js_bridge()
	if jb == null:
		return
	var js := """
	(() => {
	  fetch('version.txt', {cache: 'no-store'})
	    .then(r => r.ok ? r.text() : '?')
	    .then(t => { window.%s = ((t || '').trim().slice(0, 12) || '?'); })
	    .catch(() => { window.%s = '?'; });
	  return true;
	})()
	""" % [JS_BUILD, JS_BUILD]
	jb.call("eval", js, true)


## Takes the state over from the page. Call it a few times per second, not every
## frame. Returns true when something changed (the town then redraws its labels).
func poll() -> bool:
	if not web:
		return false
	_ticks += 1
	if _ticks % 15 != 0:
		return false
	var w: Object = _window()
	if w == null:
		return false
	var changed := false
	var b: Variant = w.get(JS_BUILD)
	if b != null and typeof(b) == TYPE_STRING and String(b) != "" and String(b) != build_id:
		build_id = String(b)
		changed = true
	var u: Variant = w.get(JS_UPDATE)
	if u != null and typeof(u) == TYPE_STRING and String(u) != "":
		apply_note(String(u))
		# The note is taken over ONCE — otherwise it keeps coming back.
		w.set(JS_UPDATE, "")
		changed = true
	return changed


## Asks the browser for a fresh build: refresh the registrations (the new worker
## is installed by now thanks to `skipWaiting`), drop every cache, reload with a
## cache-busting query. The reload ALWAYS happens — a watchdog arms it up front.
func request_update() -> void:
	note = ""
	if not web:
		note = "Aktualizace je jen pro webovou verzi."
		return
	var jb: Object = _js_bridge()
	if jb == null:
		note = "Prohlížeč neumí aktualizaci na pozadí."
		return
	# Hláska se nastavuje TADY, ne až z JavaScriptu: stránka se za chvíli restartuje a
	# hráč má vidět, že se něco děje, i kdyby eval nic neudělal (na desktopu je to
	# tichý no-op — viz `_js_bridge`).
	note = "Aktualizuji, hra se restartuje…"
	var js := """
	(async () => {
	  const note = (c) => { window.%s = c; };
	  const bust = location.href.split('#')[0].split('?')[0] + '?v=' + Date.now();
	  let gone = false;
	  const go = () => { if (!gone) { gone = true; location.replace(bust); } };
	  // POJISTKA: at se deje cokoli, do 2,5 s se stranka restartuje. Restart je
	  // to, co hru opraví, tak ho nikdy nedrzime za asynchronni operaci.
	  setTimeout(go, 2500);
	  note('hard');
	  let regs = [];
	  try {
	    regs = await navigator.serviceWorker.getRegistrations();
	  } catch (e) { regs = []; }
	  try {
	    for (const r of regs) {
	      // ODREGISTROVAT SE NESMI: pri prvni instalaci to necha prohlizec
	      // cekat na worker, ktery uz nikdy nedobehne. Staci rict workeru, at
	      // si stahne novou verzi - novy se sam ujme rizeni (skipWaiting).
	      r.update().catch(() => {});
	    }
	  } catch (e) {}
	  // Kazdou cache smazat, ale s limitem: kdyz se browser zasekne, jdeme dal.
	  try {
	    const cc = await Promise.race([
	      caches.keys(),
	      new Promise((res) => setTimeout(() => res([]), 1200))
	    ]);
	    for (const k of cc) { caches.delete(k).catch(() => {}); }
	  } catch (e) {}
	  setTimeout(go, 900);
	  return 'hard';
	})()
	""" % JS_UPDATE
	# `false` = necekat na dokonceni: slib bezi dal a stranka se restartuje.
	jb.call("eval", js, false)


func apply_note(code: String) -> void:
	match code:
		"hard":
			note = "Cache smazána, restartuji…"
		"none":
			note = "Není co aktualizovat."
		"n/a":
			note = "Prohlížeč neumí aktualizaci na pozadí."
		_:
			note = "Aktualizace se nepodařila: " + code
