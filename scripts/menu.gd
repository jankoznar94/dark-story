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

enum View { MENU, SETTINGS, BATTLE }

const TITLE := "ZILY"
const SUBTITLE := "elementární poutníci na žilách many"

# Prepisuje se v _ready() podle toho, jestli hra bezi ve webovem exportu.
var web: bool = false
# Vysledek posledni aktualizace - kresli se jako hlaska pod tlacitky.
var update_note: String = ""
var view: int = View.MENU


func open_battle() -> void:
	view = View.BATTLE


func open_settings() -> void:
	view = View.SETTINGS


func open_menu() -> void:
	view = View.MENU


func is_battle() -> bool:
	return view == View.BATTLE


func is_settings() -> bool:
	return view == View.SETTINGS


func is_menu() -> bool:
	return view == View.MENU


# Vyzada aktualizaci PWA: service worker zkontroluje novou verzi a stahne
# ji, pak se stranka sama reloaduje. Pres JavaScriptBridge se saha jen na
# webu - a to dynamicky pres Engine.get_singleton, aby se desktopovy
# export vubec nesnazil resolvnout tridu, kterou nema.
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
	    setTimeout(() => { location.reload(); }, 1400);
	    return 'ok';
	  } catch (e) { return 'err:' + e; }
	})()
	"""
	var res: Variant = jb.call("eval", js, true)
	var s: String = "?" if res == null else str(res)
	match s:
		"ok":
			update_note = "Kontroluji novou verzi — stránka se restartuje…"
		"none":
			update_note = "Hra neběží jako PWA — není co aktualizovat."
		"n/a":
			update_note = "Prohlížeč neumí aktualizaci na pozadí."
		_:
			update_note = "Aktualizace se nepodařila: " + s
