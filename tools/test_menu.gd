extends SceneTree

# Test MENU A NASTAVENI. Nemeni se tu herni logika, ale to, co hrac vidi
# jako prvni obrazovku a kam se z ni dostane:
#   * stavova masina obrazovek (menu / nastaveni / bitva),
#   * seznam tlacitek a jejich AKCE (ze se nevybiraji podle poradi),
#   * hlasky aktualizace (i to, ze mimo web se nic nestahuje),
#   * prepinac jakosti vykreslovani.
# Vystup: MENU_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0
# Klepaci testy se pousteji JEDNOU, v prvnim snimku (viz poznamka nize).
var _ran: bool = false


# POZOR NA PORADI - dvakrat jsem na to koukal a je to past:
#   * `_init` SceneTree skriptu bezi PRED tim, nez je strom postaveny,
#   * `_initialize` taky - koren sice existuje, ale jeste NENI ve strome, takze
#     `add_child` uvnitr obrazovky proběhne do uzlu mimo strom: `_ready` dostane
#     `get_viewport() == null` (spadne na `size_changed`), `get_viewport_rect()`
#     vrati prazdny obdelnik a vsechna tlacitka vyjdou mimo displej.
# Klepaci testy proto bezi az v PRVNIM SNIMKU (`_process`), kdy strom stoji.
# Kdyby se nekdy presunuly zpatky do `_init`, testy projdou a meri nic.
func _init() -> void:
	_run("menu zacina v menu", _test_starts_in_menu)
	_run("seznam tlacitek a akci sedi", _test_items_and_actions)
	_run("obrazovky se prepinaji", _test_views)
	_run("update mimo web nic nestahuje", _test_update_offline)
	_run("hlasky aktualizace", _test_update_notes)
	_run("otisk buildu mimo web", _test_build_id)
	_run("jakost vykreslovani se prepina", _test_lowres)
	_run("stav z prohlizece se mimo web neprevzima", _test_pull_state_offline)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run("klepnuti na HRAT otevre bitvu", _test_tap_starts_battle)
	_run("odchod z bitvy se nejdriv zepta", _test_tap_leave_asks)
	_run("nastaveni a update se ovladaji klepnutim", _test_tap_settings_and_update)
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("MENU_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	return true


# ------------------------------------------------------------------ POMOCNE

func _run(name: String, fn: Callable) -> void:
	var before: int = fails.size()
	fn.call()
	if fails.size() == before:
		print("  ok   %s" % name)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)
		print("       FAIL: %s" % msg)


# -------------------------------------------------------------------- TESTY

func _test_starts_in_menu() -> void:
	var m := Menu.new()
	_check(m.is_menu(), "hra nezacina v menu")
	_check(not m.is_battle(), "hra zacina rovnou v bitve")
	_check(not m.is_settings(), "hra zacina v nastaveni")
	_check(m.update_note == "", "menu zacina s hláskou o aktualizaci")


func _test_items_and_actions() -> void:
	_check(Menu.MENU_ITEMS.size() == Menu.MENU_ACTIONS.size(),
		"tlacitek je %d, akci %d" % [Menu.MENU_ITEMS.size(), Menu.MENU_ACTIONS.size()])
	_check(Menu.MENU_ITEMS.size() == Menu.MENU_SUBS.size(),
		"tlacitek je %d, podtitulku %d" % [Menu.MENU_ITEMS.size(), Menu.MENU_SUBS.size()])
	var known: Array = ["battle", "settings", "update"]
	var seen: Dictionary = {}
	for act in Menu.MENU_ACTIONS:
		_check(known.has(String(act)),
			"neznama akce tlacitka '%s' (obrazovka by na ni nereagovala)" % str(act))
		_check(not seen.has(String(act)), "akce '%s' je v seznamu dvakrat" % str(act))
		seen[String(act)] = true
	# KAZDA OBRAZOVKA, KTERA V MENU JE, MUSI MIT AKCI - jinak je to tlacitko,
	# ktere nic nedela.
	_check(seen.has("battle") and seen.has("settings") and seen.has("update"),
		"v menu chybi nektera z akci (hrani / nastaveni / aktualizace)")


