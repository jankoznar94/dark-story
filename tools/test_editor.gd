extends SceneTree

# Test EDITORU: kresleni prstem, kladeni uzlu, deleni cest, guma.
# Vystup: EDITOR_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0


func _init() -> void:
	# Testy si po sobe uklidi: editor uklada pri kazde zmene, takze by po
	# kazdem behu nechaval v user://levels/ hromadu prazdnych levelu a
	# dalsi beh by zacinal v jinem stavu, nez v jakem skoncil.
	_wipe_levels()
	_run("novy level", _test_empty)
	_run("start a cesta", _test_start_and_road)
	_run("rychlý tah", _test_fast_drag)
	_run("uzel deli cestu", _test_node_splits_lane)
	_run("guma", _test_erase)
	_run("jidel a cil", _test_element_and_exit)
	_run("uprava existujiciho useku", _test_edit_existing)
	_run("ukladani a novy level", _test_level_store)
	_run("mista jsou legacy", _test_lane_slots_are_legacy)
	_run("delka cesty prstem", _test_lane_finger)
	_run("posun kusu cesty", _test_move_run)
	_run("typy cest", _test_lane_types)
	_run("oznaceni prvku", _test_select_node)
	_run("zpet", _test_undo)
	_run("presouvani uzlu", _test_move_node)
	_run("obdelnikovy vyber a kopie", _test_box_copy)
	_run("chytani cesty prstem", _test_lane_grab_tools)
	_run("posun vystupku prstem", _test_bump_shift)
	_run("mala tlacitka -/+ a mrizka", _test_steppers_and_grid)
	_run("export", _test_export)
	_run("barva a mista podle typu useku", _test_lane_type_color)
	_run("panely a pruh", _test_panels)
	_run("parametry levelu", _test_level_params)
	_run("rozvrzeni editoru", _test_editor_layout)
	_run("seznam levelu", _test_list)
	if fails.is_empty():
		print("EDITOR_ALL_PASS=true (%d kontrol)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("EDITOR_ALL_PASS=false (%d kontrol)" % checks)
		quit(1)


func _wipe_levels() -> void:
	var d := DirAccess.open("user://levels/")
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".zily"):
			DirAccess.remove_absolute("user://levels/" + f)
		f = d.get_next()
	d.list_dir_end()


func _run(label: String, fn: Callable) -> void:
	var before: int = checks
	fn.call()
	if checks == before:
		fails.append("test '%s' neudelal ani jednu kontrolu - spadl uvnitr" % label)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)


func _ed() -> Editor:
	var e := Editor.new()
	e.reset()
	return e


# POPISEK TLACITKA ZE STEJNEHO ZDROJE JAKO UI. Tlacitko bydli bud v pruhu,
# nebo v nekterem panelu - hleda se v obojim pres `bar_entries()` /
# `panel_rows()`. Kdyby si test skladal popisek sam, mohl by projit i s
# popiskem, ktery hrac nikde nevidi (a to je presne ta chyba, kterou hledame).
func _panel_label(e: Editor, act: int) -> String:
	for it in e.bar_entries():
		if int(it["act"]) == act:
			return str(it["label"])
	var save: int = e.panel
	for p in range(1, Editor.PANEL_COUNT + 1):
		e.panel = p
		for row in e.panel_rows():
			for it in row:
				if int(it["act"]) == act:
					e.panel = save
					return str(it["label"])
	e.panel = save
	return ""


# TEXTOVA HODNOTA V PANELU (polozka bez akce) JEJIM NAZVEM. Hleda se podle
# popisku, ktery na ni hrac vidi - stejne jako vsechno ostatni z `panel_rows()`.
func _panel_value_label(e: Editor, p: int, needle: String) -> String:
	var save: int = e.panel
	e.panel = p
	var out: String = ""
	for row in e.panel_rows():
		for it in row:
			if int(it["act"]) < 0 and str(it["label"]).begins_with(needle):
				out = str(it["label"])
	e.panel = save
	return out


# JE V PANELU POPISEK S TIMTO SLOVEM? Pouziva se na to, ze se v panelu NEMA
# objevit neco, co uz neexistuje (mista na bonus).
func _panel_has_needle(e: Editor, p: int, needle: String) -> bool:
	var save: int = e.panel
	e.panel = p
	var out: bool = false
	for row in e.panel_rows():
		for it in row:
			if str(it["label"]).contains(needle):
				out = true
	e.panel = save
	return out


# Docasne prepnuti panelu, aby se daly prectit jeho radky.
func _save_panel(e: Editor, p: int) -> void:
	e.panel = p


# TLACITKA V PANELU: cisla akci, ktera panel nabizi (bez hodnotovych popisku).
func _panel_acts(e: Editor, p: int) -> Array:
	var save: int = e.panel
	e.panel = p
	var out: Array = []
	for row in e.panel_rows():
		for it in row:
			if int(it["act"]) >= 0:
				out.append(int(it["act"]))
	e.panel = save
	return out


# LEVEL SE DVEMA POSKOZUJICIMI USEKY: START -> VYHYBKA -> dva cile.
# Usek 0 je VSTUPNI (ze startu) a kresli se jako KMEN - neposkozuje a nema
# mista. Da se ale rucne prepnout na element; testy to hlidaji.
func _lane_level(e: Editor) -> void:
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_VYHYBKA
	e.tap_cell(Vector2i(4, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(8, 2))
	e.tap_cell(Vector2i(8, 8))
	e.tool = Editor.TOOL_ROAD
	e.elem = Element.FIRE
	e.draw_elem = Element.FIRE
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)])
	_stroke(e, [Vector2i(4, 5), Vector2i(4, 4), Vector2i(4, 3), Vector2i(4, 2),
		Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2)])
	_stroke(e, [Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8),
		Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8)])


# Nakresli cestu tahem: prst jede po zadanych bunkach.
func _stroke(e: Editor, cells: Array) -> void:
	e.tool = Editor.TOOL_ROAD
	e.draw_elem = e.elem
	e.begin_draw(cells[0])
	for i in range(1, cells.size()):
		e.extend_draw(cells[i])
	e.end_draw()


# ---------------------------------------------------------------- zaklad

func _test_empty() -> void:
	var e := _ed()
	_check(e.level.lane_count() == 0, "novy level ma mit 0 useku")
	_check(e.level.node_count() == 0, "novy level ma mit 0 uzlu")


func _test_start_and_road() -> void:
	var e := _ed()
	# bez uzlu se cesta nesmi prijmout - jinak by graf nevedel, kudy dal
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)])
	_check(e.level.lane_count() == 0, "cesta mimo uzly se prijala")
	_check(e.status.contains("uzlu"), "status nemluvi o uzlu: " + e.status)

	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	_check(e.level.node_count() == 1, "start se nepoložil")
	_check(e.level.node_kind(0) == Level.START, "prvni uzel neni start")

	e.tool = Editor.TOOL_UZEL
	e.tap_cell(Vector2i(5, 5))
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)])
	_check(e.level.lane_count() == 1, "cesta se nepridala (useku %d)" % e.level.lane_count())
	# VSTUPNI USEK SE KRESLI JAKO KMEN, i kdyz je v palete zvoleny zivel.
	# Driv si odnesl barvu elementu, ale neposkozoval - hrac videl oranzovy
	# pruh a divil se, proc na nem nic nedela. Jan: "barvu má jak element
	# a je to matoucí".
	_check(e.level.lane_element(0) == Level.KMEN,
		"usek ze startu si odnesl zivel (%s) - ma byt kmen" % e.level.lane_type_name(0))
	_check(e.level.lane_is_entry(0), "usek ze startu neni vstupni")
	_check(e.status.contains("vstupní"), "status nemluvi o vstupnim useku: " + e.status)
	# Rozdelana mapa jeste nema cil, takze validate() ji spravne odmitne -
	# testuje se tady jen to, ze cesta a uzly vznikly.
	_check(e.level.lane_start_node(0) == 0, "usek nezacina ve startu")
	_check(e.level.lane_end_node(0) == 1, "usek nekonci v uzlu")


# PRST NENI MYS. Kdyz hrac taha rychle, Godot posle jen kazdou druhou bunku -
# a cesta by se roztrhla. Editor preskocene bunky doplni.
func _test_fast_drag() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_UZEL
	e.tap_cell(Vector2i(7, 5))
	e.tool = Editor.TOOL_ROAD
	e.draw_elem = Element.WATER
	e.begin_draw(Vector2i(1, 5))
	e.extend_draw(Vector2i(4, 5))
	e.extend_draw(Vector2i(7, 5))
	e.end_draw()
	_check(e.level.lane_count() == 1, "rychlý tah neprosel")
	if e.level.lane_count() == 1:
		var cs: Array = e.level.lane_cells(0)
		_check(cs.size() == 7, "preskocene bunky se nedoplnily (bunek %d, ceka se 7)"
			% cs.size())
		var ok: bool = true
		for k in range(1, cs.size()):
			var a: Vector2i = cs[k - 1]
			var b: Vector2i = cs[k]
			if absi(a.x - b.x) + absi(a.y - b.y) != 1:
				ok = false
		_check(ok, "cesta z rychleho tahu neni souvisla")


# UZEL DOPROSTRED CESTY ji ROZDELI. Presne to Jan chtel - ne tri uzly, ktere
# by mu urcil program.
func _test_node_splits_lane() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(9, 5))
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5)])
	_check(e.level.lane_count() == 1, "cesta se nepridala")
	# ted uzel doprostred - cesta se musi rozdelit na dve
	e.tool = Editor.TOOL_VYHYBKA
	e.tap_cell(Vector2i(5, 5))
	_check(e.level.lane_count() == 2, "cesta se nerozdelila (useku %d)" % e.level.lane_count())
	_check(e.level.node_count() == 3, "uzlu ma byt 3, je %d" % e.level.node_count())
	var mid: int = e.level.node_at_cell(Vector2i(5, 5))
	_check(mid >= 0, "vyhybka stoji na 5,5")
	if mid >= 0:
		_check(e.level.node_kind(mid) == Level.VYHYBKA, "uzel na 5,5 neni vyhybka")
		_check(e.level.lanes_into(mid).size() == 1, "do vyhybky nevede jeden usek")
	# druhy vystup z vyhybky: druha cesta z ni do druheho cile
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(5, 2))
	_stroke(e, [Vector2i(5, 5), Vector2i(5, 4), Vector2i(5, 3), Vector2i(5, 2)])
	_check(e.level.lane_count() == 3, "druha cesta se nepridala")
	_check(e.level.node_count() == 4, "uzlu ma byt 4, je %d" % e.level.node_count())
	if mid >= 0:
		_check(e.level.lanes_from(mid).size() == 2, "vyhybka nema dva vystupy")
	var errs2: Array = e.level.validate()
	_check(errs2.is_empty(), "mapa s vyhybkou a cilem neprojde: " + str(errs2))


func _test_erase() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(5, 5))
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)])
	_check(e.level.lane_count() == 1, "cesta se nepridala")
	e.tool = Editor.TOOL_GUMA
	e.tap_cell(Vector2i(3, 5))
	_check(e.level.lane_count() == 0, "guma nesmazala usek")
	e.tap_cell(Vector2i(5, 5))
	_check(e.level.node_count() == 1, "guma nesmazala uzel")


func _test_element_and_exit() -> void:
	var e := _ed()
	# tlacitko typu cesty cykluje pres VSECHNY typy: ctyri zivly,
	# neutralni usek a kmen (poradi je v Editor.TYPE_CYCLE)
	var seen: Array = []
	for i in range(Editor.TYPE_CYCLE.size()):
		seen.append(e.elem)
		e.press(Editor.BTN_ELEM)
	_check(seen.size() == Editor.TYPE_CYCLE.size(), "cyklus typu cest neprosel")
	_check(e.elem == seen[0], "cyklus typu cest se nevratil na zacatek")
	_check(e.bar_entries().size() == 7, "pruh nema 7 polozek (tabu a akci)")
	_check(_panel_acts(e, Editor.PANEL_SEL).size() >= 1, "panel vyberu je prazdny")
	_check(_panel_label(e, Editor.BTN_ELEM) == Element.name_of(e.elem),
		"tlacitko zivlu neukazuje zvoleny zivel")


