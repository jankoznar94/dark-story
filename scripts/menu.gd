class_name Menu
extends RefCounted

# KTERA OBRAZOVKA JE OTEVRENA + AKTUALIZACE PWA. Hra sama nic nekresli ani
# necte vstup - tady je jen stav, podle ktereho se kresli a klepe.
#
# TLACITKO UPDATE (Jan, Oct 2026: "ve hře musí být taky tlačítko Update. Jako
# v Zily2. Abych mohl ručně aktualizovat service workera"): posle prohlizeci
# dotaz, ktery odregistruje service workera, smaze cache a nacte hru znovu
# s razitkem v adrese. Bez toho zustane nainstalovane PWA stara verze, dokud
# se nezavrou vsechny panely - a to u PWA nejde.
#
# Mimo web (desktop) tlacitko jen rekne, ze neni co aktualizovat.

enum View { MENU, BATTLE, UPGRADES }

# Polozky menu. Akce se vyhodnocuji PRES JMENO, ne podle poradi.
const ITEMS := ["HRÁT", "VYLEPŠENÍ", "UPDATE"]
const SUBS := ["hraj od nejvyššího levelu", "permanentní upgrady za body", "stáhnout novou verzi"]
const ACTIONS := ["battle", "upgrades", "update"]

# GLOBALNI PROMENNE, KTERYMI PROHLIZEC MLUVI S HROU. Hra si je sama VYCTE
# (`pull_js_state`) - callback z JS do GDScriptu v prohlizeci nedojde.
const JS_BUILD := "__thrower_build"
const JS_UPDATE := "__thrower_update"

var view: int = View.MENU
var web: bool = false
var build_id: String = "dev"
var update_note: String = ""


func open_menu() -> void:
	view = View.MENU


func open_battle() -> void:
	view = View.BATTLE


func open_upgrades() -> void:
	view = View.UPGRADES


func is_menu() -> bool:
	return view == View.MENU


func is_battle() -> bool:
	return view == View.BATTLE


func is_upgrades() -> bool:
	return view == View.UPGRADES


# JavaScriptovy singleton. NIKDY jako globalni identifikator: desktop export si
# webove tridy nesmi vubec vsimnout.
func _jb() -> Object:
	return Engine.get_singleton("JavaScriptBridge")


func _window() -> Object:
	var jb: Object = _jb()
	if jb == null:
		return null
	return jb.call("get_interface", "window")


# Nacte otisk buildu (version.txt vedle index.html). Vysledek si hra VYCTE
# pozdeji (`pull_js_state`) - ne callbackem.
func load_build_id() -> void:
	build_id = "dev"
	if not web:
		return
	var jb: Object = _jb()
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


# STAV Z PROHLIZECE. Hra si ho prevzme nekolikrat za sekundu. Vraci true, kdyz
# se neco zmenilo (obrazovka se pak prekresli).
func pull_js_state() -> bool:
	if not web:
		return false
	var w: Object = _window()
	if w == null:
		return false
	var changed: bool = false
	var b: Variant = w.get(JS_BUILD)
	if b != null and typeof(b) == TYPE_STRING and String(b) != "" and String(b) != build_id:
		build_id = String(b)
		changed = true
	var u: Variant = w.get(JS_UPDATE)
	if u != null and typeof(u) == TYPE_STRING and String(u) != "":
		apply_update_note(String(u))
		# Hlaska se prevezme JEDNOU, jinak by se porad vracela.
		w.set(JS_UPDATE, "")
		changed = true
	return changed


# RUCNI AKTUALIZACE. Nejdriv normalni cesta (nova verze uz ceka ve service
# workeru), pak odregistrovani + znovuzalozeni registrace a smazani cache.
func request_update() -> void:
	update_note = ""
	if not web:
		update_note = "Aktualizace je jen pro webovou verzi."
		return
	var jb: Object = _jb()
	if jb == null:
		update_note = "Prohlížeč neumí aktualizaci na pozadí."
		return
	var js := """
	(async () => {
	  const note = (c) => { window.%s = c; };
	  const bust = location.href.split('#')[0].split('?')[0] + '?v=' + Date.now();
	  let gone = false;
	  const go = () => { if (!gone) { gone = true; location.replace(bust); } };
	  // POJISTKA: at se deje cokoli, do 2,5 s se stranka restartuje. Driv se
	  // tu cekalo na `serviceWorker.ready` a na `r.update()` - pri PRVNIM
	  // nacteni (worker se jeste instaloval) to viselo a hra zustala seknuta,
	  // dokud ji clovek nezavrel. Restart je to, co hru opraví, tak ho nikdy
	  // nedrzime za asynchronni operaci.
	  setTimeout(go, 2500);
	  note('hard');
	  try {
	    const regs = await navigator.serviceWorker.getRegistrations();
	    for (const r of regs) {
	      // ODREGISTROVAT SE NESMI: pri prvni instalaci to necha prohlizec
	      // cekat na worker, ktery uz nikdy nedobehne. Staci rict workeru,
	      // at si stahne novou verzi - novy se sam ujme rizeni (skipWaiting).
	      r.update().catch(() => {});
	    }
	  } catch (e) {}
	  try {
	    // Mazani cache s limitem: kdyz se browser zasekne, jdeme dal.
	    const cc = await Promise.race([
	      caches.keys(),
	      new Promise((res) => setTimeout(() => res([]), 1200))
	    ]);
	    for (const k of cc) { caches.delete(k).catch(() => {}); }
	  } catch (e) {}
	  setTimeout(go, 350);
	  return 'hard';
	})()
	""" % JS_UPDATE
	jb.call("eval", js, false)


func apply_update_note(code: String) -> void:
	match code:
		"hard":
			update_note = "Cache smazána — restartuji…"
		"none":
			update_note = "Není co aktualizovat."
		"n/a":
			update_note = "Prohlížeč neumí aktualizaci na pozadí."
		_:
			update_note = "Aktualizace se nepodařila: " + code