func _test_views() -> void:
	var m := Menu.new()
	m.open_battle()
	_check(m.is_battle() and not m.is_menu(), "HRAT neotevre bitvu")
	m.open_settings()
	_check(m.is_settings() and not m.is_battle(), "SETTINGS neotevre nastaveni")
	m.open_menu()
	_check(m.is_menu() and not m.is_settings(), "ZPET nevrati do menu")


func _test_update_offline() -> void:
	var m := Menu.new()
	_check(not m.web, "testovaci menu se hlasi jako webove")
	m.request_update()
	_check(m.update_note == "Aktualizace je jen pro webovou verzi.",
		"mimo web se nerekne, ze neni co aktualizovat (hlaska: '%s')" % m.update_note)


func _test_update_notes() -> void:
	var cases: Array = [
		["hard", "Cache"],
		["none", "PWA"],
		["n/a", "Prohlížeč"],
		["err:boom", "nepodařila"],
	]
	for c in cases:
		var m := Menu.new()
		m.apply_update_note(String(c[0]))
		_check(m.update_note.contains(String(c[1])),
			"hlaska pro '%s' neobsahuje '%s' (je: '%s')" % [str(c[0]), str(c[1]), m.update_note])


func _test_build_id() -> void:
	var m := Menu.new()
	m.load_build_id()
	_check(m.build_id == "dev", "mimo web se otisk buildu nacita z prohlizece (%s)" % m.build_id)


func _test_lowres() -> void:
	var s := Settings.new()
	_check(not s.lowres, "hra zacina v uspornem rezimu (ma zacinat v nativnim)")
	_check(s.lowres_text() == "Nativní", "popisek nativniho rezimu je '%s'" % s.lowres_text())
	s.toggle_lowres()
	_check(s.lowres, "prepinac jakosti nic nezmenil")
	_check(s.lowres_text() == "Úsporné", "popisek usporneho rezimu je '%s'" % s.lowres_text())
	s.toggle_lowres()
	_check(not s.lowres, "druhe klepnuti nevratilo nativni rezim")


# STAV Z PROHLIZECE (otisk buildu, vysledek aktualizace). Mimo web se nesmi
# cist NIC - kdyby se funkce ptala prohlizece i na desktopu, spadla by.
func _test_pull_state_offline() -> void:
	var m := Menu.new()
	_check(m.build_id == "?", "menu nezacina s neznamym otiskem (%s)" % m.build_id)
	_check(not m.pull_js_state(), "mimo web se stav z prohlizece prevzal")
	m.load_build_id()
	_check(m.build_id == "dev", "mimo web se otisk nacita z prohlizece (%s)" % m.build_id)
	_check(not m.pull_js_state(), "mimo web se stav z prohlizece prevzal")
	_check(m.build_id == "dev", "mimo web se otisk zmenil")


# =========================================================================
# KLEPNUTI NA OBRAZOVKY
#
# Tohle je jedina cast, ktera se neda overit ctenim zdroje: kam ktere klepnuti
# vede a jaky stav po nem zustane. Postup je z popisu pasti v skillu:
# `add_child` -> rucne `_ready()` (v `_init` stromu jeste neproběhlo) ->
# `layout.update(velikost)` (viewport je v testu 0x0) -> teprve pak klepat.
# =========================================================================

func _screen() -> Node2D:
	var scn: PackedScene = load("res://main.tscn")
	var v: Node2D = scn.instantiate()
	get_root().add_child(v)
	if v.get("game") == null:
		v.call("_ready")
	# Rozvrzeni se prelozi na SKUTECNOU velikost okna - v `_init` by byla
	# nulova a vsechna tlacitka by vysla mimo displej.
	v.call("_refield")
	# STRAZCE: kdyby obrazovka nebyla ve strome, je viewport prazdny a vsechny
	# klepace testy by prosly, aniž by na neco klepaly. To se uz jednou stalo.
	var l: ScreenLayout = v.get("layout")
	_check(v.is_inside_tree(), "obrazovka neni ve strome (klepani by nikam netrefilo)")
	_check(l.view.x > 1.0 and l.view.y > 1.0,
		"rozvrzeni ma nulovou velikost (klepani by nikam netrefilo)")
	_check(v.get("layout").menu_rects.size() == Menu.MENU_ITEMS.size(),
		"obrazovka nema rozvrzene tlacitka menu")
	return v