# UPRAVA JIZ EXISTUJICIHO USEKU. Klepnuti na caru useku (nastrojem cesta) ho
# VYbere a tlacitka "zivel" a "mista" pak meni JEHO vlastnosti. Presne to
# Janovi chybelo: "upravovat jiz existujici zatim nejde".
func _test_edit_existing() -> void:
	var e := _ed()
	_lane_level(e)
	_check(e.level.lane_count() == 3, "level s vyhybkou ma %d useku" % e.level.lane_count())
	_check(e.level.validate().is_empty(),
		"level s vyhybkou je rozbity: " + str(e.level.validate()))
	_check(e.level.lane_is_entry(0), "usek ze startu neni vstupni")

	# klepnuti na caru useku = vyber (a nic se nekresli)
	e.sel_lane = -1
	e.tool = Editor.TOOL_ROAD
	e.begin_draw(Vector2i(6, 2))
	e.end_draw()
	_check(e.level.lane_count() == 3, "klepnuti na usek neco nakreslilo")
	_check(e.sel_lane == 1, "klepnuti na caru useku ho nevybralo (sel %d)" % e.sel_lane)
	_check(e.status.contains("Vybran"), "status nemluvi o vyberu: " + e.status)
	# NASTROJ JE VIDET I SE ZAVRENYM PANELEM: pruh s nastroji uz neni porad
	# na ocich, takze horni pruh musi rict, cim se prave kresli.
	_check(e.sel_text().begins_with(Editor.TOOL_LABELS[e.tool]),
		"horni pruh nerekne, jaky je nastroj: " + e.sel_text())

	# zivel se zmeni NA VYBRANEM useku a rovnou se s nim i kresli dal
	e.elem = Element.FIRE
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(1) == Element.WATER,
		"zivel vybraneho useku se nezmenil (je %s)" % e.level.lane_type_name(1))
	_check(e.elem == Element.WATER, "kreslici zivel se neshoduje s usekem")
	# druhy stisk posune dal - uprava je opakovatelna
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(1) == Element.EARTH, "druha zmena zivlu neprosla")

	# VSTUPNI USEK SE MENIT DA. Od vychoziho stavu je to KMEN (neposkrzuje,
	# kresli se sedy) a hrac ho rucne prepne na element - a zpet na kmen.
	# Jan: "Melo by byt mozne rucne tuto vstupni cestu take prepnout na
	# neco jineho nez kmen, nebo naopak prepnout na kmen." Driv se zmena
	# odmitla, ale barva vstupniho useku se stejne kreslila podle elementu
	# - usek tedy lhal o tom, co dela.
	e.sel_lane = 0
	_check(e.level.lane_is_kmen(0), "usek ze startu neni kmen (je %s)"
		% e.level.lane_type_name(0))
	# CYKLUS VYCHAZI Z TYPU VYBRANEHO USEKU, ne z typu v palete: panel stoji
	# na typu useku, takze stisk musi posunout PRESNE to, co hrac vidi
	# (jinak prvni klepnuti u jineho useku "preskoci" na hodnotu, ktera
	# s nim nesouvisi).
	e.level.set_lane_element(0, Element.AIR)
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(0) == Level.NEUTRAL,
		"vstupnimu useku se nezmenil typ (je %s)" % e.level.lane_type_name(0))
	_check(e.elem == Level.NEUTRAL, "kreslici typ nekopiruje zmenu useku (je %s)"
		% Level.value_name(e.elem))
	_check(e.level.lane_is_neutral(0), "vstupni usek se neprepnul na neutralni typ")
	_check(e.status.contains("Vstupní"), "status nemluvi o vstupnim useku: " + e.status)
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(0) == Level.KMEN,
		"vstupni usek se neprepnul zpet na kmen (je %s)" % e.level.lane_type_name(0))
	_check(e.level.lane_is_neutral(0) or e.level.lane_is_kmen(0), "usek nema ani element, ani kmen")
	_check(e.level.lane_is_kmen(0), "usek ze startu neni kmen")
	# rozdelovani useku si pocet mist odnese do OBOU dilu
	e.sel_lane = 1
	e.tool = Editor.TOOL_UZEL
	e.tap_cell(Vector2i(6, 2))
	_check(e.level.lane_count() == 4, "usek se nerozdelil (useku %d)" % e.level.lane_count())
	if e.level.lane_count() == 4:
		_check(e.level.lane_slot_count(1) == Level.SLOTS
			and e.level.lane_slot_count(3) == Level.SLOTS,
			"po rozdeleni prisel jeden dil o mista")


# POČET MÍST NA ÚSEKU JE LEGACY DATA. Veze se staví do pásu kolem cesty, ne
# na místa na úseku, takže editor žádné ovládání počtu míst nemá - a data si
# usek nese dál, aby se stará mapa dala přečíst a zapsat přesně tak, jak byla.
# DELKA HOTOVE CESTY. Jan (Oct 2026): "Ještě by to chtělo možnost
# zvětšovat/zmenšovat existující cesty... abych nemusel vše dokola mazat
# a znovu vkládat." Vybrany usek se prodlouzi/zkrati, uzly zustavaji, a jde
# to vzit zpet.
# POSUN CELEHO ROVNEHO KUSU. Jan (Oct 2026): "Chci posouvat konce cesty.
# Jakože celé úseky. Horizontální, vertikální. Jako jeden úsek počítám kus po
# nejbližší rohy, nebo uzly." Tah za konec do strany posune cely rovny kus
# za poslednim rohem (nebo uzlem) o bunku vedle - kus zustane rovny.
func _test_move_run() -> void:
	var e := _ed()
	var lv := Level.new()
	var s: int = lv.add_node(2, 5, Level.START)
	var c: int = lv.add_node(6, 5, Level.CIL)
	lv.add_lane(s, c, "RRRR", Element.FIRE)
	e.level = lv
	e.tool = 2   # "cíl" v TOOL_LABELS - tazenim se z prvku presouva
	e.sel_lane = 0
	e.sel_node = c
	var was: int = e.level.lane_cells(0).size()
	_check(was == 5, "testovaci cesta nema 5 bunek (%d)" % was)
	# 1) TAH DO STRANY = POSUN CELEHO KUSU
	_check(e.begin_move(Vector2i(6, 5)), "tazeni za konec cesty nezacalo")
	e.extend_move(Vector2i(6, 6))
	e.end_move()
	var cs: Array = e.level.lane_cells(0)
	_check(cs.size() == was + 1,
		"posun kusu nepridal jednu spojovaci bunku (%d -> %d)" % [was, cs.size()])
	_check(cs[cs.size() - 1] == Vector2i(6, 6), "konec cesty neni o bunku vedle")
	_check(cs[0] == Vector2i(2, 5), "posun kusu utrhl zacatek cesty (%s)" % str(cs[0]))
	var straight: bool = true
	for i in range(cs.size() - 1, 1, -1):
		if (cs[i] - cs[i - 1]) != Vector2i(1, 0):
			straight = false
	_check(straight, "kus u konce po posunu neni rovny: " + str(cs))
	for i in range(cs.size() - 1):
		var d: Vector2i = cs[i + 1] - cs[i]
		_check(absi(d.x) + absi(d.y) == 1, "cesta po posunu neni souvisla (krok %d)" % i)
	# 2) PO SMERU KUSU se dal prodluzuje - puvodni chovani musi zustat
	var len2: int = e.level.lane_cells(0).size()
	_check(e.begin_move(Vector2i(6, 6)), "tazeni za konec nezacalo")
	e.extend_move(Vector2i(7, 6))
	e.end_move()
	var cs2: Array = e.level.lane_cells(0)
	_check(cs2.size() == len2 + 1, "tah po smeru kusu cestu neprodlouzil (%d -> %d)" % [
		len2, cs2.size()])
	_check(cs2[cs2.size() - 1] == Vector2i(7, 6), "konec cesty neni na protazene bunce")


# TVAROVANI CESTY PRSTEM. Jan (Oct 2026): "Nechci měnit velikost pomocí
# tlačítek. Chci ji měnit tahem prstem." V editoru proto ZADNA tlacitka na
# delku cesty nejsou - cesta se chytá prstem za sebe: u kraje se chyti konec
# a posouvá se, uprostred se chyti kus a ohne se (a tahem zpet srovna).
func _test_lane_finger() -> void:
	var e := _ed()
	var lv := Level.new()
	var s: int = lv.add_node(2, 5, Level.START)
	var c: int = lv.add_node(6, 5, Level.CIL)
	lv.add_lane(s, c, "RRRR", Element.FIRE)
	e.level = lv
	e.tool = 2   # "cíl" v TOOL_LABELS - jen aby platilo can_move()
	e.sel_lane = 0
	e.sel_node = c
	# ZADNA TLACITKA NA DELKU CESTY (Jan je nechce)
	_check(not _panel_has_needle(e, Editor.PANEL_SEL, "delší"),
		"panel vyberu porad nabizi tlacitko na delku cesty")
	_check(not _panel_has_needle(e, Editor.PANEL_TOOLS, "kratší"),
		"panel nastroju nabizi tlacitko na delku cesty")
	# 1) CHYTIM KUS UPROSTRED A TÁHNU DO STRANY = OHNE SE U PRSTU
	var was: int = e.level.lane_cells(0).size()
	_check(e.begin_move(Vector2i(4, 5)), "cesta se neda chytit prstem")
	e.extend_move(Vector2i(4, 6))
	var cs: Array = e.level.lane_cells(0)
	_check(cs.size() == was + 2,
		"ohnuti kusu nepridalo dve bunky (%d -> %d)" % [was, cs.size()])
	_check(cs.has(Vector2i(4, 6)),
		"ohnuti nevzniklo u bunky, za kterou hrac chytil: " + str(cs))
	_check(cs.has(Vector2i(4, 5)), "ohnuti utrhlo bunku, za kterou hrac chytil")
	# 2) TAH ZPET NA PUVODNI MISTO = SROVNA SE (a to same gesto)
	e.extend_move(Vector2i(4, 5))
	_check(e.level.lane_cells(0).size() == was,
		"tah zpet kus nesrovnal (%d vs %d)" % [e.level.lane_cells(0).size(), was])
	e.end_move()
	# 3) CHYTIM CESTU U KONCE = POSOUVA SE KONEC (ne uzel - cestu)
	var len3: int = e.level.lane_cells(0).size()
	_check(e.begin_move(Vector2i(5, 5)), "cesta se u konce neda chytit")
	e.extend_move(Vector2i(6, 6))
	e.end_move()
	var cs3: Array = e.level.lane_cells(0)
	_check(cs3[cs3.size() - 1] == Vector2i(6, 6),
		"tah za cestu u konce neposunul konec (%s)" % str(cs3[cs3.size() - 1]))
	_check(cs3.size() == len3 + 1, "posun konce nepridal jednu spojovaci bunku")
	# 4) KLEPNUTI NA CESTU (tah bez pohybu) dal ROZDELI cestu na dve
	var lanes_before: int = e.level.lane_count()
	_check(e.begin_move(Vector2i(3, 6)), "cesta se neda chytit")
	e.end_move()
	_check(e.level.lane_count() == lanes_before + 1,
		"klepnuti na cestu ji nerozdelilo (%d)" % e.level.lane_count())


# UKLADANI, NACITANI A NOVE LEVELY. Jan (Oct 2026): "Načítání, ukládání
# a vytváření nových levelů nefunguje moc dobře. Některé nejdou otevřít, při
# vytváření nového tam zůstává název předchozího."
#
# Hlida se pet veci:
#   * novy level ma NOVE jmeno a nic se po nem neuklada,
#   * nakresleny level se objevi v seznamu a da se otevrit,
#   * otevreni levelu nemeni jeho soubor (neuklada se podruhe jinam),
#   * ROZPRACOVANY level (s chybou v mape) se musi dat otevrit - prace
#     hrace je v souboru a musi se k ni dostat,
#   * po sobe uklidi (jinak by v seznamu zustavaly testovaci polozky).
func _test_level_store() -> void:
	var e := _ed()
	_clean_test_levels()
	# 1) NOVY LEVEL
	e.reset()
	var n1: String = e.local_name
	_check(n1 != "", "novy level nema jmeno")
	_check(e.level.name == n1, "jmeno levelu nesedi s klicem (%s vs %s)" % [
		n1, e.level.name])
	_check(e.level.lane_count() == 0 and e.level.node_count() == 0,
		"novy level neni prazdny")
	_check(not Level.saved_keys().has(n1),
		"prazdny novy level se hned ulozil jako %s" % n1)
	# 2) DRUHY NOVY LEVEL MA JINE JMENO
	e.reset()
	var n2: String = e.local_name
	_check(n2 != n1, "druhy novy level ma stejne jmeno jako prvni (%s)" % n2)
	# 3) NAKRESLI A ULOZ
	var s: int = e.level.add_node(1, 1, Level.START)
	var c: int = e.level.add_node(5, 1, Level.CIL)
	e.level.add_lane(s, c, "RRRR", Element.FIRE)
	e.level.save()
	_check(Level.saved_keys().has(n2), "nakresleny level se neulozil jako %s" % n2)
	# 4) OTEVRI HO ZNOVU ZE SEZNAMU
	e.reset()
	e.open_list()
	var found: bool = false
	for it in e.list_items():
		if str(it["kind"]) == "level" and str(it["key"]) == n2:
			found = true
			e.pick(it)
	_check(found, "ulozeny level %s neni v seznamu" % n2)
	_check(e.level.lane_count() == 1,
		"nacteny level nema cestu (%d)" % e.level.lane_count())
	_check(e.level.node_count() == 2,
		"nacteny level nema oba prvky (%d)" % e.level.node_count())
	_check(e.local_name == n2, "po nacteni nesedi jmeno (%s vs %s)" % [e.local_name, n2])
	var files: int = Level.saved_keys().size()
	e.level.save()
	_check(Level.saved_keys().size() == files,
		"ulozene nacteneho levelu udelalo druhy soubor (%d -> %d)" % [
			files, Level.saved_keys().size()])
	# 5) ROZPRACOVANY LEVEL (CHYBA V MAPE) SE MUSI DAT OTEVRIT
	var bad := Level.new()
	bad.name = "test-rozepsany"
	bad.add_node(2, 2, Level.START)
	_check(not bad.validate().is_empty(), "testovaci level ma byt s chybou")
	_check(bad.save(), "rozepsany level se neulozil")
	var probe := Level.new()
	_check(probe.load_from_disk("test-rozepsany"),
		"rozepsany level se neda otevrit (presne to Jan videl)")
	_check(probe.node_count() == 1, "otevreny rozepsany level nema svuj prvek")
	# 6) UKLID
	_clean_test_levels()


