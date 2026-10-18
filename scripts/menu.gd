class_name Menu
extends RefCounted

# STAV MENU. Prvni obrazovka hry, nez zacne partie. Nema zadnou logiku hry -
# jen vi, ktera obrazovka je otevrena, aby se podle toho kreslilo a
# vyhodnocoval vstup. Vsechno ostatni zustava v Game.
#
# "Update" nerestartuje hru natvrdo. Posle prohlizeci dotaz, aby service
# worker zkontroloval novou verzi a stahl ji - to je presne to, co Jan jinak
# musel delat v anonymnim okne. Mimo web (desktop export) tlacitko jen oznami,
# ze neni co aktualizovat.
#
# Hra se timhle da take PRIDAT NA PLOCHU (PWA): prohlizec nabidne instalaci
# jen tehdy, kdyz je hra normalne otevrena (ne v anonymnim okne) a ma manifest
# + service worker. Oboji web export Godotu prida.

enum View { MENU, LEVELS, SETTINGS, BATTLE, UPGRADES }

const TITLE := "ŽILY 2"
const SUBTITLE := "jedna věž uprostřed, poutníci ze všech stran"

# TLACITKA MENU JSOU JEDEN SEZNAM. Jmeno, podtitulek i AKCE jsou tady spolu a
# ve stejnem poradi - kresleni i vstup z toho ctou. Dva oddelene seznamy
# (jmena tady, cisla v obrazovce) uz jednou vedly k tomu, ze klepnuti na
# "EDITOR" otevrelo navod: akce se vybirala podle poradi, ne podle jmena.
#
# VYLEPSENI (driv "UPRAVY", prejmenovano dle Jana, Oct 2026) jsou permanentni
# upgrady za BODY - bez te obrazovky by hrac nemel jak utratit body za vyhrane
# levely.
#
# RESET je JEDINE tlacitko, ktere maze - proto stoji az pred UPDATE (na kraji,
# kam se neklika omylem) a vzdycky se na nej ptá dialogem. UPDATE nic nemaze:
# jen stahne novou verzi hry (`request_update`).
const MENU_ITEMS := ["HRÁT", "LEVELY", "VYLEPŠENÍ", "SETTINGS", "RESET", "UPDATE"]
const MENU_SUBS := ["partie od nejvyššího levelu", "vrátit se i k vyhraným", "permanentní vylepšení", "jakost vykreslování", "smazat celý postup", "stáhnout novou verzi"]
# Akce se vyhodnocuji PRES JMENO, ne podle poradi.
const MENU_ACTIONS := ["battle", "levels", "upgrades", "settings", "reset", "update"]

# GLOBALNI PROMENNE, KTERYMI PROHLIZEC MLUVI S HROU. Hra si je sama VYCTE
# (`pull_js_state`) - viz poznamka u te funkce, proc to neni callback.
const JS_BUILD := "__zily_build"
const JS_UPDATE := "__zily_update"

# Prepisuje se v `_ready()` podle toho, jestli hra bezi ve webovem exportu.
var web: bool = false
# Otisk buildu, ktery se zobrazuje v menu. Bez nej se neda poznat, jestli hrac
# po aktualizaci vidi novou verzi, nebo mu ji jeste drzi cache service
# workera - presne to hrace mate.
var build_id: String = "?"
# Vysledek posledni aktualizace - kresli se jako hlaska pod tlacitky.
var update_note: String = ""
var view: int = View.MENU


func open_menu() -> void:
	view = View.MENU


func open_settings() -> void:
	view = View.SETTINGS


func open_levels() -> void:
	view = View.LEVELS


func is_levels() -> bool:
	return view == View.LEVELS


func open_battle() -> void:
	view = View.BATTLE


func open_upgrades() -> void:
	view = View.UPGRADES


func is_upgrades() -> bool:
	return view == View.UPGRADES


func is_menu() -> bool:
	return view == View.MENU


func is_settings() -> bool:
	return view == View.SETTINGS


func is_battle() -> bool:
	return view == View.BATTLE


# JavaScriptovy singleton. NIKDY jako globalni identifikator: desktop export si
# webovou tridu nesmi vubec vsimnout.
func _jb() -> Object:
	return Engine.get_singleton("JavaScriptBridge")


func _window() -> Object:
	var jb: Object = _jb()
	if jb == null:
		return null
	return jb.call("get_interface", "window")


