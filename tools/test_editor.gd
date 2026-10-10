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
	_run("mista na useku", _test_slot_edit)
	_run("presouvani uzlu", _test_move_node)
	_run("export", _test_export)
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
	_check(e.level.lane_element(0) == Element.FIRE, "cesta nema zvoleny zivel")
	_check(e.level.lane_is_entry(0), "usek ze startu neni vstupni")
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
	# tlacitko zivlu cykluje pres vsechny ctyri
	var seen: Array = []
	for i in range(Element.COUNT):
		seen.append(e.elem)
		e.press(Editor.BTN_ELEM)
	_check(seen.size() == Element.COUNT, "cyklus zivlu neprosel")
	_check(e.elem == seen[0], "cyklus zivlu se nevratil na zacatek")
	_check(e.button_labels().size() == Editor.BTN_COUNT, "pruh nema %d tlacitek"
		% Editor.BTN_COUNT)
	_check(e.button_labels()[Editor.BTN_ELEM] == Element.name_of(e.elem),
		"tlacitko zivlu neukazuje zvoleny zivel")


# UPRAVA JIZ EXISTUJICIHO USEKU. Klepnuti na caru useku (nastrojem cesta) ho
# VYbere a tlacitka "zivel" a "mista" pak meni JEHO vlastnosti. Presne to
# Janovi chybelo: "upravovat jiz existujici zatim nejde".
func _test_edit_existing() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(7, 5))
	e.tool = Editor.TOOL_ROAD
	e.draw_elem = Element.FIRE
	e.begin_draw(Vector2i(1, 5))
	e.extend_draw(Vector2i(7, 5))
	e.end_draw()
	_check(e.level.lane_count() == 1, "cesta se nepridala")
	_check(e.level.lane_element(0) == Element.FIRE, "nova cesta nema ohen")
	_check(e.sel_lane == 0, "nova cesta se nevybrala (sel_lane %d)" % e.sel_lane)

	# klepnuti na caru useku = vyber (a nic se nekresli)
	e.sel_lane = -1
	e.begin_draw(Vector2i(4, 5))
	e.end_draw()
	_check(e.level.lane_count() == 1, "klepnuti na usek neco nakreslilo")
	_check(e.sel_lane == 0, "klepnuti na caru useku ho nevybralo")
	_check(e.status.contains("Vybran"), "status nemluvi o vyberu: " + e.status)

	# zivel se zmeni NA VYBRANEM useku a rovnou se s nim i kresli dal
	e.elem = Element.FIRE
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(0) == Element.WATER,
		"zivel vybraneho useku se nezmenil (je %s)" % Element.name_of(e.level.lane_element(0)))
	_check(e.elem == Element.WATER, "kreslici zivel se neshoduje s usekem")
	# druhy stisk posune dal - uprava je opakovatelna
	e.press(Editor.BTN_ELEM)
	_check(e.level.lane_element(0) == Element.EARTH, "druha zmena zivlu neprosla")

	# rozdelovani useku si pocet mist odnesе do OBOU dilu
	e.tool = Editor.TOOL_UZEL
	e.tap_cell(Vector2i(4, 5))
	_check(e.level.lane_count() == 2, "usek se nerozdelil")
	if e.level.lane_count() == 2:
		_check(e.level.lane_slot_count(0) == Level.SLOTS
			and e.level.lane_slot_count(1) == Level.SLOTS,
			"po rozdeleni prisel jeden dil o mista")


func _test_slot_edit() -> void:
	var e := _ed()
	e.tool = Editor.TOOL_START
	e.tap_cell(Vector2i(1, 5))
	e.tool = Editor.TOOL_CIL
	e.tap_cell(Vector2i(7, 5))
	e.tool = Editor.TOOL_ROAD
	e.begin_draw(Vector2i(1, 5))
	e.extend_draw(Vector2i(7, 5))
	e.end_draw()
	_check(e.sel_lane == 0, "usek se nevybral")
	# bez vyberu se meni, s kolika misty se kresli dalsi cesta
	e.sel_lane = -1
	var n0: int = e.draw_slots
	e.press(Editor.BTN_SLOTS)
	_check(e.draw_slots == (n0 + 1) % (Level.MAX_SLOTS + 1),
		"pocet mist pro nove cesty se nezmenil")
	_check(e.button_labels()[Editor.BTN_SLOTS] == "místa %d" % e.draw_slots,
		"tlacitko neukazuje pocet mist: " + e.button_labels()[Editor.BTN_SLOTS])
	# s vyberem se meni pocet mist TOHO useku, az na nulu a pak dokola
	e.sel_lane = 0
	var seen: Dictionary = {}
	for i in range(Level.MAX_SLOTS + 2):
		var cur: int = e.level.lane_slot_count(0)
		seen[cur] = true
		e.press(Editor.BTN_SLOTS)
		_check(e.level.lane_slot_count(0) == (cur + 1) % (Level.MAX_SLOTS + 1),
			"pocet mist na vybranem useku se nezmenil z %d" % cur)
		_check(e.button_labels()[Editor.BTN_SLOTS] == "místa %d" % e.level.lane_slot_count(0),
			"tlacitko nelze o poctu mist na useku")
	_check(seen.has(0), "na useku se nikdy nepodarilo udelat nula mist")
	_check(seen.size() == Level.MAX_SLOTS + 1, "cyklus neprosel vsechny pocty mist")
	# pocet mist musi prezit ulozeni a nacteni
	var code: String = e.level.to_code()
	var back := Level.from_code(code)
	_check(back != null, "kod s upravenym poctem mist se neda nacist")
	if back != null:
		_check(back.lane_slot_count(0) == e.level.lane_slot_count(0),
			"po nacteni ma usek jiny pocet mist")


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