func _clean_test_levels() -> void:
	for k in ["test-rozepsany"]:
		var p: String = Level.storage_dir() + str(k) + ".zily"
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _test_lane_slots_are_legacy() -> void:
	var e := _ed()
	_lane_level(e)
	_check(e.level.lane_slot_count(1) == Level.SLOTS,
		"usek nema vychozi pocet mist (%d)" % e.level.lane_slot_count(1))
	_check(not e.sel_text().contains("míst"),
		"vyber v hornim pruhu hlasi mista na bonus: " + e.sel_text())
	for p in [Editor.PANEL_SEL, Editor.PANEL_TOOLS]:
		_check(not _panel_has_needle(e, p, "míst"),
			"panel %d porad nabizi mista na bonus" % p)


# TYPY CEST: zivly + neutralni usek + kmen. Jan: "v nabidce typu cest
# chybi neutralni a kmen (nedava zadne poskozeni)".
func _test_lane_types() -> void:
	var e := _ed()
	e.sel_lane = -1
	e.sel_node = -1
	var seen: Dictionary = {}
	for i in range(Editor.TYPE_CYCLE.size()):
		seen[e.elem] = true
		e.press(Editor.BTN_ELEM)
	_check(seen.has(Level.NEUTRAL), "v nabidce typu cest chybi neutralni usek")
	_check(seen.has(Level.KMEN), "v nabidce typu cest chybi kmen")
	_check(seen.size() == Editor.TYPE_CYCLE.size(), "cyklus typu cest neprosel vsechny")
	_check(e.elem == int(Editor.TYPE_CYCLE[0]), "cyklus typu cest se nevratil na zacatek")
	_check(Level.value_name(Level.KMEN) == "kmen", "kmen se jmenuje spatne")
	_check(Level.value_name(Level.NEUTRAL) == "neutrální", "neutralni usek se jmenuje spatne")

	# KMEN NAKRESLENY RUKOU: neposkozuje, nema mista a neposila se z nej
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(7, 5))
	e.elem = Level.KMEN
	e.tool = Editor.TOOL_ROAD
	e.draw_elem = Level.KMEN
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	_check(e.level.lane_count() == 1, "kmen se nenakreslil")
	_check(e.level.lane_is_kmen(0), "usek nema typ kmen (je %s)" % e.level.lane_type_name(0))
	_check(e.level.lane_is_neutral(0) or e.level.lane_is_kmen(0), "usek nema ani element, ani kmen")
	_check(not e.level.spawn_elements().has(Level.KMEN), "z kmene se posila poutnik")
	_check(e.level.spawn_elements().is_empty(),
		"z kmene se posilaji poutnici: " + str(e.level.spawn_elements()))
	_check(Level.value_name(e.level.lane_element(0)) == "kmen", "kmen nema jmeno")

	# a neutralni usek na POSKOZUJICIM useku: poskozuje vsechny stejne,
	# ale taky se na nem nestavi a neposila se z nej
	var f := _ed()
	_lane_level(f)
	f.sel_lane = 1
	f.sel_node = -1
	# CYKLUS TYPU VYCHAZI Z VYBRANEHO USEKU (panel stoji na jeho typu), takze
	# se nastavuje typ useku - ne "kreslici" typ v palete.
	f.level.set_lane_element(1, Element.AIR)
	f.press(Editor.BTN_ELEM)
	_check(f.level.lane_element(1) == Level.NEUTRAL, "neutralni usek se nenastavil")
	_check(f.level.lane_is_neutral(1), "usek neni neutralni")
	_check(not f.level.lane_is_kmen(1), "neutralni usek se tvari jako kmen")
	_check(f.level.lane_is_neutral(1), "usek neni neutralni")
	_check(not f.level.spawn_elements().has(Level.NEUTRAL),
		"z neutralniho useku se posila poutnik")
	# PO ZMENE NA NEUTRALNI zbyde v mape jen Ohen - a ten tu nema svuj protiklad
	# (vodu), takze se z nej neposila: poutnik Ohne by nemel kde zemrit.
	_check(f.level.present_elements() == [Element.FIRE],
		"po zmene na neutralni zbyva spatny zivel: " + str(f.level.present_elements()))
	_check(f.level.spawn_elements().is_empty(),
		"Ohen bez protikladu se posila: " + str(f.level.spawn_elements()))
	_check(f.level.unkillable_elements() == [Element.FIRE],
		"Ohen bez protikladu neni hlasen jako nezabitelny")


# OZNACENI JIZ EXISTUJICIHO PRVKU. Jan: "chybi mi moznost oznacit jiz
# existujici prvek, abych ho mohl upravit". Klepnutim nastrojem "cesta"
# se oznaci uzel nebo usek a tlacitko "mista" se u prvku zmeni na "druh".
func _test_select_node() -> void:
	var e := _ed()
	_lane_level(e)
	e.sel_lane = -1
	e.sel_node = -1
	e.tool = Editor.TOOL_ROAD
	# klepnuti na UZEL oznaci prave uzel (ne usek, ktery pod nim vede)
	e.begin_draw(Vector2i(4, 5))
	e.end_draw()
	_check(e.sel_node == 1, "klepnuti na prvek neoznacilo prvek (sel_node %d)" % e.sel_node)
	_check(e.sel_lane == -1, "oznaceni prvku nechalo oznaceny i usek")
	_check(e.status.contains("prvek"), "status nemluvi o prvku: " + e.status)
	_check(e.sel_text().contains("výhybka"), "vyber neukazuje druh prvku: " + e.sel_text())
	# tlacitko "mista" se u prvku zmeni na "druh" a opravdu meni druh
	_check(_panel_label(e, Editor.BTN_KIND).begins_with("druh:"),
		"tlacitko u prvku neukazuje druh: " + _panel_label(e, Editor.BTN_KIND))
	var before: int = e.level.node_kind(1)
	e.press(Editor.BTN_KIND)
	_check(e.level.node_kind(1) == (before + 1) % Level.KIND_NAMES.size(),
		"druh prvku se nezmenil")
	_check(_panel_label(e, Editor.BTN_KIND) == "druh: %s" % e.level.kind_name(e.level.node_kind(1)),
		"tlacitko nelze o druhu prvku: " + _panel_label(e, Editor.BTN_KIND))
	# klepnuti na CARU useku (ne na uzel) oznaci usek
	e.tool = Editor.TOOL_ROAD
	e.begin_draw(Vector2i(6, 2))
	e.end_draw()
	_check(e.sel_lane == 1 and e.sel_node == -1,
		"klepnuti na caru useku neoznacilo usek (lane %d, node %d)" % [e.sel_lane, e.sel_node])
	# a paletou se da prvek zmenit i dal - klepnuti na uzel s nastrojem
	e.tool = Editor.TOOL_SPOJKA
	e.tap_cell(Vector2i(1, 5))
	_check(e.level.node_kind(0) == Level.SPOJKA, "paleta neprekreslila druh prvku")


# ZPET. Kazda uprava musi jit vratit - vcetne presunu uzlu (cely tah je
# jedna uprava) a vcetne levelu, ktery hrac omylem prepsal novym.
func _test_undo() -> void:
	var e := _ed()
	_check(_panel_label(e, Editor.BTN_UNDO) == "zpět",
		"v pruhu neni tlacitko zpet: " + _panel_label(e, Editor.BTN_UNDO))
	e.press(Editor.BTN_UNDO)
	_check(e.status.contains("Není co vrátit"), "zpet na prazdnem levelu nehlasi: " + e.status)

	# start, cil a cesta - kazdy krok zpet
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(7, 5))
	e.tool = Editor.TOOL_ROAD
	_stroke(e, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	_check(e.level.lane_count() == 1, "cesta se nepridala")
	e.press(Editor.BTN_UNDO)
	_check(e.level.lane_count() == 0, "zpet nevratilo nakreslenou cestu")
	_check(e.level.node_count() == 2, "zpet vzalo i uzly")
	e.press(Editor.BTN_UNDO)
	_check(e.level.node_count() == 1, "zpet nevratilo položeny cil")
	e.press(Editor.BTN_UNDO)
	_check(e.level.node_count() == 0, "zpet nevratilo položeny start")

	# PRESUN UZLU: cely tah je JEDNA uprava, ne krok za bunku
	_lane_level(e)
	e.tool = Editor.TOOL_START
	var start_node: int = e.level.first_start()
	_check(e.begin_move(Vector2i(1, 5)), "tazeni ze startu nezacalo")
	e.extend_move(Vector2i(1, 3))
	e.end_move()
	_check(e.level.node_cell(start_node) == Vector2i(1, 3),
		"start se nepresunul (je na %s)" % str(e.level.node_cell(start_node)))
	e.press(Editor.BTN_UNDO)
	_check(e.level.node_cell(start_node) == Vector2i(1, 5),
		"zpet nevratilo presun (je na %s)" % str(e.level.node_cell(start_node)))

	# POCET MIST a DRUH PRVKU se taky vraci
	e.sel_lane = 1
	e.sel_node = -1
	e.sel_node = 1
	e.sel_lane = -1
	var kind_before: int = e.level.node_kind(1)
	e.press(Editor.BTN_KIND)
	_check(e.level.node_kind(1) != kind_before, "druh se nezmenil")
	e.press(Editor.BTN_UNDO)
	_check(e.level.node_kind(1) == kind_before, "zpet nevratilo druh prvku")

	# NOVY LEVEL: "zpet" musi vratit i praci, kterou hrac omylem prepsal
	var name_before: String = e.local_name
	e.reset()
	_check(e.level.lane_count() == 0 and e.level.node_count() == 0, "novy level neni prazdny")
	e.press(Editor.BTN_UNDO)
	_check(e.level.lane_count() == 3, "zpet nevratilo level pred novym (%d useku)" % e.level.lane_count())
	_check(e.local_name == name_before, "zpet nevratilo jmeno levelu")


# PRESOUVANI UZLU. Klepnuti uzel zmeni, TAZENI ho presune - a cesty, ktere
# do nej vedly, se prepoji. Testuje se to, co se neda poznat okem: ze cesta
# zustane souvisla, ze se mapa nerozbije a ze klepnuti porad funguje.
func _test_move_node() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(6, 5))
	e.tool = Editor.TOOL_ROAD
	e.begin_draw(Vector2i(1, 5))
	e.extend_draw(Vector2i(6, 5))
	e.end_draw()
	_check(e.level.lane_count() == 1, "cesta se nepridala")
	var start: int = e.level.first_start()
	var cil: int = e.level.node_at_cell(Vector2i(6, 5))

	# --- START DOLEVA: usek se prodlouzi az na okraj mrizky
	e.tool = Editor.TOOL_START
	_check(e.begin_move(Vector2i(1, 5)), "tazeni ze startu nezacalo")
	_check(e.extend_move(Vector2i(0, 5)), "krok presunu neprosel")
	e.end_move()
	_check(e.level.node_cell(start) == Vector2i(0, 5),
		"start se neposunul (je na %s)" % str(e.level.node_cell(start)))
	_check(e.level.lane_count() == 1, "presun uzlu pridal usek")
	_check(e.level.lane_start_node(0) == start, "usek nezacina v presunutem startu")
	_check(e.level.lane_cells(0)[0] == Vector2i(0, 5), "usek nezacina bunkou uzlu")
	_check(e.level.lane_is_entry(0), "presunuty start neni vstup do mapy")
	_check(e.level.validate().is_empty(),
		"po presunu startu je mapa rozbita: " + str(e.level.validate()))

	# --- CIL DOPRAVA
	e.tool = Editor.TOOL_CIL
	_check(e.begin_move(Vector2i(6, 5)), "tazeni z cile nezacalo")
	_check(e.extend_move(Vector2i(8, 5)), "krok presunu cile neprosel")
	e.end_move()
	_check(e.level.node_cell(cil) == Vector2i(8, 5),
		"cil se neposunul (je na %s)" % str(e.level.node_cell(cil)))
	_check(e.level.lane_end_node(0) == cil, "usek nekonci v presunutem cili")
	_check(e.level.validate().is_empty(),
		"po presunu cile je mapa rozbita: " + str(e.level.validate()))
	_check(e.level.lane_cells(0).size() == 9,
		"usek ma po prodlouzeni %d bunek, ceka se 9" % e.level.lane_cells(0).size())

	# --- KLEPNUTI (TAH BEZ POHYBU) PORAD MENI DRUH UZLU
	e.tool = Editor.TOOL_SPOJKA
	_check(e.begin_move(Vector2i(8, 5)), "klepnuti na cil nezacalo")
	e.end_move()
	_check(e.level.node_kind(cil) == Level.SPOJKA,
		"klepnuti na uzel nezmenilo jeho druh")
	# ... a zpet na cil, aby mapa davala smysl
	e.tool = Editor.TOOL_CIL
	e.begin_move(Vector2i(8, 5))
	e.end_move()
	_check(e.level.node_kind(cil) == Level.CIL, "cil se nevrátil")

	# --- UZEL NESMI PREJET NA JINY UZEL
	var e2 := _ed()
	e2.tool = Editor.TOOL_START
	e2.tap_cell(Vector2i(1, 3))
	e2.tool = Editor.TOOL_VYHYBKA
	e2.tap_cell(Vector2i(4, 3))
	e2.tool = Editor.TOOL_ROAD
	e2.begin_draw(Vector2i(1, 3))
	e2.extend_draw(Vector2i(4, 3))
	e2.end_draw()
	e2.tool = Editor.TOOL_CIL
	e2.tap_cell(Vector2i(8, 3))
	e2.tool = Editor.TOOL_ROAD
	e2.begin_draw(Vector2i(4, 3))
	e2.extend_draw(Vector2i(8, 3))
	e2.end_draw()
	# vyhybka musi mit aspon dva vystupy - druhy vede dolu
	e2.tool = Editor.TOOL_CIL
	e2.tap_cell(Vector2i(4, 7))
	e2.tool = Editor.TOOL_ROAD
	e2.begin_draw(Vector2i(4, 3))
	e2.extend_draw(Vector2i(4, 7))
	e2.end_draw()
	_check(e2.level.lane_count() == 3, "treti cesta se nepridala")
	_check(e2.level.validate().is_empty(), "rozdelana mapa neni v poradku")
	var jn: int = e2.level.node_at_cell(Vector2i(4, 3))
	e2.tool = Editor.TOOL_VYHYBKA
	_check(e2.begin_move(Vector2i(4, 3)), "tazeni z vyhybky nezacalo")
	# tah doleva na start: usek se zkrati, ale uzel na start NESMI
	e2.extend_move(Vector2i(1, 3))
	e2.end_move()
	var nj: Vector2i = e2.level.node_cell(jn)
	_check(nj != Vector2i(1, 3), "uzel prejel na druhy uzel (%s)" % str(nj))
	_check(e2.level.node_at_cell(Vector2i(1, 3)) >= 0, "start pri presunu zmizel")
	_check(e2.level.validate().is_empty(),
		"mapa po presunu vyhybky neprojde: " + str(e2.level.validate()))


