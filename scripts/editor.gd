class_name Editor
extends RefCounted

# EDITOR KRESLI MAPU RUKOU. Zadne "pridej usek", zadne automaticke umistovani
# - to je cely smysl teto verze.
#
#   * TAZENIM PRSTU se kresli cesta. Prst jde po bunkach mrizky, cesta se
#     lame v 90 stupnich a muze se stacet zpet, jak hrac chce. Pusteni
#     prstu ji uzavre.
#   * KLEPNUTIM se polozi prvek z palety: start, cil, vyhybka, spojka, uzel.
#     Prvek se objevi PRESNE tam, kam hrac klikl.
#   * UZEL polozeny DOPROSTRED cesty ji ROZDELI na dva useky. Takhle si hrac
#     dela uzly, kde chce - ne tri, ktere by mu urcil program.
#   * GUMA maze uzel (klepnuti na uzel) nebo cely usek (klepnuti na cestu).
#
# Cesta musi zacit i skoncit v uzlu. Neni to buzerace: bez toho by graf
# nevedel, kudy poutnik po dokresleni pujde dal. Hrac to udela tak, ze
# nejdriv polozi START a pak kresli.

enum { TOOL_ROAD, TOOL_START, TOOL_CIL, TOOL_VYHYBKA, TOOL_SPOJKA, TOOL_UZEL, TOOL_GUMA }

const TOOL_LABELS := ["cesta", "start", "cíl", "výhybka", "spojka", "uzel", "guma"]
const TOOL_COUNT := 7

# Tlacitka za nastroji.
const BTN_ELEM := TOOL_COUNT
const BTN_NEW := TOOL_COUNT + 1
const BTN_EXPORT := TOOL_COUNT + 2
const BTN_PLAY := TOOL_COUNT + 3
const BTN_COUNT := TOOL_COUNT + 4

const TOOL_KINDS := [Level.NEUTRAL, Level.START, Level.CIL, Level.VYHYBKA,
	Level.SPOJKA, Level.UZEL, Level.NEUTRAL]

var level: Level = null
var tool: int = TOOL_ROAD
var elem: int = Element.FIRE
var status: String = ""
var code: String = ""
var local_name: String = "vlastni"

# Prubeh tahnuti prstem. `draw_cells` je to, co hrac prave nakreslil, a
# kresli se to zive - dokud prst nezvedne, neni to soucast levelu.
var drawing: bool = false
var draw_cells: Array = []
var draw_elem: int = Level.NEUTRAL

# Kde hrac naposledy klikl. Kresli se zvyraznene, aby bylo videt, kam to
# padlo - bez toho by si hrac u posledniho prvku nikdy nebyl jisty.
var mark: Vector2i = Vector2i(-1, -1)


func _init() -> void:
	level = Level.new()
	level.name = "vlastni"


# =========================================================================
# ZAKLAD
# =========================================================================

func reset() -> void:
	level = Level.new()
	level.name = local_name
	tool = TOOL_ROAD
	status = "Prázdná mřížka. Polož START a pak tažením prstu kresli cesty."
	code = ""
	drawing = false
	draw_cells = []
	mark = Vector2i(-1, -1)
	level.save()


func open_last() -> void:
	if level.load_from_disk(local_name):
		status = "Načteno: %s" % level.name
	else:
		reset()


func button_labels() -> Array:
	var out: Array = []
	for t in TOOL_LABELS:
		out.append(t)
	out.append(Element.name_of(elem))
	out.append("nový")
	out.append("export")
	out.append("hrát")
	return out


# Je to tlačítko "hrát"? Pruh se kresli z jednoho seznamu a tohle je jedine
# misto, kde se rozhoduje, co se stane po klepnuti.
func is_play(button: int) -> bool:
	return button == BTN_PLAY


func sel_text() -> String:
	return "úseků %d · uzlů %d" % [level.lane_count(), level.node_count()]


# =========================================================================
# KRESLENI PRSTEM
# =========================================================================

func begin_draw(cell: Vector2i) -> void:
	if not level.in_bounds(cell.x, cell.y):
		return
	drawing = true
	draw_cells = [cell]
	draw_elem = elem if tool == TOOL_ROAD else Level.NEUTRAL


# KAZDA BU NKA SE PRIPOJI TAK, ZE SE K PREDCHOZI PRIDA JEN SOUSED.
# Kdyz hrac taha rychle pres vic bunek, doplni se i preskocene - prst
# neni mys a po mrizce klouze. Diky tomu se cesta nikdy neroztrhne.
func extend_draw(cell: Vector2i) -> void:
	if not drawing:
		return
	if not level.in_bounds(cell.x, cell.y):
		return
	while true:
		var last: Vector2i = draw_cells[draw_cells.size() - 1]
		if last == cell:
			return
		var dx: int = cell.x - last.x
		var dy: int = cell.y - last.y
		if dx == 0 and dy == 0:
			return
		# Uz tam ta bunka je? Pak se hrac vratil po vlastni ceste - koncime,
		# jinak by se cesta zacala motat do smycky.
		for c in draw_cells:
			var v: Vector2i = c
			if v == cell:
				return
		var step: Vector2i = last
		if absi(dx) >= absi(dy):
			step = Vector2i(last.x + (1 if dx > 0 else -1), last.y)
		else:
			step = Vector2i(last.x, last.y + (1 if dy > 0 else -1))
		draw_cells.append(step)


