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
# VELIKOST TELEFONU, NA KTEREM SE KLEPE.
const PHONE := Vector2(390.0, 844.0)
# KOLIK KONTROL MA TEST MIT. Chyba v GDScriptu prerusi funkci, ktera ji
# zpusobila - a kdyz se test prerusí driv, nez stihne zapsat prvni FAIL,
# `_run` napise "ok" a sada je ZELENA, i kdyz se polovina testu vubec
# nespustila. Presne to se stalo, kdyz v obrazovce chybel `game.palette`:
# misto 83 kontrol jich probehlo 37 a verdikt byl MENU_ALL_PASS=true.
const MIN_CHECKS := 80


# POZOR NA PORADI - dvakrat jsem na to koukal a je to past:
#   * `_init` SceneTree skriptu bezi PRED tim, nez je strom postaveny,
#   * `_initialize` taky - koren sice existuje, ale jeste NENI ve strome, takze
#     `add_child` uvnitr obrazovky proběhne do uzlu mimo strom: `_ready` dostane
#     `get_viewport() == null` (spadne na `size_changed`), `get_viewport_rect()`
#     vrati prazdny obdelnik a vsechna tlacitka vyjdou mimo displej.
# Klepaci testy proto bezi az v PRVNIM SNIMKU (`_process`), kdy strom stoji.
# Kdyby se nekdy presunuly zpatky do `_init`, testy projdou a meri nic.
func _init() -> void:
	Profile.allow_save = false
	Settings.allow_save = false
	# UKLADANI ROZEHRANE PARTIE SE V TESTECH VYPINA a presmeruje do vlastniho
	# souboru: obrazovka uklada kazde dve vteriny, takze by testy prepsaly
	# hracovu skutecnou rozehranou partii.
	BattleSave.allow_save = false
	BattleSave.path = "user://test_menu_battle.cfg"
	BattleSave.clear()
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
	_run("panel upgradu v bitve je porad otevreny a nakup funguje", _test_tap_shop_is_permanent)
	_run("pauza v bitve zastavi hru a deska pod ni nereaguje", _test_tap_pause)
	_run("paleta nad panelem prenastavi barvu veze", _test_tap_palette_switches_hue)
	_run("vyber levelu: klepnuti na vyhrany level ho spusti znovu", _test_tap_level_select)
	_run("klepnuti na RESET se vzdy zepta a maze cely postup", _test_tap_reset)
	_run("rozehrana partie se nabidne a klepnuti ji obnovi", _test_tap_resume)
	_run("nastaveni a update se ovladaji klepnutim", _test_tap_settings_and_update)
	_run("smycka paprsku hraje, dokud neco sviti", _test_laser_loop)
	_check(checks >= MIN_CHECKS,
		"probehlo jen %d kontrol z %d - test se nekde prerusil chybou" % [checks, MIN_CHECKS])
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("MENU_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	return true


# SMYCKA PAPRSKU (Jan, Oct 2026): "kdyz je to nepretrzity paprsek, tak by to
# melo delat nejaky kolísavy zvuk po celou dobu trvani." Smycka je STAV, ne
# udalost: dokud ma hra paprsek, hraje; kdyz zhasne, ztichne. Test hlida obe
# strany a Take to, ze soubor je presne 1,000 s pri 44100 Hz - na tom stoji
# to, ze spojnice nesedi na pulku periody a nelupne.
func _test_laser_loop() -> void:
	var v: Node2D = _screen()
	v.set("touched", true)
	(v.get("settings") as Settings).sfx = true
	var m: Menu = v.get("menu")
	m.open_battle()
	var g: Game = v.get("game")
	var pl: AudioStreamPlayer = v.get("laser")
	_check(pl != null and pl.stream != null, "smycka paprsku se nenacetla")
	if pl == null or pl.stream == null:
		v.queue_free()
		return
	var w: AudioStreamWAV = pl.stream
	_check(w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "smycka nema LOOP_FORWARD")
	_check(absf(w.get_length() - 1.0) < 0.001,
		"smycka nema presne 1 s (%.3f)" % w.get_length())
	_check(w.mix_rate == 44100, "smycka nema 44100 Hz (ma %d)" % w.mix_rate)
	# PAPRSEK SVITI -> hraje.
	g.beams = [{"from": Vector2.ZERO, "to": Vector2.ONE, "target": null, "hop": 0, "crit": false}]
	v.call("_sync_laser", 0.5)
	_check(absf(float(v.get("laser_gain")) - 1.0) < 0.01,
		"paprsek sviti a smycka se nerozjela (gain %.2f)" % float(v.get("laser_gain")))
	# PAPRSEK ZHASL -> ztichne.
	g.beams = []
	v.call("_sync_laser", 0.5)
	_check(float(v.get("laser_gain")) < 0.01,
		"paprsek zhasl a smycka hraje dal (gain %.2f)" % float(v.get("laser_gain")))
	v.queue_free()


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
	_check(not m.is_upgrades(), "hra zacina v upravach")
	_check(m.update_note == "", "menu zacina s hláskou o aktualizaci")


func _test_items_and_actions() -> void:
	_check(Menu.MENU_ITEMS.size() == Menu.MENU_ACTIONS.size(),
		"tlacitek je %d, akci %d" % [Menu.MENU_ITEMS.size(), Menu.MENU_ACTIONS.size()])
	_check(Menu.MENU_ITEMS.size() == Menu.MENU_SUBS.size(),
		"tlacitek je %d, podtitulku %d" % [Menu.MENU_ITEMS.size(), Menu.MENU_SUBS.size()])
	var known: Array = ["battle", "levels", "upgrades", "settings", "reset", "update"]
	var seen: Dictionary = {}
	for act in Menu.MENU_ACTIONS:
		_check(known.has(String(act)),
			"neznama akce tlacitka '%s' (obrazovka by na ni nereagovala)" % str(act))
		_check(not seen.has(String(act)), "akce '%s' je v seznamu dvakrat" % str(act))
		seen[String(act)] = true
	# KAZDA OBRAZOVKA, KTERA V MENU JE, MUSI MIT AKCI - jinak je to tlacitko,
	# ktere nic nedela.
	_check(seen.has("battle") and seen.has("upgrades") and seen.has("settings")
		and seen.has("reset") and seen.has("update"),
		"v menu chybi nektera z akci (hrani / vylepseni / nastaveni / reset / aktualizace)")


func _test_views() -> void:
	var m := Menu.new()
	m.open_battle()
	_check(m.is_battle() and not m.is_menu(), "HRAT neotevre bitvu")
	m.open_settings()
	_check(m.is_settings() and not m.is_battle(), "SETTINGS neotevre nastaveni")
	m.open_upgrades()
	_check(m.is_upgrades() and not m.is_settings(), "UPRAVY neotevrou obrazovku uprav")
	m.open_menu()
	_check(m.is_menu() and not m.is_settings() and not m.is_upgrades(), "ZPET nevrati do menu")


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
	var l: ScreenLayout = _phone(v)
	# STRAZCE: kdyby obrazovka nebyla ve strome, je viewport prazdny a vsechny
	# klepace testy by prosly, aniž by na neco klepaly. To se uz jednou stalo.
	_check(v.is_inside_tree(), "obrazovka neni ve strome (klepani by nikam trefilo)")
	_check(l.view == PHONE, "rozvrzeni nema velikost telefonu (%s)" % str(l.view))
	_check(v.get("layout").menu_rects.size() == Menu.MENU_ITEMS.size(),
		"obrazovka nema rozvrzene tlacitka menu")
	return v


# ROZVRZENI ZNOVU NA TELEFON. Kazda akce, ktera rozvrzeni prelozi (`_refield`
# po startu partie, zmena jakosti vykreslovani), ho prelozi na SKUTECNOU
# velikost okna - a v headless behu je to 64x64. Klepace testy pak klepou na
# obdelniky z JINEHO rozvrzeni a minou (v 64x64 navic paleta dole leze do
# horniho pruhu). Prekladat se proto musi po kazde takove akci a `l.view` to
# hlasi nahlas, misto aby to jen tise minulo.
func _phone(v: Node2D) -> ScreenLayout:
	var l: ScreenLayout = v.get("layout")
	l.update(PHONE)
	v.get("game").set_field(l.field_r, l.unit_r, l.center)
	l.layout_palette(v.get("game").palette.size())
	v.call("_sync_shop_shape")
	v.call("_sync_dialogs")
	return l


# VYBER LEVELU. Hrac se musi dostat ZPET k vyhranemu levelu a spustit ho znovu
# - a hra u toho nesmi prepsat profil (postup zustava, jen se neplatí body).
func _test_tap_level_select() -> void:
	var v: Node2D = _screen()
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	var g: Game = v.get("game")
	g.profile.level = 3
	g.profile.best = 2
	var idx: int = Menu.MENU_ACTIONS.find("levels")
	_check(idx > 0, "v menu chybi polozka LEVELY")
	v.call("_tap", (l.menu_rects[idx] as Rect2).get_center())
	_check(m.is_levels(), "klepnuti na LEVELY neotevrelo vyber levelu")
	_check(l.lvl_tiles.size() == 3,
		"vyber levelu nema tri dlazdice za tri odemcene levely (%d)" % l.lvl_tiles.size())
	# ZPET VRACI DO MENU (a klepnuti na dlazdici spusti level az na konci testu -
	# v bitve uz by klepnuti na ZPET nemelo co delat).
	var back: ScreenLayout = _phone(v)
	v.call("_tap", (back.lvl_back as Rect2).get_center())
	_check(m.is_menu(), "klepnuti na ZPET nevratilo do menu")

	# STRANKOVANI: 14 odemcenych levelu = dve stranky po dvanacti.
	g.profile.level = 14
	g.profile.best = 13
	v.call("_tap", (l.menu_rects[idx] as Rect2).get_center())
	_check(m.is_levels(), "vyber levelu se neotevrel podruhe")
	var lp: ScreenLayout = _phone(v)
	_check(lp.lvl_pages == 2, "ctrnact levelu nema dve stranky (%d)" % lp.lvl_pages)
	# VYBER SE OTEVRE NA STRANCE S NEJVYSSIM ODEMCENYM LEVELEM - tam hrac
	# pokracuje, takze nechce listovat.
	_check(lp.lvl_page == 1 and lp.lvl_tiles.size() == 2,
		"vyber se neotevrel na strance s nejvyssim levelem (strana %d, %d dlazdic)"
		% [lp.lvl_page, lp.lvl_tiles.size()])
	v.call("_tap", (lp.lvl_prev as Rect2).get_center())
	var l0: ScreenLayout = _phone(v)
	_check(l0.lvl_page == 0 and l0.lvl_tiles.size() == 12,
		"sipka PREDCHOZI neprelistovala na prvni stranku (strana %d, %d dlazdic)"
		% [l0.lvl_page, l0.lvl_tiles.size()])
	v.call("_tap", (l0.lvl_next as Rect2).get_center())
	var l2: ScreenLayout = _phone(v)
	_check(l2.lvl_page == 1, "sipka DALSI neprelistovala zpet (%d)" % l2.lvl_page)
	# SIPKA ZA POSLEDNI STRANKOU NIC NEDELA (a nic nespusti).
	var n_before: int = g.level
	v.call("_tap", (l2.lvl_next as Rect2).get_center())
	_check(_phone(v).lvl_page == 1, "sipka za posledni strankou prelistovala")
	_check(g.level == n_before, "klepnuti za posledni stranku spustilo level")

	# A TED KLEPNUTI NA VYHRANY LEVEL (druhy) NA PRVNI STRANCE - SPUSTI HO ZNOVU.
	v.call("_tap", (_phone(v).lvl_prev as Rect2).get_center())
	var l3: ScreenLayout = _phone(v)
	_check(l3.lvl_page == 0, "sipka PREDCHOZI neprelistovala zpet (%d)" % l3.lvl_page)
	v.call("_tap", (l3.lvl_tiles[1] as Rect2).get_center())
	_check(m.is_battle(), "klepnuti na dlazdici neotevrelo bitvu")
	_check(g.level == 2, "nezačal druhy level (je %d)" % g.level)
	_check(g.phase == "build", "level nezacal pripravou (%s)" % g.phase)
	_check(g.profile.best == 13 and g.profile.level == 14, "profil se klepanim poskodil")


func _test_tap_starts_battle() -> void:
	var v: Node2D = _screen()
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	_check(m.is_menu(), "hra neotevrela menu")
	var before: float = v.get("game").max_hp
	v.call("_tap", (l.menu_rects[0] as Rect2).get_center())
	_check(m.is_battle(), "klepnuti na HRAT neotevrelo bitvu")
	_check(v.get("game").hp == before and v.get("game").max_hp == before,
		"nova partie nezacina s plnymi zivoty veze")
	l = _phone(v)
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
	v.call("_tap", l.dlg_b.get_center())
	_check(not bool(v.get("leave_ask")), "ZPET DO HRY nezavrelo dotaz")
	v.call("_process", 1.0)
	_check(v.get("game").build_left < t, "po ZPET DO HRY se partie nekrokuje")
	# UKONCIT vraci do menu (a dotaz zmizi).
	v.call("_tap", l.hud_menu.get_center())
	v.call("_tap", l.dlg_a.get_center())
	_check(m.is_menu(), "UKONCIT nevratilo do menu")
	_check(not bool(v.get("leave_ask")), "po ukonceni zustal dotaz otevreny")
	v.queue_free()


# PANEL UPGRADU V BITVE: JE OTEVRENY PORAD (Jan, Oct 2026) a PARTII NEZASTAVUJE -
# stoji mimo herni plochu, takze hrac nakupuje za pochodu. Krizek na zavreni
# neexistuje, klepnuti mimo panel nic nedela.
func _test_tap_shop_is_permanent() -> void:
	var v: Node2D = _screen()
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	v.call("_tap", (l.menu_rects[0] as Rect2).get_center())
	_check(m.is_battle(), "klepnuti na HRAT neotevrelo bitvu")
	l = _phone(v)
	# NENI CO OTEVIRAT: panel je soucasti bitvy, hra pod nim bezi dal.
	_check(not bool(v.call("is_halted")), "s panelem upgradu hra stoji - panel je pritom trvale otevreny")
	var t: float = v.get("game").build_left
	v.call("_process", 1.0)
	_check(v.get("game").build_left < t, "pod panelem se partie nekteruje")
	# KLEPNUTI MIMO PANEL (do pole, do pruhu) NIC NEDELA: panel se nezavre.
	v.call("_tap", Vector2(2.0, l.bar_h + 2.0))
	_check(not bool(v.call("is_halted")), "klepnuti mimo panel hru zastavilo")
	var stats: Array = Upgrades.stats_in(String(v.get("SHOP_CATS")[0]))
	var first_id: String = String(stats[0]["id"])
	v.get("game").gold = 500
	v.call("_tap", (l.shop_cells[0] as Rect2).get_center())
	_check(v.get("game").temp_level(first_id) == 1,
		"klepnuti na bunku v panelu nekouplo krok (%s)" % first_id)
	# KATEGORIE: klepnuti na druhy tab prepne radek (a rozvrzeni se prelozi).
	v.call("_tap", (l.shop_tabs[1] as Rect2).get_center())
	_check(int(v.get("shop_cat")) == 1, "klepnuti na tab nezmenilo kategorii")
	v.queue_free()


# PAUZA / POKRAČOVAT. Jedno tlacitko v hornim pruhu, dva vyznamy. Pod pauzou
# se NESMI zmenit stav hry - ani nakup, ani barva veze -, ale MENU musi jit
# i pod pauzou, jinak by se hrac z pauzy nedostal do menu.
func _test_tap_pause() -> void:
	var v: Node2D = _screen()
	var g: Game = v.get("game")
	var l: ScreenLayout = v.get("layout")
	v.call("_tap", (l.menu_rects[0] as Rect2).get_center())
	l = _phone(v)
	_check(not g.is_paused(), "partie zacina pod pauzou")
	var t: float = g.build_left
	v.call("_tap", l.hud_pause.get_center())
	_check(g.is_paused(), "klepnuti na PAUZU hru nezastavilo")
	v.call("_process", 1.0)
	_check(is_equal_approx(g.build_left, t), "pod pauzou partie bezi dal (priprava se odecitala)")
	# DESKA POD PAUZOU NEREAGUJE.
	var gold: int = g.gold
	g.gold = 500
	var stats: Array = Upgrades.stats_in(String(v.get("SHOP_CATS")[0]))
	var first_id: String = String(stats[0]["id"])
	v.call("_tap", (l.shop_cells[0] as Rect2).get_center())
	_check(g.temp_level(first_id) == 0, "pod pauzou se da nakupovat")
	_check(g.gold == 500, "pod pauzou se menilo zlato")
	var hue: int = g.tower.hue
	if l.pal_rects.size() >= 2:
		v.call("_tap", (l.pal_rects[1] as Rect2).get_center())
	_check(g.tower.hue == hue, "pod pauzou se da prenastavit barva veze")
	# MENU JDE I POD PAUZOU a ZPET DO HRY pauzu nerusi: hrac si ji zapnul sam.
	v.call("_tap", l.hud_menu.get_center())
	_check(bool(v.get("leave_ask")), "pod pauzou se neda odejit do menu")
	v.call("_tap", l.dlg_b.get_center())
	_check(g.is_paused(), "ZPET DO HRY zrusilo pauzu, kterou si hrac zapnul")
	_check(g.tower.hue == hue, "po ZPET DO HRY se zmenila barva veze")
	# POKRACOVAT: hra zase bezi (a zlato nikdo nebral).
	v.call("_tap", l.hud_pause.get_center())
	_check(not g.is_paused(), "klepnuti na POKRACOVAT hru nespustilo")
	v.call("_process", 1.0)
	_check(g.build_left < t, "po zruseni pauzy se partie nekrokuje")
	_check(g.gold == 500, "pauza menila zlato")
	g.gold = gold
	v.queue_free()


# PALETA DOLE JE JEDINA CESTA, JAK PRENASTAVIT BARVU VEZE. Kdyz se rozvrhne
# prazdna (nebo se klepnuti nevyhodnoti), hrac o tuhle mechaniku prijde - a
# presne to se stalo: `game.palette` po refaktoru neexistoval, obrazovka se v
# tech mistech nedokreslila, klepnuti na barvu nic nedelalo a VSEchny testy
# byly zelene. Proto se tady netvrdi jen "pocet sedi" (0 == 0 projde i s chybou),
# ale "na tom miste opravdu neco je a klepnuti opravdu zmeni barvu".
func _test_tap_palette_switches_hue() -> void:
	var v: Node2D = _screen()
	var g: Game = v.get("game")
	var l: ScreenLayout = v.get("layout")
	v.call("_tap", (l.menu_rects[0] as Rect2).get_center())
	l = _phone(v)
	_check(g.palette.size() >= 2, "hra nema paletu (%d barev)" % g.palette.size())
	_check(l.pal_rects.size() >= 2, "paleta nema rozvrzene puntiky (%d)" % l.pal_rects.size())
	_check(g.palette == g.tower.palette, "vez ma jinou paletu nez hra")
	if l.pal_rects.size() < 2:
		v.queue_free()
		return
	var other: int = -1
	for i in range(g.palette.size()):
		if int(g.palette[i]) != g.tower.hue:
			other = i
			break
	_check(other >= 0, "v palete je jen jedna barva (neni co prepnout)")
	if other < 0:
		v.queue_free()
		return
	var want: int = int(g.palette[other])
	v.call("_tap", (l.pal_rects[other] as Rect2).get_center())
	_check(g.tower.hue == want,
		"klepnuti na puntik palety nepreplo barvu veze (%s misto %s)"
		% [Hue.name_of(g.tower.hue), Hue.name_of(want)])
	var first: int = 0 if other != 0 else 1
	v.call("_tap", (l.pal_rects[first] as Rect2).get_center())
	_check(g.tower.hue == int(g.palette[first]),
		"druhe klepnuti na paletu nic nezmenilo (%s)" % Hue.name_of(g.tower.hue))
	v.queue_free()


# ROZEHRANA PARTIE (ukladani stavu bitvy). Klepnuti na HRAT se u ni nejdriv
# zeptá - a POKRACOVAT musi vratit hru do ULOZENE vlny, ne na zacatek levelu.
func _test_tap_resume() -> void:
	var v: Node2D = _screen()
	var g: Game = v.get("game")
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	var idx: int = Menu.MENU_ACTIONS.find("battle")
	# ROZEHRANA PARTIE NA DISKU: slozi se rovnou hra (jako by ji hrac dohral
	# do treti vlny) a ulozi se do TESTOVACIHO souboru.
	BattleSave.clear()
	var saved := Game.new()
	saved.profile = Profile.new()
	saved.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	saved.start_level(2)
	saved.wave = 3
	saved.gold = 77
	for i in range(60 * 12):
		saved.step(1.0 / 60.0)
	BattleSave.allow_save = true
	_check(BattleSave.save(saved), "rozehranou partii se nepodarilo ulozit")
	BattleSave.allow_save = false
	_check(m.is_menu(), "test nezacina v menu")
	# KLEPNUTI NA HRAT SE NEJDRIV ZEPTÁ (hrac muze chtit i novou partii).
	v.call("_tap", (l.menu_rects[idx] as Rect2).get_center())
	_check(bool(v.get("resume_ask")), "HRAT se u ulozene partie na nic nezeptalo")
	_check(m.is_menu(), "HRAT rovnou spustil novou partii, i kdyz je co obnovit")
	_check(g.wave == 1, "hra se rozjela, i kdyz se hrac jeste nerozhodl (vlna %d)" % g.wave)
	_check(l.dlg_a.size.x > 0.0 and l.dlg_b.size.x > 0.0,
		"dotaz na pokracovani nema obe odpovedi")
	# KLEPNUTI MIMO ODPOVED NIC NEDELA.
	v.call("_tap", Vector2(2.0, 2.0))
	_check(bool(v.get("resume_ask")), "klepnuti mimo dotaz ho zavrelo")
	# POKRACOVAT: hrac se vrati do ULOZENE vlny, ne na zacatek levelu.
	v.call("_tap", l.dlg_a.get_center())
	_check(m.is_battle(), "POKRACOVAT neotevrelo bitvu")
	_check(g.level == saved.level and g.wave == saved.wave,
		"POKRACOVAT nevratilo hru do ulozene vlny (%d/%d, ma byt %d/%d)"
		% [g.level, g.wave, saved.level, saved.wave])
	_check(g.gold == saved.gold, "POKRACOVAT nevratilo zlato (%d, ma byt %d)"
		% [g.gold, saved.gold])
	_check(g.pilgrims.size() > 0, "POKRACOVAT nevratilo poutniky na plochu")
	_check(not BattleSave.has() or BattleSave.info()["level"] == saved.level,
		"uloziste se cestou pokazilo")
	v.queue_free()
	# NOVA PARTIE: ulozena bitva se maze a hra zacne na nejvyssim levelu.
	var v2: Node2D = _screen()
	var g2: Game = v2.get("game")
	var l2: ScreenLayout = v2.get("layout")
	BattleSave.allow_save = true
	BattleSave.save(saved)
	BattleSave.allow_save = false
	v2.call("_tap", (l2.menu_rects[idx] as Rect2).get_center())
	v2.call("_tap", l2.dlg_b.get_center())
	_check(v2.get("menu").is_battle(), "NOVA PARTIE neotevrela bitvu")
	_check(g2.wave == 1 and g2.level == g2.profile.level,
		"NOVA PARTIE nezacala novou partii (%d/%d)" % [g2.level, g2.wave])
	_check(not BattleSave.has(), "NOVA PARTIE nechala ulozenou partii na disku")
	v2.queue_free()
	BattleSave.clear()


# RESET MAZE CELY POSTUP A VZDY SE NA TO ZEPTÁ. (Jan, Oct 2026: "Přidáme do menu
# tlačítko Reset, které resetuje celý progres hry. Nebo to už dělá tlačítko
# Update?" - UPDATE nic nemaze, ten jen stahuje novou verzi.)
func _test_tap_reset() -> void:
	var v: Node2D = _screen()
	var g: Game = v.get("game")
	var m: Menu = v.get("menu")
	var l: ScreenLayout = v.get("layout")
	var idx: int = Menu.MENU_ACTIONS.find("reset")
	_check(idx >= 0, "v menu chybi tlacitko RESET")
	if idx < 0:
		v.queue_free()
		return
	# NASILNEJ POSTUP: neco, co ma reset smazat.
	g.profile.body = 120
	g.profile.best = 5
	g.profile.level = 6
	g.profile.perm["ad"] = 3
	_check(m.is_menu(), "test nezacina v menu")
	v.call("_tap", (l.menu_rects[idx] as Rect2).get_center())
	_check(bool(v.get("reset_ask")), "klepnuti na RESET se na nic nezeptalo")
	_check(l.dlg_b.size.x > 0.0, "dotaz na smazani nema tlacitko ZPET")
	# KLEPNUTI MIMO ODPOVED NIC NEDELA (na tohle se neodpovida mimochodem).
	v.call("_tap", Vector2(2.0, 2.0))
	_check(bool(v.get("reset_ask")), "klepnuti mimo dotaz ho zavrelo")
	_check(g.profile.body == 120, "dotaz uz neco smazal (%d bodu)" % g.profile.body)
	# ZPET nic nemaze.
	v.call("_tap", l.dlg_b.get_center())
	_check(not bool(v.get("reset_ask")), "ZPET nezavrelo dotaz na smazani")
	_check(g.profile.body == 120 and g.profile.perm_level("ad") == 3,
		"ZPET neco smazalo (body %d, ad %d)" % [g.profile.body, g.profile.perm_level("ad")])
	# SMAZAT smaze profil a vrati hru na prvni level.
	v.call("_tap", (l.menu_rects[idx] as Rect2).get_center())
	v.call("_tap", l.dlg_a.get_center())
	_check(g.profile.body == 0, "SMAZAT nechal body (%d)" % g.profile.body)
	_check(g.profile.best == 0 and g.profile.level == 1,
		"SMAZAT nechal postup (level %d, best %d)" % [g.profile.level, g.profile.best])
	_check(g.profile.perm_level("ad") == 0, "SMAZAT nechal permanentni vylepseni")
	_check(g.level == 1 and g.wave == 1, "hra nezacala znovu na prvnim levelu (%d/%d)" % [g.level, g.wave])
	_check(m.is_menu(), "po smazani se neotevrelo menu")
	_check(str(v.get("reset_note")) != "", "po smazani se hrac nedozvi, ze se neco stalo")
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
	s.music = true
	v.call("_tap", (l.settings_rows[0] as Rect2).get_center())
	_check(s.lowres != before, "radek jakosti vykreslovani nic neprepnul")
	# DRUHY RADEK = HUDBA, TRETI = ZVUKY (Jan, Oct 2026: "A střelba a zásah by
	# samozřejmě měly mít také zvukové efekty."). Pocet radku musi sedet s tim,
	# co si obrazovka kresli - jinak by posledni volba nikam nevedla.
	_check(l.settings_rows.size() == Settings.ROWS,
		"nastaveni ma %d radku, rozvrzeni %d" % [Settings.ROWS, l.settings_rows.size()])
	_check((v.call("_settings_rows") as Array).size() == Settings.ROWS,
		"obrazovka kresli jiny pocet radku, nez je voleb")
	var mbefore: bool = s.music
	v.call("_tap", (l.settings_rows[1] as Rect2).get_center())
	_check(s.music != mbefore, "radek hudby hudbu neprepnul")
	_check(mbefore, "nastaveni nezacina s hudbou zapnutou")
	v.call("_tap", (l.settings_rows[1] as Rect2).get_center())
	_check(s.music == mbefore, "druhe klepnuti na radek hudby ji nezapnulo zpet")
	# HUDBA: prehravac musi existovat, soubor se musi nacist a stav hry se musi
	# srovnat s nastavenim (ne jen s udalosti klepnuti).
	var pl: AudioStreamPlayer = v.get("music")
	_check(pl != null, "hra si nevytvorila prehravac hudby")
	_check(pl != null and pl.stream != null, "hudba se nenacetla (chybi soubor theme.ogg?)")
	s.music = false
	v.call("_sync_music")
	_check(pl == null or not pl.playing, "vypnuta hudba presto hraje")
	s.music = true
	v.call("_sync_music")
	_check(pl == null or pl.playing, "zapnuta hudba po klepnuti nehraje")
	# BOJOVA HUDBA (Jan, Oct 2026: "Tuto hudbu dáme jako background music
	# v souboji. Pojede ve smyčce. Do nekonečna."). V souboji musi hrat JINA
	# smycka nez v menu, musi byt nastavena na LOOP (jinak po 31 s ztichne)
	# a po navratu do menu se musi vratit tema menu.
	var battle: AudioStream = v.get("music_battle")
	_check(battle != null, "bojova hudba se nenacetla (chybi battle.ogg?)")
	if battle is AudioStreamOggVorbis:
		_check((battle as AudioStreamOggVorbis).loop, "bojova smycka nema zapnuty loop")
	if battle != null:
		_check(absf(battle.get_length() - 31.35) < 0.2,
			"bojova smycka ma jinou delku nez 31,35 s (%.2f)" % battle.get_length())
	v.set("touched", true)
	s.music = true
	m.open_battle()
	v.call("_sync_music")
	_check(pl != null and pl.stream == battle, "v souboji nehraje bojova hudba")
	m.open_menu()
	v.call("_sync_music")
	_check(pl != null and pl.stream == v.get("music_menu"),
		"po navratu do menu nehraje zpet tema menu")
	# Test pokracuje v NASTAVENI (dalsi radky), takze se sem musi vratit -
	# jinak si dalsi kontroly meri neco jineho (presne to jednou shodilo
	# "ZPET z nastaveni nevrátilo do menu").
	m.open_settings()

	# ZVUKY: treti radek je vypne a `_play_sfx` to musi respektovat.
	var voices: Array = v.get("sfx_voices")
	_check(voices.size() > 0, "hra si nevytvorila hlasy pro zvukove efekty")
	# "shot" tu uz neni - paprsek hraje smyckou, ne jednorazovym zvukem (viz
	# `_test_laser_loop`). Zbyly jen zasah a smrt.
	_check((v.get("sfx_streams") as Dictionary).size() >= 2,
		"nenacetly se vsechny zvukove efekty (%d)" % (v.get("sfx_streams") as Dictionary).size())
	v.set("touched", true)
	_check(s.sfx, "nastaveni nezacina se zvuky zapnutymi")
	v.call("_tap", (l.settings_rows[2] as Rect2).get_center())
	_check(not s.sfx, "radek zvuku zvuky nevypnul")
	v.call("_play_sfx", "hit")
	_check(voices.is_empty() or not (voices[0] as AudioStreamPlayer).playing,
		"vypnute zvuky presto hraji")
	s.sfx = true
	v.call("_play_sfx", "hit")
	_check(voices.is_empty() or (voices[0] as AudioStreamPlayer).playing,
		"zapnuty zasah se neprehraje")
	v.call("_tap", l.settings_back.get_center())
	_check(m.is_menu(), "ZPET z nastaveni nevrátilo do menu")
	# UPDATE: mimo web se jen oznami, ze neni co aktualizovat.
	var ui: int = Menu.MENU_ACTIONS.find("update")
	_check(ui >= 0, "v menu chybi tlacitko aktualizace")
	v.call("_tap", (l.menu_rects[ui] as Rect2).get_center())
	_check(m.is_menu(), "klepnuti na UPDATE zmenilo obrazovku")
	_check(m.update_note != "", "klepnuti na UPDATE nic nereklo")
	v.queue_free()