func _test_export() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(6, 5))
	e.tool = Editor.TOOL_ROAD
	e.draw_elem = Element.AIR
	e.begin_draw(Vector2i(1, 5))
	e.extend_draw(Vector2i(6, 5))
	e.end_draw()
	_check(e.level.lane_count() == 1, "cesta se nepridala")
	e.press(Editor.BTN_EXPORT)
	_check(e.code.begins_with("ZILY2;"), "export nedal kod")
	var back := Level.from_code(e.code)
	_check(back != null, "kod z editoru se neda nacist zpatky")
	if back != null:
		_check(back.to_code() == e.code, "kod se po nacteni zmenil")
		_check(back.lane_count() == e.level.lane_count(), "po nacteni je jiný pocet useku")
		_check(back.spawn_elements() == e.level.spawn_elements(), "po nacteni jine zivly")
	# EXPORT MUSI KOD DOSTAT Z TELEFONU VEN. Vypsany radek se neda oznacit,
	# takze se kod pri exportu kopiruje do schranky - a to se hlida na miste
	# volani, protoze headless se schranka necte.
	var esrc: String = FileAccess.get_file_as_string("res://scripts/editor.gd")
	_check(esrc.contains("Clipboard.copy(code)"), "export nekopiruje kod do schranky")
	_check(esrc.contains("je ve schránce"), "hrac se nedozvi, ze kod je ve schrance")
	_check(not Clipboard.copy(""), "prazdny text se do schranky kopirovat nema")


# BARVA A MISTA PODLE HODNOTY USEKU. Kmen (-2) a neutralni usek (-1) NEJSOU
# elementy, takze se na ne NESMI odpovidat pres `Element.color_of/name_of`:
# GDScript bere zaporny index od konce pole, takze `COLORS[-2]` je barva Zeme
# a `NAMES[-1]` je "Vzduch". Presne to se stalo - kmen se kreslil hnedovy jako
# zemska cesta. A druha vec: `net.lane_is_kmen` v siti VUBEC NEBYLA, i kdyz ji
# game_view volal, takze kazde volani barvy spadlo ("Nonexistent function") a
# GDScript po te chybe ukonci funkci, ktera ji zavolala - `_lane_color`
# vratila null a kazdy pruh krome neutralniho se kreslil CERNY.
func _test_lane_type_color() -> void:
	var kmen: Color = Level.value_color(Level.KMEN)
	var neutral: Color = Level.value_color(Level.NEUTRAL)
	_check(kmen != neutral, "kmen a neutralni usek maji stejnou barvu")
	for e in range(Element.COUNT):
		_check(Level.value_color(e) == Element.color_of(e),
			"barva elementu %s se zmenila" % Element.name_of(e))
		_check(kmen != Element.color_of(e),
			"kmen ma barvu elementu %s" % Element.name_of(e))
	# Hodnota mimo element se NESMI tise preklopit na jiny element.
	_check(Element.color_of(Level.KMEN) != Element.color_of(Element.EARTH),
		"color_of(-2) vraci barvu Zeme (zaporny index)")
	_check(Element.color_of(Level.NEUTRAL) != Element.color_of(Element.AIR),
		"color_of(-1) vraci barvu Vzduchu (zaporny index)")
	_check(Element.name_of(Level.KMEN) == "?", "name_of(-2) vraci jmeno elementu")
	_check(Level.value_name(Level.KMEN) == "kmen", "kmen nema sve jmeno")
	_check(Level.value_name(Level.NEUTRAL) == "neutrální", "neutral nema sve jmeno")

	# SIT MUSI VEDET, CO JE KMEN. Tenhle test spadne na starem kodu tim, ze se
	# ukonci hned na prvnim volani a _run to hlasi jako "neudelal ani jednu
	# kontrolu".
	var g := Game.new()
	g.setup(Rect2(0.0, 0.0, 932.0, 430.0), 1.0, 0.0, Level.base())
	var entry: int = g.net.entry_lane
	_check(entry >= 0, "sit nema vstupni usek")
	_check(g.net.lane_is_kmen(entry), "sit nevi, ze vstupni usek je kmen (net)")
	_check(g.level.lane_is_kmen(entry), "level nevi, ze vstupni usek je kmen")
	for i in range(g.net.lane_count()):
		var col: Color = Level.value_color(g.net.lane_element(i))
		_check(col.r + col.g + col.b > 0.3,
			"usek %d vychazi cerny (%s)" % [i, col])
		if g.net.lane_element(i) == Element.EARTH:
			_check(col == Element.color_of(Element.EARTH),
				"zemsky usek nema barvu Zeme")

	# MISTA: kmen je v DATECH ma (hracuv pocet se nesmi pri zmene typu ztratit),
	# ale UI je hlásit NESMI - a veze se do pasu u kmene vubec nestavi.
	var e2 := Editor.new()
	e2.level = Level.base()
	e2.sel_lane = entry
	_check(e2.level.lane_slot_count(entry) == Level.SLOTS,
		"kmen prisel o pocet mist v datech")
	_check(not e2.sel_text().contains("míst"),
		"popisek u kmene hlasi mista (%s)" % e2.sel_text())
	var elem_lane: int = -1
	for i in range(e2.level.lane_count()):
		if e2.level.lane_is_kmen(i) or e2.level.lane_is_entry(i):
			continue
		elem_lane = i
		break
	_check(elem_lane >= 0, "na zakladni desce neni usek s elementem")

	# Barva pruhu je na JEDNOM miste - kdyby si ji kazda obrazovka pocitala
	# sama, vratila by se ta chyba s kmenem.
	var src: String = FileAccess.get_file_as_string("res://scripts/game_view.gd")
	_check(src.contains("Level.value_color("),
		"barva pruhu nechodi pres Level.value_color")
	_check(not src.contains("Element.color_of(game.net.lane_element"),
		"barva pruhu se pocita z elementu (u kmene je to barva Zeme)")
	_check(not src.contains("Element.color_of(editor.draw_elem)"),
		"nacrt cesty se pocita z elementu (u kmene je to barva Zeme)")


# =========================================================================
# PANELY, PARAMETRY, ROZVRZENI
# =========================================================================

