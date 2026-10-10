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