# Nacte otisk buildu (version.txt vedle index.html). Vysledek si hra VYCTE
# pozdeji (`pull_js_state`).
func load_build_id() -> void:
	build_id = "dev"
	if not web:
		return
	var jb: Object = _jb()
	if jb == null:
		return
	# POZOR: tohle je zamerne `fetch` + zapis do globalni promenne, NE callback
	# do hry. `JavaScriptBridge.create_callback` se sice podari zaregistrovat
	# (v prohlizeci je videt jako funkce), ale zavolani z JS do GDScriptu
	# NEDOJDE - overeno v Chromiu: po rucnim `setVersion('PROBE99')` zustal
	# v menu otisk "dev". Cteni vlastnosti objektu `window` naproti tomu
	# funguje, takze si hra stav prebere sama. Ne verit mostu, overit ho.
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


# STAV Z PROHLIZECE. Hra si ho prevzme pri kazdem snimku (ale jen nekolikrat za
# sekundu) - zadny callback, zadna skryta cesta. Vraci true, kdyz se neco
# zmenilo (kresli se pak znovu).
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
		# Hlaska se prevezme JEDNOU - jinak by se porad vracela.
		w.set(JS_UPDATE, "")
		changed = true
	return changed


# Vyzada aktualizaci PWA. Nejdriv zkusi normalni cestu (nova verze uz ceka ve
# service workeru), a kdyz nic neceka, registraci ODREGISTRUJE a znovu
# zaregistruje - tim se stahne vse znovu ze site. Bez toho zustane hraci stara
# verze, dokud nezavre vsechny panely, coz u PWA nejde.
func request_update() -> void:
	update_note = ""
	if not web:
		update_note = "Aktualizace je jen pro webovou verzi."
		return
	var jb: Object = _jb()
	if jb == null:
		update_note = "Prohlížeč neumí aktualizaci na pozadí."
		return
	# Hlaska jde do GLOBALNI PROMENNE, ne do callbacku (viz `load_build_id`).
	# A hlasi se VZDY - i to, ze neni co aktualizovat: tlacitko, po kterem se
	# nic nestane a nic nerekne, je pro hrace rozbite.
	var js := """
	(async () => {
	  const note = (c) => { window.%s = c; };
	  try {
	    if (!('serviceWorker' in navigator)) { note('n/a'); return 'n/a'; }
	    // SERVICE WORKER SE REGISTRUJE ASYNC. Kdyz hrac klepne na Update hned
	    // po startu hry, je seznam registraci jeste PRAZDNY a hra by jen
	    // rekla "neni co aktualizovat" - pritom staci chvilku pockat. Ceka se
	    // proto na AKTIVNI registraci, ale S LIMITEM: `serviceWorker.ready`
	    // bez registrace visi VECNE (a hra by se uz nikdy neozvala).
	    await Promise.race([
	      navigator.serviceWorker.ready,
	      new Promise((r) => setTimeout(() => r(null), 3000))
	    ]);
	    const regs = await navigator.serviceWorker.getRegistrations();
	    for (const r of regs) { await r.update(); }
	    // Pres cache zadna sila - registrace se zrusi a znovu zalozi, takze
	    // se vse stahne znovu ze site. Je to hrubsi, ale funguje i tomu, kdo
	    // ma hru otevrenou jako nainstalovanou aplikaci, kde zavreni vsech
	    // panelu neni mozne.
	    for (const r of regs) { await r.unregister(); }
	    if (regs.length > 0) {
	      await navigator.serviceWorker.register('index.service.worker.js', {scope: './'});
	    }
	    const cc = await caches.keys();
	    for (const k of cc) { await caches.delete(k); }
	    // NAVIGACE S RAZITKEM. Bez nej vraci stary service worker (nebo HTTP
	    // cache prohlizece) PORAD ten stary index.html, i kdyz uz je nova verze
	    // na serveru - presne to Jan videl: "použil jsem Update jako vždy a je
	    // to stejné". Jiná adresa je v kazde cache nova polozka, takze se
	    // vzdycky stahuje ze site.
	    note('hard');
	    const bust = location.href.split('#')[0].split('?')[0] + '?v=' + Date.now();
	    setTimeout(() => location.replace(bust), 900);
	    return 'hard';
	  } catch (e) {
	    note('err:' + e);
	    return 'err:' + e;
	  }
	})()
	""" % JS_UPDATE
	jb.call("eval", js, false)


# Vysledek se zpet do GDScriptu vraci pres callback - hlaska se tak ukaze jeste
# pred restartem stranky.
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