# PRUH S TABY A ROZBALOVACI PANELY. Hlida se:
#   * pruh ma 3 taby + 4 akce a cisla akci v nem nejsou nastroje,
#   * panel "nastroje" nabizi VSECHNY nastroje a klepnuti na nej nastroj
#     opravdu prepne (nastroj je na dvou mistech: v palete a v pruhu stavu),
#   * panel "vyber" se meni podle toho, co je oznacene (usek / prvek / nic)
#     - jinak by hrac videl tlacitka, ktera na jeho vyber neplati,
#   * hodnotovy popisek v panelu "level" NENI tlacitko (nema akci) - kdyby
#     mel, slibil by klepnuti, ktere nic nedela.
func _test_panels() -> void:
	var e := _ed()
	var bar: Array = e.bar_entries()
	_check(bar.size() == 7, "pruh nema 7 polozek (ma %d)" % bar.size())
	var tabs: int = 0
	var acts: Array = []
	for it in bar:
		if int(it["tab"]) >= 0:
			tabs += 1
		else:
			acts.append(int(it["act"]))
	_check(tabs == 3, "v pruhu nejsou tri taby (jsou %d)" % tabs)
	for a in [Editor.BTN_UNDO, Editor.BTN_LIST, Editor.BTN_EXPORT, Editor.BTN_PLAY]:
		_check(acts.has(a), "v pruhu chybi akce %d" % a)

	# NASTROJE: vsechny a klepnuti na kazdy opravdu prepne nastroj
	var tools: Array = _panel_acts(e, Editor.PANEL_TOOLS)
	var tool_acts: Array = []
	for a in tools:
		if int(a) < Editor.TOOL_COUNT:
			tool_acts.append(int(a))
	_check(tool_acts.size() == Editor.TOOL_COUNT,
		"panel nastroju nema %d tlacitek (ma %d)" % [Editor.TOOL_COUNT, tool_acts.size()])
	# PANEL NASTROJU MA DVA RADKY: nahore parametry (typ cesty + mista),
	# dole samotne nastroje u pruhu. Hrac tak vidi, CIM pracuje i CO tim
	# prave meni - a hodnoty jsou predvyplnene podle vyberu.
	var rows0: Array = []
	_save_panel(e, Editor.PANEL_TOOLS)
	rows0 = e.panel_rows()
	e.panel = Editor.PANEL_NONE
	_check(rows0.size() == 2, "panel nastroju ma %d radku" % rows0.size())
	if rows0.size() == 2:
		var line: Array = rows0[0]
		var gaps: int = 0
		for it in line:
			if str(it["kind"]) == "spacer":
				gaps += 1
		_check(gaps == 1, "v panelu nastroju chybi predel mezi skupinami (%d)" % gaps)
		var labels: Array = []
		for it in line:
			if int(it["act"]) >= 0 and int(it["act"]) < Editor.TOOL_COUNT:
				labels.append(str(it["label"]))
		_check(labels.size() == Editor.TOOL_COUNT, "nastroje se v panelu ztratily: " + str(labels))
		_check(labels[0] == Editor.TOOL_LABELS[Editor.TOOL_ROAD]
			and labels[1] == Editor.TOOL_LABELS[Editor.TOOL_GUMA],
			"prvni skupina nejsou kreslici nastroje: " + str(labels))
		# A DRUHY RADEK JSOU PARAMETRY: typ cesty (mista na bonus uz nejsou).
		var prm: Array = _panel_acts(e, Editor.PANEL_TOOLS)
		for want in [Editor.BTN_ELEM]:
			_check(prm.has(want), "v panelu nastroju chybi parametr %d" % want)
		_check(not prm.has(Editor.BTN_DELETE),
			"panel nastroju nabizi smazani useku - to patri do panelu vyber")
	e.panel = Editor.PANEL_NONE
	for t in range(Editor.TOOL_COUNT):
		e.press(t)
		_check(e.tool == t, "nastroj %d se nevybral (je %d)" % [t, e.tool])
	e.toggle_panel(Editor.PANEL_TOOLS)
	_check(e.panel == Editor.PANEL_TOOLS, "panel nastroju se neotevrel")
	e.toggle_panel(Editor.PANEL_TOOLS)
	_check(e.panel == Editor.PANEL_NONE, "klepnuti na tentýž tab panel nezavrelo")

	# VYBER: obsah zavisi na tom, co je oznacene
	_lane_level(e)
	e.sel_lane = -1
	e.sel_node = -1
	var none_acts: Array = _panel_acts(e, Editor.PANEL_SEL)
	_check(none_acts.has(Editor.BTN_ELEM),
		"bez vyberu panel nevyber nenabizi zivel: " + str(none_acts))
	_check(not none_acts.has(Editor.BTN_DELETE),
		"bez vyberu panel nabizi smazani: " + str(none_acts))
	e.sel_lane = 1
	var lane_acts: Array = _panel_acts(e, Editor.PANEL_SEL)
	_check(lane_acts.has(Editor.BTN_DELETE), "u vybraneho useku chybi smazani")
	e.sel_lane = -1
	e.sel_node = 0
	var node_acts: Array = _panel_acts(e, Editor.PANEL_SEL)
	_check(node_acts.size() == 2 and node_acts.has(Editor.BTN_DELETE),
		"u vybraneho prvku panel nabizi %s" % str(node_acts))
	_check(_panel_label(e, Editor.BTN_KIND).begins_with("druh:"),
		"u prvku tlacitko neukazuje druh: " + _panel_label(e, Editor.BTN_KIND))

	# SMAZANI VYBERU
	e.sel_node = 0
	var nodes0: int = e.level.node_count()
	e.press(Editor.BTN_DELETE)
	_check(e.level.node_count() == nodes0 - 1, "smazani prvku nesmazalo prvek")
	_check(e.sel_node == -1 and e.sel_lane == -1, "po smazani zustal vyber viset")
	e.sel_lane = 1
	var lanes0: int = e.level.lane_count()
	e.press(Editor.BTN_DELETE)
	_check(e.level.lane_count() == lanes0 - 1, "smazani useku nesmazalo usek")

	# HODNOTOVY POPISEK NENI TLACITKO: v panelu "level" musi byt polozky bez
	# akce (hodnoty) a klepnuti na ne nic nedela.
	var values: int = 0
	e.panel = Editor.PANEL_LEVEL
	for row in e.panel_rows():
		for it in row:
			if int(it["act"]) < 0 and str(it["kind"]) == "value":
				values += 1
			_check(str(it["kind"]) != "value" or int(it["act"]) < 0,
				"hodnota v panelu je zaroven tlacitko")
	_check(values == Editor.PARAM_COUNT,
		"v panelu level chybi hodnoty (%d z %d)" % [values, Editor.PARAM_COUNT])

	# KLEPNUTI NA DESKU S OTEVRENYM PANELEM PANEL JEN ZAVRE (a nic nepolozi).
	# game_view se v testu neinstanciuje (je to obrazovka s _draw), takze se
	# hlida PORADI v kodu: zavreni panelu musi byt PRED prací s bunkou -
	# kdyby bylo az za ni, hrac by polozil prvek pod panelem, tedy nekam,
	# co nevidi.
	#
	# VYJIMKA JE VLOZENI KOPIE: dokud hrac vybira, KAM kopii polozi, musi
	# tlacitka panelu zustat na ocich (a vlozeni musi jit vzit zpet) - proto
	# je vetev vlozeni PRED zavrenim panelu.
	var vsrc: String = FileAccess.get_file_as_string("res://scripts/game_view.gd")
	var body: String = _func_body(vsrc, "_handle_editor_tap")
	_check(body.contains("editor.close_panel()"), "klepnuti na desku nezavre panel")
	var iclose: int = body.find("editor.close_panel()")
	var icell: int = body.rfind("_editor_cell(pos)")
	var ipaste: int = body.find("editor.paste_at(")
	_check(ipaste >= 0 and iclose >= 0 and ipaste < iclose,
		"vetev vlozeni kopie neni pred zavrenim panelu - panel by zmizel uprostred vlozeni")
	_check(iclose >= 0 and icell >= 0 and iclose < icell,
		"panel se zavira az po praci s bunkou - hrac by polozil prvek pod panelem")
	# A panel i horni pruh se musi opravdu kreslit: tlacitka, ktera existuji
	# jen v datech, hrac nevidi (presne to se stalo s hlasenim chyb).
	_check(vsrc.contains("_draw_editor_panel()"), "editor nekresli panel")
	_check(vsrc.contains("_draw_editor_top()"), "editor nekresli horni pruh")


func _func_body(src: String, name: String) -> String:
	var i: int = src.find("func " + name)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 5)
	return src.substr(i, (j - i) if j > 0 else src.length() - i)


# PARAMETRY LEVELU: kazdy se meni po svem kroku, drzi meze a jde s nim ven
# i kod levelu. Kdyz hrac klepne na doraz, NESMI se do historie "zpet" zapsat
# krok, ktery nic nemeni.
func _test_level_params() -> void:
	var e := _ed()
	var seen_dirs: Dictionary = {}
	for p in range(Editor.PARAM_COUNT):
		var par: Dictionary = Editor.PARAMS[p]
		var key: String = str(par["key"])
		var up_act: int = Editor.BTN_PARAM_DOWN + p * 2 + 1
		var down_act: int = Editor.BTN_PARAM_DOWN + p * 2
		e.panel = Editor.PANEL_LEVEL
		# NAHORU: hodnota vyroste o krok (a popisek v panelu ji ukaze)
		var before: float = float(e.level.get(key))
		e.press(up_act)
		var after: float = float(e.level.get(key))
		_check(after > before, "%s se po + nezvedl (%s -> %s)" % [key, str(before), str(after)])
		_check(absf(after - (before + float(par["step"]))) < 0.001
			or absf(after - float(par["hi"])) < 0.001,
			"%s se nezmenil o krok (%s -> %s)" % [key, str(before), str(after)])
		var label: String = _panel_label(e, up_act)
		_check(label == "+", "%s: tlacitko + ma popisek %s" % [key, label])
		_check(_panel_label(e, down_act) == "−", "%s: tlacitko - ma popisek %s" % [key, _panel_label(e, down_act)])
		# NAZEV S HODNOTOU je v panelu jako TEXT (ne obdelnik): hrac vidi
		# "kolo 120 s" a vedle jen dve mala tlacitka.
		var value_label: String = _panel_value_label(e, Editor.PANEL_LEVEL, str(par["label"]))
		_check(value_label.begins_with(str(par["label"]) + " "),
			"%s: hodnota v panelu je \"%s\"" % [key, value_label])
		_check(value_label.contains(e._param_text(key)) or value_label.length() > str(par["label"]).length(),
			"%s: hodnota v panelu neukazuje cislo: \"%s\"" % [key, value_label])
		_check(e.status.contains(str(par["label"])), "hlaska nemluvi o %s: %s" % [key, e.status])
		# DOLU: zpatky
		e.press(down_act)
		_check(absf(float(e.level.get(key)) - before) < 0.001,
			"%s se po - nevratil na puvodni hodnotu" % key)
		# DORAZ: doklepat az na horni mez a pak zkusit jeste jednou. Klepnuti,
		# ktere nic nemeni, NESMI zapsat krok do historie "zpet" (jinak by
		# se hrac proklikal krokody, ktere nic nedelaji).
		var guard: int = 0
		while float(e.level.get(key)) < float(par["hi"]) - 0.001 and guard < 500:
			e.press(up_act)
			guard += 1
		_check(is_equal_approx(float(e.level.get(key)), float(par["hi"])),
			"%s nedrzi horni mez (%s)" % [key, str(float(e.level.get(key)))])
		var undo_before: int = e.undo_stack.size()
		e.press(up_act)
		_check(e.undo_stack.size() == undo_before,
			"%s: klepnuti na doraz zapsalo krok do historie" % key)
		_check(e.status.contains("dál to nejde"), "%s: doraz nerekne proc: %s" % [key, e.status])
		seen_dirs[key] = true

	# KOD LEVELU SI HODNOTY ODNESE. Bez toho by hrac nastavil cas kola
	# a level by se mu po exportu vratil jiny. `from_code` vraci null, kdyz
	# mapa neplati, takze se nejdriv postavi platna mapa (START -> VYHYBKA ->
	# dva cile) - parametry se pak meni na ni.
	_lane_level(e)
	var code: String = e.level.to_code()
	var back := Level.from_code(code)
	_check(back != null, "kod s upravenymi parametry se neda nacist")
	if back != null:
		_check(is_equal_approx(back.round_time, e.level.round_time),
			"cas kola se v kodu ztratil (%s vs %s)" % [str(back.round_time), str(e.level.round_time)])
		_check(is_equal_approx(back.speed, e.level.speed), "rychlost se v kodu ztratila")
		_check(back.lives == e.level.lives, "zivoty se v kodu ztratily")
		_check(back.gold == e.level.gold, "zlato se v kodu ztratilo")


# ROZVRZENI PRUHU A PANELU: vsechno se musi vejit na displej, panel musi byt
# NAD pruhem (ne pres nej) a popisky musi zustat citelne. Meri se na 640x360
# (nejmensi podporovany) i na 960x600 - kresleni i test berou stejne cislo
# z rozvrzeni, takze se nemuze stat, ze test meri neco jineho, nez hrac vidi.
# Popisek tlacitka v KONKRETNIM panelu. `_panel_label` vraci prvni vyskyt
# v celem editoru, takze u tlacitka, ktere je ve DVOU panelech (typ cesty),
# by test meril porad jeden z nich.
func _label_in_panel(e: Editor, p: int, act: int) -> String:
	var save: int = e.panel
	e.panel = p
	var out: String = ""
	for row in e.panel_rows():
		for it in row:
			if int(it["act"]) == act:
				out = str(it["label"])
	e.panel = save
	return out


# PANEL SE PREDVYPLNI PODLE VYBERU. Jan: "Pri oznaceni prvku se musi v
# panelu nastroju predvyplnit parametry podle vybraneho prvku. Kdyz kliknu
# na ohnivou cestu se 2 upgrade body, tak se v panelu nastroju vsechny tyto
# udaje predvyplnit."
#
# Testuje se to, co hrac opravdu vidi: popisek tlacitka typu a hodnotovy
# popisek mist v OBOU panelech (nastroje i vyber), ne vnitrni promenna.
# A zaroven ze stisk meni PRESNE ten vybrany usek.
func _test_params_prefill() -> void:
	var e := _ed()
	_lane_level(e)
	# Usek 1 je ohniva vetev; dame ji 2 mista a zvolime JINY kreslici typ,
	# aby se poznalo, ze se panel ridi vyberem, a ne tim, s cim se kresli.
	e.level.set_lane_element(1, Element.FIRE)
	e.level.set_lane_slots(1, 2)
	e.elem = Element.WATER
	e.sel_lane = -1
	e.sel_node = -1
	for p in [Editor.PANEL_TOOLS, Editor.PANEL_SEL]:
		var lab0: String = _label_in_panel(e, p, Editor.BTN_ELEM)
		_check(lab0 == Level.value_name(e.elem),
			"bez vyberu panel %d neukazuje kreslici typ: %s" % [p, lab0])
	# --- oznaceni ohnive cesty se 2 misty
	e.tool = Editor.TOOL_ROAD
	e.begin_draw(e.level.lane_cells(1)[3])
	e.end_draw()
	_check(e.sel_lane == 1, "usek 1 se nevybral (sel %d)" % e.sel_lane)
	for p in [Editor.PANEL_TOOLS, Editor.PANEL_SEL]:
		var lab: String = _label_in_panel(e, p, Editor.BTN_ELEM)
		_check(lab == Level.value_name(Element.FIRE),
			"panel %d nepredvyplnil typ vybraneho useku (%s)" % [p, lab])
		var sl: String = _panel_value_label(e, p, "úsek")
		_check(sl.contains("úsek 1"), "panel %d nemluvi o vybranem useku (%s)" % [p, sl])
	# --- stisk meni VYBRANY usek (a cyklus jde z jeho typu)
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(1) == Element.EARTH,
		"typ vybraneho useku se nezmenil z ohnive (%s)" % e.level.lane_type_name(1))
	# --- druhy usek ma SVOJE hodnoty: panel se preplni znovu
	var other: int = 2
	e.level.set_lane_element(other, Element.WATER)
	e.begin_draw(e.level.lane_cells(other)[3])
	e.end_draw()
	_check(e.sel_lane == other, "druhy usek se nevybral (sel %d)" % e.sel_lane)
	_check(_label_in_panel(e, Editor.PANEL_SEL, Editor.BTN_ELEM) == Level.value_name(Element.WATER),
		"panel se nepreplnil na druhy usek")