func _test_tap_starts_battle() -> void:
	var v: Node2D = _screen()
	var m: Menu = v.get("menu")
	_check(m.is_menu(), "hra neotevrela menu")
	var before: float = v.get("game").lives
	v.call("_tap", (v.get("layout").menu_rects[0] as Rect2).get_center())
	_check(m.is_battle(), "klepnuti na HRAT neotevrelo bitvu")
	_check(v.get("game").lives == before, "nova partie nezacina s plnymi zivoty")
	# Hra se krokuje JEN v bitve: pod menu se nesmi hrat.
	v.call("_process", 1.0)
	var t: float = v.get("game").build_left
	v.get("menu").call("open_menu")
	v.call("_process", 1.0)
	_check(is_equal_approx(v.get("game").build_left, t),
		"pod menu se partie krokuje (priprava se odecitala)")
	v.queue_free()


func _test_tap_leave_asks() -> void:
	var v: Node2D = _screen()
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	v.call("_tap", (l.menu_rects[0] as Rect2).get_center())
	v.call("_tap", l.hud_menu.get_center())
	_check(bool(v.get("leave_ask")), "klepnuti na MENU v bitve se na nic nezeptalo")
	# DOTAZ PARTII POZASTAVI: hrac se nema rozhodovat, zatimco mu umiraji
	# poutnici.
	var t: float = v.get("game").build_left
	v.call("_process", 1.0)
	_check(is_equal_approx(v.get("game").build_left, t),
		"pod dotazem partie bezi dal (priprava se odecitala)")
	# Klepnuti mimo odpoved nic nedela.
	v.call("_tap", Vector2(1.0, 1.0))
	_check(bool(v.get("leave_ask")), "klepnuti mimo dotaz ho zavrelo")
	_check(m.is_battle(), "klepnuti mimo dotaz ukoncilo partii")
	# ZPET DO HRY vrati hru a partie zase bezi.
	v.call("_tap", l.leave_no.get_center())
	_check(not bool(v.get("leave_ask")), "ZPET DO HRY nezavrelo dotaz")
	v.call("_process", 1.0)
	_check(v.get("game").build_left < t, "po ZPET DO HRY se partie nekrokuje")
	# UKONCIT vraci do menu (a dotaz zmizi).
	v.call("_tap", l.hud_menu.get_center())
	v.call("_tap", l.leave_yes.get_center())
	_check(m.is_menu(), "UKONCIT nevratilo do menu")
	_check(not bool(v.get("leave_ask")), "po ukonceni zustal dotaz otevreny")
	v.queue_free()


func _test_tap_settings_and_update() -> void:
	var v: Node2D = _screen()
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	var s: Settings = v.get("settings")
	# SETTINGS je druhe tlacitko v seznamu (akce se vybiraji podle jmena, ale
	# test ma klepat na to, co je opravdu v seznamu).
	var idx: int = Menu.MENU_ACTIONS.find("settings")
	_check(idx >= 0, "v menu chybi obrazovka nastaveni")
	v.call("_tap", (l.menu_rects[idx] as Rect2).get_center())
	_check(m.is_settings(), "klepnuti na SETTINGS neotevrelo nastaveni")
	var before: bool = s.lowres
	v.call("_tap", l.settings_row.get_center())
	_check(s.lowres != before, "radek jakosti vykreslovani nic neprepnul")
	v.call("_tap", l.settings_back.get_center())
	_check(m.is_menu(), "ZPET z nastaveni nevrátilo do menu")
	# UPDATE: mimo web se jen oznami, ze neni co aktualizovat.
	var ui: int = Menu.MENU_ACTIONS.find("update")
	_check(ui >= 0, "v menu chybi tlacitko aktualizace")
	v.call("_tap", (l.menu_rects[ui] as Rect2).get_center())
	_check(m.is_menu(), "klepnuti na UPDATE zmenilo obrazovku")
	_check(m.update_note != "", "klepnuti na UPDATE nic nereklo")
	v.queue_free()
