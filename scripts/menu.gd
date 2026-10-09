class_name Menu
extends RefCounted

# STAV MENU. Prvni obrazovka hry, nez zacne kolo. Nema zadnou logiku hry -
# jen vi, ktera obrazovka je otevrena, aby se podle toho kreslilo a
# vyhodnocoval vstup. Vsechno ostatni zustava v Game.
#
# "Update" nerestartuje hru natvrdo. Posle prohlizeci dotaz, aby service
# worker zkontroloval novou verzi a stahl ji - to je presne to, co Jan
# jinak musel delat v anonymnim okne. Mimo web (desktop export) tlacitko
# jen oznami, ze neni co aktualizovat.
#
# Hra se timhle da take PRIDAT NA PLOCHU (PWA): prohlibec nabidne
# instalaci jen tehdy, kdyz je hra normalne otevrena (ne v anonymnim
# okne) a ma manifest + service worker. Oboji web export Godotu prida.

enum View { MENU, EDITOR, GUIDE, SETTINGS, BATTLE }

const TITLE := "ZILY"
const SUBTITLE := "elementární poutníci na žilách many"

# Poradi tlacitek v menu. Je tady, ne v kresleni - kdyby se kresleni a
# vstup rozešly, klepnuti by delalo neco jineho, nez co je videt.
const MENU_ITEMS := ["BATTLE", "EDITOR", "NÁVOD", "SETTINGS", "UPDATE"]
const MENU_SUBS := ["spustit kolo", "vyrobit si level", "pravidla hry a poškození",
	"hudba a zvuky", "stáhnout novou verzi"]

# Prepisuje se v _ready() podle toho, jestli hra bezi ve webovem exportu.
var web: bool = false
# Otisk buildu, ktery se zobrazuje v menu. Bez nej se neda poznat, jestli
# hrac po aktualizaci vidi novou verzi, nebo mu ji jeste drzi cache.
var build_id: String = "?"
# Vysledek posledni aktualizace - kresli se jako hlaska pod tlacitky.
var update_note: String = ""
var view: int = View.MENU


# Nacte otisk buildu (version.txt vedle index.html). Zapisuje se do
# projektoveho nastaveni - to je jedine misto, na ktere se z GDScriptu
# dostanu i z JavaScriptoveho callbacku (promenna v Menu by v nem byla
# jina instance).
func load_build_id() -> void:
	build_id = "dev"
	if not web:
		return
	var jb: Object = Engine.get_singleton("JavaScriptBridge")
	if jb == null:
		return
	var js := """
	(async () => {
	  try {
	    const r = await fetch('version.txt', {cache: 'no-store'});
	    const t = r.ok ? (await r.text()).trim() : '?';
	    if (window.godotBridge && window.godotBridge.setVersion) {
	      window.godotBridge.setVersion(t.slice(0, 12) || '?');
	    }
	    return t;
	  } catch (e) { return '?'; }
	})()
	"""
	jb.call("eval", js, false)


func open_battle() -> void:
	view = View.BATTLE


# EDITOR LEVELU. Sem se chodi vyrabet levely rucne - klepnutim na usek se
# vybere, tlacitky dole se meni. Hra se pri tom nehraje: editor ma svuj
# stav a do hry posila hotovy level.
func open_editor() -> void:
	view = View.EDITOR


func is_editor() -> bool:
	return view == View.EDITOR


# NAVOD. Sem se prestehovalo vsechno, co drive stalo popisky primo v herni
# desce - a hlavne CELY puvodni navod z ovladaciho pruhu. Deska je tak bez
# textu a pruh se zmensil na jedno tlacitko.
func open_guide() -> void:
	view = View.GUIDE


func open_settings() -> void:
	view = View.SETTINGS


func open_menu() -> void:
	view = View.MENU


func is_battle() -> bool:
	return view == View.BATTLE


func is_settings() -> bool:
	return view == View.SETTINGS


func is_guide() -> bool:
	return view == View.GUIDE


func is_menu() -> bool:
	return view == View.MENU


# Vyzada aktualizaci PWA. Nejdriv zkusi normalni cestu (nova verze uz ceka
# ve service workeru), a kdyz nic neceka, registraci ODREGISTRUJE a znovu
# zaregistruje - tim se stahne vse znovu ze site. Bez toho zustane hraci
# stara verze, dokud nezavre vsechny panely, coz u PWA nejde.
func request_update() -> void:
	update_note = ""
	if not web:
		update_note = "Aktualizace je jen pro webovou verzi."
		return
	var jb: Object = Engine.get_singleton("JavaScriptBridge")
	if jb == null:
		update_note = "Prohlížeč neumí aktualizaci na pozadí."
		return
	var js := """
	(async () => {
	  try {
	    if (!('serviceWorker' in navigator)) { return 'n/a'; }
	    const regs = await navigator.serviceWorker.getRegistrations();
	    if (regs.length === 0) { return 'none'; }
	    for (const r of regs) { await r.update(); }
	    // Pres cache zadna sila - registrace se zrusi a znovu zalozi,
	    // takze se vse stahne znovu ze site. Je to hrubsi, ale funguje
	    // i tomu, kdo ma hru otevrenou jako nainstalovanou aplikaci,
	    // kde zavreni vsech panelu neni mozne.
	    for (const r of regs) { await r.unregister(); }
	    await navigator.serviceWorker.register('index.service.worker.js', {scope: './'});
	    const cc = await caches.keys();
	    for (const k of cc) { await caches.delete(k); }
	    if (window.godotBridge && window.godotBridge.onUpdate) {
	      window.godotBridge.onUpdate('hard');
	    }
	    setTimeout(() => location.reload(), 900);
	    return 'hard';
	  } catch (e) {
	    if (window.godotBridge && window.godotBridge.onUpdate) {
	      window.godotBridge.onUpdate('err:' + e);
	    }
	    return 'err:' + e;
	  }
	})()
	"""
	jb.call("eval", js, false)


# Vysledek se zpet do GDScriptu vraci pres callback (JavaScriptBridge.eval
# u Promise vrati null, ne hodnotu). Hlaska se tak ukaze jeste pred
# restartem stranky.
func apply_update_note(code: String) -> void:
	match code:
		"hard":
			update_note = "Cache smazána — restartuji…"
		"none":
			update_note = "Hra neběží jako PWA — není co aktualizovat."
		"n/a":
			update_note = "Prohlížeč neumí aktualizaci na pozadí."
		_:
			update_note = "Aktualizace se nepodařila: " + code