func _test_editor_layout() -> void:
	var e := _ed()
	_lane_level(e)
	e.sel_lane = 1
	e.sel_node = -1
	var font := ThemeDB.fallback_font
	for size in [Vector2(640.0, 360.0), Vector2(960.0, 600.0), Vector2(1024.0, 600.0)]:
		var lay := ScreenLayout.new()
		lay.compute(size)
		lay.set_editor_font(font)
		_check(lay.ed_buttons.size() == 7, "%s: pruh nema 7 tlacitek" % str(size))
		for r in lay.ed_buttons:
			var rr: Rect2 = r
			_check(rr.position.x >= -0.5 and rr.end.x <= size.x + 0.5,
				"%s: tlacitko pruhu utika z displeje" % str(size))
			_check(rr.size.y >= ScreenLayout.MIN_TOUCH - 0.5,
				"%s: tlacitko pruhu je nizsi nez prst (%.1f)" % [str(size), rr.size.y])
		var labels: Array = []
		for it in e.bar_entries():
			labels.append(str(it["label"]))
		var lpx: int = lay.ed_label_px(labels, font)
		_check(lpx >= 11, "%s: popisky v pruhu jsou jen %d px" % [str(size), lpx])
		# KAZDY PANEL ZVLAST: musi se vejit, byt nad pruhem a mit citelny popisek
		for p in range(1, Editor.PANEL_COUNT + 1):
			var save: int = e.panel
			e.panel = p
			lay.editor_panel(e.panel_rows())
			e.panel = save
			_check(lay.ed_panel_rows.size() > 0, "%s: panel %d se nerozvrstvil" % [str(size), p])
			_check(lay.ed_panel_top < lay.editor_bar_top() - 1.0,
				"%s: panel %d neni nad pruhem" % [str(size), p])
			var prev_bottom: float = 1.0e9
			var cells: Array = []
			for row in lay.ed_panel_rows:
				var line: Array = row
				var row_top: float = 1.0e9
				var row_cells: Array = []
				for k in range(line.size()):
					var en: Dictionary = line[k]
					var rr: Rect2 = en["rect"]
					_check(rr.position.x >= -0.5 and rr.end.x <= size.x + 0.5,
						"%s: panel %d utika z displeje" % [str(size), p])
					_check(rr.size.y >= ScreenLayout.MIN_TOUCH - 0.5,
						"%s: tlacitko panelu %d je nizsi nez prst" % [str(size), p])
					row_top = minf(row_top, rr.position.y)
					_check(_rects_do_not_overlap(lay.all_editor_buttons(), rr),
						"%s: tlacitka editoru se prekryvaji" % str(size))
					# ZACATKY BUNEK: kazda treti polozka je zacatek bunky
					if p == Editor.PANEL_LEVEL and k % 3 == 0:
						row_cells.append(rr.position.x)
				cells.append(row_cells)
				_check(row_top < prev_bottom, "%s: radky panelu %d se prekryvaji" % [str(size), p])
				prev_bottom = row_top + float(line[0]["rect"].size.y)
				var plpx: int = lay.panel_label_px(line, font)
				_check(plpx >= 11, "%s: popisky panelu %d jsou jen %d px" % [str(size), p, plpx])
			# KOMPAKTNI TLACITKA: v panelu nastroju musi byt uzke tlacitko
			# ("cíl") opravdu uzsi nez siroke ("výhybka") a zadne nesmi
			# spadnout pod dotykove minimum.
			if p == Editor.PANEL_TOOLS:
				var w_cil: float = _tools_btn_w(lay, "cíl")
				var w_vyh: float = _tools_btn_w(lay, "výhybka")
				_check(w_cil > 0.0 and w_vyh > w_cil + 4.0,
					"%s: tlacitka nastroju maji stejnou sirku (cíl %.0f, výhybka %.0f)" % [
						str(size), w_cil, w_vyh])
				for row in lay.ed_panel_rows:
					for en in row:
						if str(en["item"].get("kind", "")) != "tool":
							continue
						_check(float(en["rect"].size.x) >= ScreenLayout.MIN_TOUCH - 0.5,
							"%s: tlacitko nastroje \"%s\" je uzsi nez prst (%.0f px)" % [
								str(size), str(en["item"]["label"]), float(en["rect"].size.x)])
			# SLOUPCE MUSI SEDET: bunky v druhem radku zacinaji na stejnem x
			# jako v prvnim. Kdyz se dorovnani rozbije, hrac vidi usklebene
			# radky - a cisla to nepoznaji, jen oko.
			if cells.size() >= 2:
				for k in range(cells[0].size()):
					_check(absf(float(cells[0][k]) - float(cells[1][k])) < 0.6,
						"%s: sloupce panelu level nesedi (radek 0: %s, radek 1: %s)" % [
							str(size), str(cells[0]), str(cells[1])])


# SIRKA TLACITKA NASTROJE PODLE POPISKU (v otevrenem panelu nastroju).
func _tools_btn_w(lay: ScreenLayout, label: String) -> float:
	for row in lay.ed_panel_rows:
		for en in row:
			if str(en["item"].get("label", "")) == label:
				return float(en["rect"].size.x)
	return 0.0


func _rects_do_not_overlap(all: Array, r: Rect2) -> bool:
	var hits: int = 0
	for other in all:
		var o: Rect2 = other
		if o.intersects(r, false):
			hits += 1
	return hits <= 1


# OBDELNIKOVY VYBER, KOPIE, OTOCENI A VLOZENI.
# Jan: "Přidáme možnost prvky označit hromadně (pomocí obdélníkového tahu),
# případně je zkopírovat (přesně v tom formátu jak jsou, včetně velikosti,
# směru, a všech jiných parametrů) a vložit a otočit (například když chci
# udělat dvě protichůdné zrcadlové trasy)."
#
# Zakladni mapa (_lane_level): START (1,5) -> VYHYBKA (4,5) -> dve cesty do
# cilu (8,2) a (8,8). Usek 1 je horni vetev, jeho bunky jsou
# (4,5)(4,4)(4,3)(4,2)(5,2)(6,2)(7,2)(8,2).
func _test_box_copy() -> void:
	var e := _ed()
	_lane_level(e)
	_check(e.level.lane_count() == 3, "zakladni mapa pro vyber se nepostavila")
	# Do useku 1 dame vlastni hodnoty, aby se poznalo, ze je kopie odnesla.
	e.level.set_lane_element(1, Element.WATER)
	e.level.set_lane_slots(1, 5)

	# --- TAH OBDELNIKEM ---
	e.tool = Editor.TOOL_VYBER
	e.begin_box(Vector2i(4, 2))
	_check(e.has_box(), "zacatek tazeni nezacal obdelnik")
	e.extend_box(Vector2i(8, 5))
	_check(e.sel_box == Rect2i(4, 2, 5, 4),
		"obdelnik ma spatny rozmer: %s" % str(e.sel_box))
	e.end_box()
	_check(e.has_box(), "po pusteni prstu obdelnik zmizel")
	_check(e.box_lanes() == [1], "v obdelniku neni cela horni vetev: %s" % str(e.box_lanes()))
	_check(e.box_nodes().size() == 2,
		"v obdelniku nejsou dva prvky (vyhybka a cil): %s" % str(e.box_nodes()))

	# --- KLEPNUTI (tah bez pohybu) VYBIRA JEDEN PRVEK, NE OBDELNIK ---
	e.begin_box(Vector2i(4, 5))
	e.end_box()
	_check(not e.has_box(), "klepnuti nechalo viset obdelnik")
	_check(e.sel_node >= 0 and not e.has_box(),
		"klepnuti nastrojem vyber nevybralo prvek pod prstem")

	# --- KOPIE ODCHAZI S CELYM FORMATEM ---
	e.begin_box(Vector2i(4, 2))
	e.extend_box(Vector2i(8, 5))
	e.end_box()
	_check(e.copy_box(), "kopie vyberu se nepovedla: %s" % e.status)
	_check(e.clip["lanes"].size() == 1 and e.clip["nodes"].size() == 2,
		"kopie nema jeden usek a dva prvky: %s" % str(e.clip))
	_check(int(e.clip["w"]) == 5 and int(e.clip["h"]) == 4,
		"kopie si nenese velikost vyberu: %dx%d" % [int(e.clip["w"]), int(e.clip["h"])])
	var cl: Dictionary = e.clip["lanes"][0]
	_check(int(cl["elem"]) == Element.WATER,
		"kopie si nenese element useku (je %d)" % int(cl["elem"]))
	_check(int(cl["slots"]) == 5, "kopie si nenese pocet mist (je %d)" % int(cl["slots"]))
	var first: Vector2i = cl["cells"][0]
	_check(first == Vector2i(0, 3),
		"kopie nema bunky relativne k obdelniku: prvni je %s" % str(first))
	_check(cl["cells"].size() == 8, "kopie ma %d bunek misto 8" % cl["cells"].size())

	# --- OTOCENI A ZRCADLENI MENI KOPII (a pocita se to na jednom miste) ---
	e.clip_rot = 1
	_check(e.clip_size() == Vector2i(4, 5),
		"po otoceni o 90 stupnu ma kopie spatny rozmer: %s" % str(e.clip_size()))
	# (0,0) v kopii 5x4 se po otoceni dostane na (h-1, 0) = (3,0)
	_check(e.clip_map(0, 0) == Vector2i(3, 0),
		"otoceni kopie miri spatne: (0,0) -> %s" % str(e.clip_map(0, 0)))
	e.clip_rot = 2
	_check(e.clip_map(0, 3) == Vector2i(4, 0),
		"otoceni o 180 stupnu miri spatne: (0,3) -> %s" % str(e.clip_map(0, 3)))
	e.clip_rot = 0
	e.flip_clip()
	_check(e.clip_flip, "zrcadleni se nepreplo")
	_check(e.clip_map(0, 3) == Vector2i(4, 3),
		"zrcadleni miri spatne: (0,3) -> %s" % str(e.clip_map(0, 3)))

	# --- VLOZENI DO PRAZDNA (zrcadlena vetev) ---
	var lanes0: int = e.level.lane_count()
	var nodes0: int = e.level.node_count()
	_check(e.paste_at(Vector2i(18, 9)), "vlozeni do prazdna se nepovedlo: %s" % e.status)
	_check(e.level.lane_count() == lanes0 + 1, "vlozeni nepridalo usek")
	_check(e.level.node_count() == nodes0 + 2, "vlozeni nepridalo dva prvky")
	var newl: Array = e.level.lane_cells(lanes0)
	_check(newl.size() == 8, "vlozeny usek ma %d bunek misto 8" % newl.size())
	# Zrcadleny usek: puvodni (4,5)->(8,2) se zrcadli vodorovne a posune na
	# (18,9), takze zacina v (22,12) a konci v (18,9).
	_check(newl[0] == Vector2i(22, 12),
		"zrcadleny usek nezacina tam, kde ma: %s" % str(newl[0]))
	_check(newl[newl.size() - 1] == Vector2i(18, 9),
		"zrcadleny usek nekonci tam, kde ma: %s" % str(newl[newl.size() - 1]))
	_check(e.level.lane_element(lanes0) == Element.WATER,
		"vlozeny usek ztratil element")
	_check(e.level.lane_slot_count(lanes0) == 5, "vlozeny usek ztratil pocet mist")
	_check(e.has_box() and e.sel_box == Rect2i(18, 9, 5, 4),
		"po vlozeni neni vybrany vlozeny kus: %s" % str(e.sel_box))
	_check(e.status.begins_with("Vloženo"), "vlozeni nerekne, co udelalo: %s" % e.status)

	# --- VLOZENI SE NESMI POLOZIT PRES CIZI USEK ---
	var lanes1: int = e.level.lane_count()
	_check(not e.paste_at(Vector2i(6, 2)),
		"vlozeni na obsazene misto proslo, i kdyz tam vede usek")
	_check(e.level.lane_count() == lanes1, "odmitnute vlozeni presto zmenilo mapu")
	_check(e.status.contains("už vede jiný úsek"),
		"odmitnute vlozeni nerekne proc: %s" % e.status)

	# --- "ZPET" VEZME VLOZENI ZPATKY ---
	e.undo()
	_check(e.level.lane_count() == lanes1 - 1,
		"zpet nevzalo vlozeni (%d useku)" % e.level.lane_count())

	# --- PRVEK KOPIE NA PRVKU SE SLOUCI (jinak by v bunce byly dva) ---
	# Kopie polozena presne na svuj original: oba jeji prvky (vyhybka i cil)
	# padnou na existujici, takze se SLOUCI - a pouzije se tim stavajici sit.
	e.begin_box(Vector2i(4, 2))
	e.extend_box(Vector2i(8, 5))
	e.end_box()
	e.copy_box()
	e.clip_rot = 0
	e.clip_flip = false
	var nn0: int = e.level.node_count()
	_check(e.paste_at(Vector2i(4, 2)), "vlozeni na stavajici prvek se nepovedlo: %s" % e.status)
	_check(e.level.node_count() == nn0,
		"vlozeni na prvky pridalo dalsi prvky misto slouceni (%d -> %d)" % [nn0, e.level.node_count()])
	_check(e.status.contains("sloučilo"),
		"slouceni prvku se nerekne: %s" % e.status)

	# --- SMAZANI CELÉHO VYBERU ---
	var e2 := _ed()
	_lane_level(e2)
	e2.tool = Editor.TOOL_VYBER
	e2.begin_box(Vector2i(4, 2))
	e2.extend_box(Vector2i(8, 5))
	e2.end_box()
	var l0: int = e2.level.lane_count()
	var n0: int = e2.level.node_count()
	e2.delete_box()
	_check(e2.level.lane_count() == l0 - 1,
		"smazani vyberu nesmazalo usek (%d -> %d)" % [l0, e2.level.lane_count()])
	_check(e2.level.node_count() == n0 - 2,
		"smazani vyberu nesmazalo dva prvky (%d -> %d)" % [n0, e2.level.node_count()])
	_check(not e2.has_box(), "po smazani zustal obdelnik viset")

	# --- PANEL "VYBER" SE MENI PODLE VYBERU ---
	var e3 := _ed()
	_lane_level(e3)
	_check(not _panel_acts(e3, Editor.PANEL_SEL).has(Editor.BTN_COPY),
		"bez obdelniku panel nabizi kopirovani")
	e3.tool = Editor.TOOL_VYBER
	e3.begin_box(Vector2i(4, 2))
	e3.extend_box(Vector2i(8, 5))
	e3.end_box()
	var acts: Array = _panel_acts(e3, Editor.PANEL_SEL)
	_check(acts.has(Editor.BTN_COPY), "u obdelniku chybi kopirovani: %s" % str(acts))
	_check(acts.has(Editor.BTN_DEL_SEL), "u obdelniku chybi smazani vyberu: %s" % str(acts))
	_check(not acts.has(Editor.BTN_ELEM) and not acts.has(Editor.BTN_KIND),
		"u obdelniku panel nabizi jednoprvkove veci: %s" % str(acts))
	e3.copy_box()
	var acts2: Array = _panel_acts(e3, Editor.PANEL_SEL)
	for b in [Editor.BTN_PASTE, Editor.BTN_ROT, Editor.BTN_FLIP]:
		_check(acts2.has(b), "po kopii chybi tlacitko %d: %s" % [b, str(acts2)])
	# A tlacitka opravdu neco delaji (tlacitko, ktere nic nedela, je lez).
	e3.press(Editor.BTN_ROT)
	_check(e3.clip_rot == 1, "tlacitko otoceni neotocilo kopii")
	e3.press(Editor.BTN_FLIP)
	_check(e3.clip_flip, "tlacitko zrcadleni nezrcadlilo kopii")
	e3.press(Editor.BTN_PASTE)
	_check(e3.paste_armed, "tlacitko vlozit nepripravilo vlozeni: %s" % e3.status)
	_check(e3.paste_cell == Vector2i(9, 2) or e3.paste_cell != Vector2i(-1, -1),
		"pripravene vlozeni nema misto")
	var lbefore: int = e3.level.lane_count()
	e3.press(Editor.BTN_PASTE)
	_check(e3.level.lane_count() == lbefore + 1,
		"druhy stisk vlozit nevlozil (useku %d)" % e3.level.lane_count())
	_check(not e3.paste_armed, "po vlozeni zustava vlozeni pripravene")

	# --- NASTROJ "VYBER" JE V PANELU NASTROJU ---
	var e4 := _ed()
	_save_panel(e4, Editor.PANEL_TOOLS)
	var row: Array = e4.panel_rows()[0]
	var labels: Array = []
	for it in row:
		if int(it["act"]) >= 0:
			labels.append(str(it["label"]))
	_check(labels.size() == Editor.TOOL_COUNT,
		"panel nastroju nema vsech %d nastroju: %s" % [Editor.TOOL_COUNT, str(labels)])
	_check(labels.has(Editor.TOOL_LABELS[Editor.TOOL_VYBER]),
		"v panelu nastroju chybi vyber: %s" % str(labels))
	# "VÝBĚR" JE NASTROJ, KTERYM SE VYBIRA A UPRAVUJE. Jan (Oct 2026): "Tah
	# prstem teď dělá rectangle select. Chtěl bych vybrat jednu cestu a
	# upravit ji." Driv tah vyberem znamenal VZDY obdelnik, takze cestu nešlo
	# tvarovat - dnes se obdelnik obtahne jen z prazdneho mista.
	e4.tool = Editor.TOOL_VYBER
	_check(e4.can_move(), "nastrojem vyber se neda upravovat uzel")
	e4.panel = Editor.PANEL_NONE