func end_draw() -> void:
	if not drawing:
		return
	drawing = false
	var cs: Array = draw_cells
	draw_cells = []
	if cs.size() < 2:
		status = "Cesta je krátká — nakresli aspoň dvě buňky."
		return
	var a: int = level.node_at_cell(cs[0])
	var b: int = level.node_at_cell(cs[cs.size() - 1])
	if a < 0 or b < 0:
		status = "Cesta musí začínat i končit v uzlu (start, výhybka, spojka, uzel)."
		return
	level.lanes.append({"cells": cs, "elem": draw_elem, "entry": false})
	_after_change()
	if draw_elem == Level.NEUTRAL:
		status = "Úsek %d je neutrální — nedá se na něm stavět." % level.lane_count()
	else:
		status = "Úsek %d (%s) přidán." % [level.lane_count(), Element.name_of(draw_elem)]


# =========================================================================
# KLEPNUTI
# =========================================================================

func tap_cell(cell: Vector2i) -> void:
	if not level.in_bounds(cell.x, cell.y):
		return
	mark = cell
	match tool:
		TOOL_ROAD:
			status = "Tažením prstu kresli cestu. Konec musí být v uzlu."
		TOOL_GUMA:
			_erase(cell)
		_:
			_place_node(cell, TOOL_KINDS[tool])


func _place_node(cell: Vector2i, kind: int) -> void:
	if kind == Level.NEUTRAL:
		return
	var existing: int = level.node_at_cell(cell)
	if existing >= 0:
		level.nodes[existing]["kind"] = kind
		_after_change()
		status = "Uzel na %d,%d je teď %s." % [cell.x, cell.y, level.kind_name(kind)]
		return
	# UPROSTRED CESTY: cesta se tam ROZDELI. Kdyby se nerozdělila, uzel by
	# ležel na úseku a ten by neměl v uzlu ani začátek, ani konec - graf by
	# se rozbil.
	var at: int = lane_through(cell)
	if at >= 0:
		_split_lane(at, cell)
	level.nodes.append({"c": cell.x, "r": cell.y, "kind": kind})
	_after_change()
	status = "%s položen na %d,%d." % [level.kind_name(kind), cell.x, cell.y]


func _erase(cell: Vector2i) -> void:
	var n: int = level.node_at_cell(cell)
	if n >= 0:
		level.nodes.remove_at(n)
		_after_change()
		status = "Uzel smazán."
		return
	var l: int = lane_through(cell)
	if l >= 0:
		level.lanes.remove_at(l)
		_after_change()
		status = "Úsek smazán."
		return
	status = "Tady nic není."


# =========================================================================
# HLEDANI V LEVELU
# =========================================================================

# Ktera cesta prochazi touhle bunkou? -1 kdyz zadna.
func lane_through(cell: Vector2i) -> int:
	for i in range(level.lane_count()):
		for c in level.lane_cells(i):
			var v: Vector2i = c
			if v == cell:
				return i
	return -1


# Rozdel cestu v bunce na dve. Vznikne tim misto pro novy uzel - presne to
# Jan chtel ("jednotlivé cesty budu moci dělit na libovolný počet uzlů").
func _split_lane(lane: int, cell: Vector2i) -> void:
	var cs: Array = level.lane_cells(lane)
	var idx: int = -1
	for i in range(cs.size()):
		var c: Vector2i = cs[i]
		if c == cell:
			idx = i
			break
	# Krajni bunka uz je v uzlu - tam se nic delit nemusi.
	if idx <= 0 or idx >= cs.size() - 1:
		return
	var left: Array = []
	for i in range(idx + 1):
		left.append(cs[i])
	var right: Array = []
	for i in range(idx, cs.size()):
		right.append(cs[i])
	var el: int = int(level.lanes[lane]["elem"])
	var en: bool = bool(level.lanes[lane]["entry"])
	level.lanes[lane]["cells"] = left
	level.lanes.append({"cells": right, "elem": el, "entry": en})


# =========================================================================
# TLACITKA
# =========================================================================

func press(button: int) -> void:
	if button < 0 or button >= BTN_COUNT:
		return
	if button < TOOL_COUNT:
		tool = button
		if button == TOOL_GUMA:
			status = "Guma: klepni na uzel nebo na cestu."
		elif button == TOOL_ROAD:
			status = "Tažením prstu kresli cestu (%s)." % Element.name_of(elem)
		else:
			status = "Klepni, kam má %s přijít." % TOOL_LABELS[button]
		return
	match button:
		BTN_ELEM:
			elem = (elem + 1) % Element.COUNT
			status = "Kreslím živel: %s." % Element.name_of(elem)
		BTN_NEW:
			reset()
		BTN_EXPORT:
			_export()
		BTN_PLAY:
			pass


func _export() -> void:
	code = level.to_code()
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = "Mapa má chybu: %s" % errs[0]
		return
	status = "Kód je vypsaný nad pruhem — opiš ho nebo pošli."


# =========================================================================
# PO KAZDE ZMENE
# =========================================================================

# Jedno misto, ktere se stara o vsechno po zmene mapy:
#   * vstupni usek se pozná Z GRAFU (je to ten ze startu), ne z priznaku -
#     hrac ho nemusi nikde zapinat a nemuze ho zapomenout prenastavit,
#   * zkontroluje se cela mapa a prvni chyba jde do statusu,
#   * ulozi se. Save tlacitko nema smysl: hrac uklada kazdou zmenu.
func _after_change() -> void:
	var st: int = level.first_start()
	for i in range(level.lane_count()):
		level.lanes[i]["entry"] = (st >= 0 and level.lane_start_node(i) == st)
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = errs[0]
	level.save()