# CHYTANI CESTY PRSTEM JE DOSTUPNE I NASTROJI "CESTA" A "VYBER".
# Jan (Oct 2026): "Stále nám nefunguje upravování cest pomocí tahu prstem. Tah
# prstem teď dělá rectangle select. Chtěl bych vybrat jednu cestu a upravit ji."
#
# Driv se cesta dala chytit JEN nastrojem z palety (start/cíl/výhybka/spojka/
# uzel): na "ceste" se taháním kreslilo a na "vyberu" obtahoval obdelnik, takze
# hrac cestu upravit NEMOHL - a presne to Jan psal. Test to hlida z obou stran:
# cesta se chyti vsude, kde tah nic jineho znamenat nema, a nechyti se tam, kde
# tah znamena neco jineho (uzel, prazdne misto, guma).
func _test_lane_grab_tools() -> void:
	var e := _ed()
	var lv := Level.new()
	var s: int = lv.add_node(2, 5, Level.START)
	var c: int = lv.add_node(6, 5, Level.CIL)
	lv.add_lane(s, c, "RRRR", Element.FIRE)
	e.level = lv
	# 1) NASTROJ "CESTA": prst na ceste chyti CESTSAMU - kreslit by tam stejne
	#    neslo, protoze nova cesta musi zacit v uzlu.
	e.tool = Editor.TOOL_ROAD
	_check(e.begin_lane_drag(Vector2i(4, 5)),
		"na ceste se nastrojem \"cesta\" neda chytit usek")
	_check(e.moving and e.drag_lane == 0,
		"chycena cesta neni oznacena jako tazena (moving=%s, lane=%d)" % [str(e.moving), e.drag_lane])
	e.end_move()
	# 2) NASTROJ "VYBER": tah za konec cestu PRODLOUZI (a neobtahne obdelnik)
	e.tool = Editor.TOOL_VYBER
	var was: int = e.level.lane_cells(0).size()
	_check(e.begin_lane_drag(Vector2i(5, 5)), "nastrojem vyber se cesta neda chytit")
	_check(e.drag_end == 1, "u konce cesty se nechytil konec (drag_end=%d)" % e.drag_end)
	e.extend_move(Vector2i(7, 5))
	e.end_move()
	var now: int = e.level.lane_cells(0).size()
	_check(now == was + 1, "tahem za konec se cesta neprodouzila (%d -> %d)" % [was, now])
	# 3) KLEPNUTI (tah bez pohybu) nastrojem "vyber" jen VYBERE: neobtahne
	#    obdelnik a nepolovi cestu prvkem
	var lanes: int = e.level.lane_count()
	_check(e.begin_lane_drag(Vector2i(4, 5)), "cesta se neda chytit")
	e.end_move()
	_check(e.sel_lane == 0, "klepnuti na cestu ji nevybralo (sel_lane=%d)" % e.sel_lane)
	_check(not e.box_active, "klepnuti na cestu spustilo obdelnikovy vyber")
	_check(e.level.lane_count() == lanes, "klepnuti na cestu ji rozdelilo")
	# 4) PRAZDNE MISTO: obdelnik se porad da obtáhnout - tah z prazdna mista
	#    cestu nechyti
	e.sel_lane = -1
	_check(not e.begin_lane_drag(Vector2i(4, 9)), "prazdne misto se chytilo jako cesta")
	e.begin_box(Vector2i(2, 4))
	e.extend_box(Vector2i(9, 6))
	e.end_box()
	_check(e.box_lanes().size() >= 1, "obdelnik obtazeny z prazdna mista nic nevybral")
	e.sel_box = Rect2i(0, 0, 0, 0)
	# 5) UZEL: klepnuti na uzel musi zustat uzel - kresli se z nej nova cesta
	#    a paleta na nem klade prvek. Uzel se v kroku 2 posunul, tak se bere
	#    JEHO skutecna bunka (test si ji nesmi pamatovat z minula).
	_check(not e.begin_lane_drag(e.level.node_cell(c)),
		"uzel na %s se chytil jako cesta" % str(e.level.node_cell(c)))
	_check(not e.begin_lane_drag(e.level.node_cell(s)),
		"start na %s se chytil jako cesta" % str(e.level.node_cell(s)))
	# 6) GUMA: tahem se maze, ne tvaruje
	e.tool = Editor.TOOL_GUMA
	_check(not e.begin_lane_drag(Vector2i(4, 5)), "gumou se cesta chytila misto mazani")
	# 7) V game_view musi byt chytani cesty PRED vetvi "cesta kresli" - jinak by
	#    kresleni vyhralo a cesta by se nikdy nechytila.
	var vsrc: String = FileAccess.get_file_as_string("res://scripts/game_view.gd")
	var body: String = _func_body(vsrc, "_handle_editor_tap")
	var grab_at: int = body.find("begin_lane_drag")
	var draw_at: int = body.find("editor.begin_draw(cell)")
	_check(grab_at >= 0 and draw_at >= 0 and grab_at < draw_at,
		"game_view zkousi chytnuti cesty az po kresleni (%d vs %d)" % [grab_at, draw_at])
	# 8) Hrac se to musi DOZVEDIT: u vybraneho useku to stoji v hornim pruhu
	e.tool = Editor.TOOL_VYBER
	e.sel_lane = 0
	e.sel_node = -1
	var txt: String = e.sel_text()
	_check(txt.contains("tažením prstem"),
		"pruh u vybraneho useku nerika, ze se da tvarovat prstem: " + txt)


# VYSTUPEK SE POSOUVA TAHEM PRSTEM (Jan, Oct 2026): "chytnu prstem horní část
# obdélníku, potáhnu nahoru, a celá tato část se posune nahoru, přičemž boční
# strany se automaticky natáhnou."
#
# Tohle je jina operace nez "ohnutí kusu" (`_test_lane_finger`): tam se do rovne
# cesty vybouleni vlozi, tady se cely rovny kus posune a strany se natahnou.
func _test_bump_shift() -> void:
	var e := _ed()
	var lv := Level.new()
	var s: int = lv.add_node(2, 5, Level.START)
	var c: int = lv.add_node(7, 5, Level.CIL)
	lv.add_lane(s, c, "RRURDRR", Element.FIRE)
	e.level = lv
	e.tool = Editor.TOOL_VYBER
	var before: Array = e.level.lane_cells(0).duplicate()
	var was: int = before.size()
	# 1) PRST NA VRSEK VYSTUPKU: chyta se KUS (posun do strany), ne ohnuti
	_check(e.begin_move(Vector2i(4, 4)), "vystupek se neda chytit prstem")
	_check(e.drag_p == Vector2i(0, -1), "chyceny kus nema smer posunu (%s)" % str(e.drag_p))
	_check(e.drag_run_cell == Vector2i(4, 4), "chyta se jina bunka nez ta pod prstem")
	# 2) TAH NAHORU: cely vrsek se posune, obe bocni strany se prodlouzi
	e.extend_move(Vector2i(4, 3))
	var cs: Array = e.level.lane_cells(0)
	_check(cs.size() == was + 2, "tah vystupek neposunul (%d -> %d)" % [was, cs.size()])
	_check(cs.has(Vector2i(4, 3)) and cs.has(Vector2i(5, 3)),
		"vrsek neni o bunku vys: " + str(cs))
	var want: Array = [Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(4, 4),
		Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5),
		Vector2i(6, 5), Vector2i(7, 5)]
	_check(cs.size() == want.size(), "tvar vystupku ma %d bunek, ma mit %d: %s" % [
		cs.size(), want.size(), str(cs)])
	for i in range(mini(cs.size(), want.size())):
		_check(cs[i] == want[i], "tvar vystupku nesedi v bunce %d: %s vs %s" % [
			i, str(cs[i]), str(want[i])])
	# 3) TAH O DVE BUNKY: krok se nesmi preskocit, strany maji tri bunky
	e.extend_move(Vector2i(4, 2))
	_check(e.level.lane_cells(0).size() == was + 4, "druhy krok tahu vystupek neposunul")
	# Chycena bunka zustava puvodni - kazda poloha tahu se stavi ZNOVU z ni.
	_check(e.drag_run_cell == Vector2i(4, 4), "chycena bunka se posunula (%s)" % str(e.drag_run_cell))
	# 4) TAH ZPET DOLU: krok za krokem presne na puvodni cestu
	e.extend_move(Vector2i(4, 3))
	e.extend_move(Vector2i(4, 4))
	var back: Array = e.level.lane_cells(0)
	_check(back.size() == was, "tah zpet nedal puvodni delku (%d vs %d)" % [back.size(), was])
	for i in range(mini(back.size(), was)):
		_check(back[i] == before[i], "tah zpet nedal puvodni cestu (bunka %d)" % i)
	e.end_move()
	# 5) CELY TAH JE JEDNA POLOZKA "ZPET" (ne jedna za kazdou bunku)
	e.extend_move(Vector2i(4, 3))
	e.end_move()
	_check(e.undo_stack.size() == 1, "tah prstem neni jedna polozka zpet (%d)" % e.undo_stack.size())
	e.undo()
	_check(e.level.lane_cells(0).size() == was, "zpet nevratil puvodni cestu")
	# 6) KLEPNUTI NA VRSEK (tah bez pohybu) jen VYBERE usek
	e.sel_lane = -1
	e.sel_node = -1
	_check(e.begin_move(Vector2i(4, 4)), "vrsek se neda chytit")
	e.end_move()
	_check(e.sel_lane == 0, "klepnuti na vrsek nevybralo usek (%d)" % e.sel_lane)
	_check(not e.box_active, "klepnuti na vrsek spustilo obdelnikovy vyber")
	# 7) ZMENŠOVÁNÍ: tah opacnym smerem vystupek SNIZI (az do zplosteni) a tah
	#    zpet ho znovu zvedne. Kazda poloha prstu se stavi z puvodni cesty,
	#    takze se pri tom nic neztrati.
	_check(e.begin_move(Vector2i(4, 4)), "vrsek se neda chytit")
	e.extend_move(Vector2i(4, 5))
	e.extend_move(Vector2i(4, 6))
	var flat: Array = e.level.lane_cells(0)
	_check(flat.size() == was - 2,
		"zmenšování nezplostilo vystupek (%d vs %d)" % [flat.size(), was - 2])
	_check(not flat.has(Vector2i(4, 4)) and not flat.has(Vector2i(5, 4)),
		"po zplosteni zustal vystupek v ceste: " + str(flat))
	e.extend_move(Vector2i(4, 3))
	e.extend_move(Vector2i(4, 2))
	_check(e.level.lane_cells(0).size() == was + 4,
		"tah ven po zplosteni vystupek nezvedl (%d)" % e.level.lane_cells(0).size())
	e.extend_move(Vector2i(4, 4))
	e.end_move()
	var back2: Array = e.level.lane_cells(0)
	_check(back2.size() == was, "po tahu zpet neni puvodni delka (%d vs %d)" % [back2.size(), was])
	for i in range(mini(back2.size(), was)):
		_check(back2[i] == before[i], "po tahu zpet neni puvodni cesta (bunka %d: %s vs %s)" % [
			i, str(back2[i]), str(before[i])])
	# 8) ROZŠÍŘENÍ VRŠKU: tah PODEL vrsku (doprava) vrsek o bunku prodlouzi a
	#    roh se posune s nim; tah zpet vrati presne puvodni cestu
	_check(e.begin_move(Vector2i(4, 4)), "vrsek se neda chytit")
	e.extend_move(Vector2i(5, 4))
	var wide: Array = e.level.lane_cells(0)
	_check(wide.size() == was,
		"rozsireni vrsku zmenilo pocet bunek (%d vs %d)" % [wide.size(), was])
	_check(wide.has(Vector2i(6, 4)) and not wide.has(Vector2i(5, 5)),
		"vrsek se nerozsiril doprava: " + str(wide))
	e.extend_move(Vector2i(6, 4))
	_check(e.level.lane_cells(0).has(Vector2i(7, 4)), "druhy krok rozsireni neprosel")
	e.extend_move(Vector2i(4, 4))
	var back3: Array = e.level.lane_cells(0)
	_check(back3.size() == was, "tah zpet po rozsireni nedal puvodni delku (%d)" % back3.size())
	for i in range(mini(back3.size(), was)):
		_check(back3[i] == before[i], "tah zpet po rozsireni nedal puvodni cestu (bunka %d)" % i)
	e.end_move()


# MALA TLACITKA "−"/"+" NALEPENA NA HODNOTU + VIDITELNA MRIZKA.
# Jan: (1) "Tlačítka + a - jsou zbytečně velká. Tato tlačítka by měla být malá
# a ideálně přímo nalepená na hodnotu, kterou ovládají."
#       (2) "Mřížku uděláme viditelnější."
#
# Meri se z ROZVRZENI, ktere dostane i kresleni - kdyby si test pocital svoje
# cisla, mohl by projit na necem, co hrac nevidi.
func _test_steppers_and_grid() -> void:
	var e := _ed()
	_lane_level(e)
	var font := ThemeDB.fallback_font
	for size in [Vector2(640.0, 360.0), Vector2(960.0, 600.0)]:
		var lay := ScreenLayout.new()
		lay.compute(size)
		lay.set_editor_font(font)
		# Krokovaci "−"/"+" ma jen panel "level" (kolo, rychlost, zivoty,
		# zlato). Panel "vyber" uz zadny nema - mista na bonus z nej zmizela;
		# test se proto pta na KAZDY panel, kolik dvojic v nem opravdu je,
		# a rovnou to overi (panel bez dvojice je povolen, kdyz nema co
		# krokovat).
		for p in [Editor.PANEL_LEVEL, Editor.PANEL_SEL, Editor.PANEL_TOOLS]:
			e.panel = p
			e.sel_lane = 0
			lay.editor_panel(e.panel_rows())
			var items: Array = _panel_items(lay)
			var pairs: int = 0
			for i in range(1, items.size() - 1):
				var minus: Dictionary = items[i]
				if str(minus["item"].get("label", "")) != "−":
					continue
				var val: Dictionary = items[i - 1]
				var plus: Dictionary = items[i + 1]
				pairs += 1
				var w: float = float(minus["rect"].size.x)
				var step_px: float = Editor.STEP_W * lay.ui
				_check(absf(w - step_px) < 0.6,
					"%s panel %d: tlacitko - ma %.1f px, ma mit %.1f" % [str(size), p, w, step_px])
				_check(w >= ScreenLayout.MIN_TOUCH * lay.ui - 0.6,
					"%s panel %d: tlacitko - je pod dotykovym minimem" % [str(size), p])
				_check(w < float(val["rect"].size.x),
					"%s panel %d: tlacitko - neni mensi nez hodnota (%.1f vs %.1f)" % [
						str(size), p, w, float(val["rect"].size.x)])
				# NALEPENE: hodnota konci presne tam, kde - zacina, a + stoji
				# na konci -.
				_check(absf(float(minus["rect"].position.x) - float(val["rect"].end.x)) < 0.6,
					"%s panel %d: - neni nalepene na hodnotu" % [str(size), p])
				_check(absf(float(plus["rect"].position.x) - float(minus["rect"].end.x)) < 0.6,
					"%s panel %d: + neni nalepene na -" % [str(size), p])
				_check(str(val["item"].get("kind", "")) == "value"
					and str(val["item"].get("align", "")) == "right",
					"%s panel %d: hodnota pred - neni text u praveho okraje" % [str(size), p])
				_check(str(plus["item"].get("label", "")) == "+",
					"%s panel %d: za - neni +" % [str(size), p])
			# Panel "level" ma dvojici u kazdeho parametru; ostatni zadnou.
			# Kdyby se nasla nula v "level", test by meril prazdno.
			var want: int = Editor.PARAM_COUNT if p == Editor.PANEL_LEVEL else 0
			_check(pairs == want,
				"%s panel %d: naslo se %d dvojic -/+ (ceka se %d)" % [str(size), p, pairs, want])
	e.panel = Editor.PANEL_NONE

	# MRIZKA JE VIDET: barvy jsou v `Level` (ne v kresleni), takze se na ne
	# test muze zeptat. Podklad desky je luminancne ~0.115 - cara mrizky musi
	# byt VYRAZNE svetlejsi, jinak v ruce neni videt vubec.
	var bg_lum: float = Color(0.125, 0.115, 0.10).get_luminance()
	_check(Level.GRID_LINE.get_luminance() > 2.0 * bg_lum,
		"cara mrizky je jen %.3f proti podkladu %.3f" % [
			Level.GRID_LINE.get_luminance(), bg_lum])
	_check(Level.GRID_MAJOR.get_luminance() > Level.GRID_LINE.get_luminance(),
		"kazda ctvrta cara mrizky neni vyraznejsi")
	_check(Level.GRID_STEP == 4, "rytmus mrizky se zmenil (%d)" % Level.GRID_STEP)
	var gsrc: String = FileAccess.get_file_as_string("res://scripts/game_view.gd")
	_check(gsrc.contains("Level.GRID_LINE") and gsrc.contains("Level.GRID_MAJOR"),
		"mrizka nekresli barvami z Level")
	_check(gsrc.contains("Level.GRID_STEP"), "mrizka nekresli kazdou ctvrtou caru vyrazneji")
	_check(not gsrc.contains("Color(0.20, 0.185, 0.165"),
		"v kresleni zustala stara (neviditelna) barva mrizky")


# POLOZKY ROZVRZENEHO PANELU (kresleni i klepnuti jdou pres ne).
func _panel_items(lay: ScreenLayout) -> Array:
	var out: Array = []
	for row in lay.ed_panel_rows:
		for en in row:
			out.append(en)
	return out


# SEZNAM ULOZENYCH LEVELU. Hlida se hlavne to, ze "novy" NEPREPISE predchozi
# praci - to je jedina vec, ktera se neda vzit zpet.
func _test_list() -> void:
	_wipe_levels()
	var a := Editor.new()
	a.reset()
	a.tool = Editor.TOOL_START
	a.tap_cell(Vector2i(1, 5))
	a.tool = Editor.TOOL_CIL
	a.tap_cell(Vector2i(5, 5))
	_stroke(a, [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)])
	_check(a.level.lane_count() == 1, "prvni level se nepostavil")
	var first: String = a.local_name
	_check(first != "", "level nema jmeno")

	var b := Editor.new()
	b.reset()
	_check(b.local_name != first, "novy level dostal stejne jmeno jako predchozi")
	b.tool = Editor.TOOL_START
	b.tap_cell(Vector2i(2, 2))
	b.tool = Editor.TOOL_CIL
	b.tap_cell(Vector2i(6, 2))
	_stroke(b, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2)])
	_check(b.level.lane_count() == 1, "druhy level se nepostavil")

	b.open_list()
	_check(b.is_list(), "seznam se neotevrel")
	var items: Array = b.list_items()
	_check(items.size() == 4, "seznam ma %d radku, cekaji se 4" % items.size())
	_check(str(items[0]["kind"]) == "new", "prvni radek neni novy level")
	_check(str(items[items.size() - 1]["kind"]) == "back", "posledni radek neni navrat")

	# NAVRAT PRVNIHO LEVELU: jeho prace musi byt cela. Presne kvuli tomuhle
	# se kazdy level uklada pod svym jmenem.
	var c := Editor.new()
	_check(c.level.load_from_disk(first), "prvni level se neda nacist zpatky")
	_check(c.level.lane_count() == 1,
		"po nacteni ma prvni level %d useku" % c.level.lane_count())
	_wipe_levels()
