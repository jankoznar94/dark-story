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

# TYP CESTY, KTERY SE KRESLI. Ctyri zivly + neutralni usek + kmen. Jan:
# "v nabidce typu cest chybi neutralni a kmen (nedava zadne poskozeni)".
# Poradi je dane: zivly dokola jako dosud, pak dva useky bez elementu.
const TYPE_CYCLE := [Element.FIRE, Element.WATER, Element.EARTH, Element.AIR,
	Level.NEUTRAL, Level.KMEN]

# PRUH TABU + ROZBALOVACI PANELY. Editor uz nema jednu radu trinacti
# tlacitek: dole je pruh s taby (nastroje / vyber / level) a ctyrmi akcemi
# (zpet, seznam, export, hrat), a nad nim se rozbali panel te kategorie.
#
# Proc to: do rady se uz NIC neveslo (trinact je strop pro 640x360) a popisky
# se musely zmensovat na 11 px. V panelu je na popisky vic mista a hlavne je
# kam dat nove veci - parametry levelu (cas kola, rychlost, zivoty, zlato,
# sila useku), ktere driv nemely vubec ovladani.
#
# CISLA TLACITEK ZUSTAVAJI (press(act)) - panel je jen to, KDE tlacitko bydli.
# Vstup do UI je VZDY `bar_entries()` / `panel_rows()`: kdyby si kresleni
# a klepnuti stavely vlastni seznam, rozejdou se a tlacitko bude jinde, nez
# se macka.
enum { PANEL_NONE, PANEL_TOOLS, PANEL_SEL, PANEL_LEVEL }
const PANEL_LABELS := ["nástroje", "výběr", "level"]
const PANEL_COUNT := 3
const PANEL_HINTS := [
	"",
	"Nástroje: klepni na nástroj, kterým se kreslí nebo klade prvek.",
	"Výběr: klepni na úsek nebo na prvek, pak tady měň, co k němu patří.",
	"Level: kolo = čas vstupů · rychlost poutníků · životy · zlato · síla úseku = poskození za projetí.",
]

# Tlacitka za nastroji. Poradi je dane; cisla se nesmi prekryvat s nastroji.
const BTN_ELEM := TOOL_COUNT
# U VYBRANEHO PRVKU tohle tlacitko cykluje DRUH uzlu ("druh: výhybka").
# U useku se pocet mist meni DVEMA tlacitky - cyklus 0..6 znamenal z "mista 3"
# na "mista 0" ctyri klepnuti a hrac u toho preletel vsechno mezi tim.
const BTN_SLOTS := TOOL_COUNT + 1
const BTN_SLOTS_DOWN := TOOL_COUNT + 2
const BTN_SLOTS_UP := TOOL_COUNT + 3
# SMAZAT VYBER. Guma maze klepnutim na prvek nebo na cestu; tohle maze to,
# co je prave oznacene - hrac nemusi trefovat maly uzel, ktery uz ma vybrany.
const BTN_DELETE := TOOL_COUNT + 4
# "ZPET" - vraci posledni upravu. Nahradilo tlacitko "novy": novy level se
# da udelat prvnim radkem v seznamu (a "zpet" je pri kresleni potreba
# mnohem casteji nez novy level).
const BTN_UNDO := TOOL_COUNT + 5
const BTN_LIST := TOOL_COUNT + 6
const BTN_EXPORT := TOOL_COUNT + 7
const BTN_PLAY := TOOL_COUNT + 8
# PARAMETRY LEVELU. Dva za sebou (dolu, nahoru) pro kazdy parametr.
const BTN_PARAM_DOWN := BTN_PLAY + 1
# TABULKA PARAMETRU LEVELU je JEDNO misto, kde se o nich vi vsechno: jak se
# jmenuji, jaky je krok a meze. Popisek tlacitka, klepnuti i test se ptaji
# tady - jinak by popisek za chovani zaostal.
# "f" = desetinne cislo, "i" = cele cislo (do levelu se zapisuje jako int).
const PARAMS := [
	{"key": "round_time", "label": "kolo", "kind": "f", "step": 15.0, "lo": 15.0, "hi": 600.0},
	{"key": "speed", "label": "rychlost", "kind": "f", "step": 4.0, "lo": 12.0, "hi": 200.0},
	{"key": "lives", "label": "životy", "kind": "i", "step": 2.0, "lo": 1.0, "hi": 99.0},
	{"key": "gold", "label": "zlato", "kind": "i", "step": 20.0, "lo": 0.0, "hi": 2000.0},
	{"key": "zone_dmg", "label": "síla", "kind": "f", "step": 5.0, "lo": 5.0, "hi": 200.0},
]
const PARAM_COUNT := 5
const BTN_COUNT := BTN_PARAM_DOWN + PARAM_COUNT * 2

const TOOL_KINDS := [Level.NEUTRAL, Level.START, Level.CIL, Level.VYHYBKA,
	Level.SPOJKA, Level.UZEL, Level.NEUTRAL]

# KOLIK UPRAV SE PAMATUJE NA "ZPET". Kazda polozka je kopie levelu (mala
# data), takze se jich par desitek vejde i na telefon.
const UNDO_MAX := 30

enum { MODE_EDIT, MODE_LIST }

var level: Level = null
var tool: int = TOOL_ROAD
var elem: int = Element.FIRE
# KOLIK MIST DOSTANOU NOVE KRESLENE USEKY. Kazdy usek si svuj pocet drzi v
# levelu (Level.lane_slot_count) - tohle je jen to, cim se zacina.
var draw_slots: int = Level.SLOTS
# VYBRANY USEK. Klepnuti na caru useku (ne na uzel) ho vybere a pak uz
# "zivel" a "mista" meni JEHO vlastnosti, ne vlastnosti dalsi kresby.
# Presne to Janovi chybelo: "upravovat jiz existujici zatim nejde".
var sel_lane: int = -1
# VYBRANY PRVEK (uzel). Klepnuti na uzel ho oznaci - hrac vidi, co si
# vybral, a tlacitko "mista" se zmeni na "druh", kterym se meni druh uzlu
# (start -> cil -> vyhybka -> spojka -> uzel). Vyber je VZDY jen jeden:
# bud usek, nebo prvek.
var sel_node: int = -1
# ZPET. Kazda uprava si pred sebou ulozi kopii levelu; "zpet" ji vrati.
var undo_stack: Array = []
# PRESOUVANI UZLU. Klepnuti na uzel mu zmeni druh, TAZENI z uzlu ho presune
# na jinou bunku - a cesty, ktere do nej vedly, se prepoji (nebo prodlouzi).
# Je to zamerne az od nastroju z palety: tazenim nastrojem "cesta" se kresli
# nova cesta, takze by si obe gesta lezla pod rukama.
var moving: bool = false
var move_node: int = -1
var move_from: Vector2i = Vector2i(-1, -1)
var move_steps: int = 0
var status: String = ""
var code: String = ""
var local_name: String = ""
var mode: int = MODE_EDIT
# KTERY PANEL JE OTEVRENY. Panel prekryva spodni kus desky, takze klepnuti na
# desku ho zavre (aby se pod panelem omylem nekladl prvek) - proto je to stav,
# ktery znaji kresleni, klepnuti i rozvrzeni.
var panel: int = PANEL_NONE

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
	# NOVY LEVEL: kdyz ma ten soucasny co ztratit, jde to vzit zpet.
	_snapshot_if_used()
	var keep: String = _free_name()
	level = Level.new()
	local_name = keep
	level.name = local_name
	mode = MODE_EDIT
	panel = PANEL_NONE
	tool = TOOL_ROAD
	status = "Prázdná mřížka. Polož START a pak tažením prstu kresli cesty."
	code = ""
	drawing = false
	draw_cells = []
	mark = Vector2i(-1, -1)
	sel_lane = -1
	sel_node = -1
	draw_slots = Level.SLOTS
	moving = false
	move_node = -1
	move_from = Vector2i(-1, -1)
	move_steps = 0
	level.save()


# =========================================================================
# ZPET (vraceni upravy)
# =========================================================================

# Kopie stavu PRED upravou. Kazda uprava levelu si ji zavola sama, tesne
# pred tim, nez neco zmeni - kdyby to delalo neco spolecneho po zmene, byl
# by v kopii uz pozmeneny level a "zpet" by nevracel nic.
func _snapshot() -> void:
	_push_state(local_name, level.clone(), sel_lane, sel_node)


func _push_state(nm: String, lv: Level, ln: int, nd: int) -> void:
	undo_stack.append({"name": nm, "level": lv, "lane": ln, "node": nd})
	while undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()


# Vraci se i JMENO levelu: kdyz hrac omylem klepne na "nový level" nebo
# nacte jiny, musi se dostat zpet k tomu, co delal - jinak by prisel o
# praci, kterou si "zpet" nedokaze vzit.
func undo() -> void:
	if undo_stack.is_empty():
		status = "Není co vrátit."
		return
	var st: Dictionary = undo_stack.pop_back()
	var lv: Level = st["level"]
	if lv == null:
		status = "Není co vrátit."
		return
	level = lv
	local_name = str(st["name"])
	level.name = local_name
	sel_lane = int(st["lane"])
	sel_node = int(st["node"])
	drawing = false
	draw_cells = []
	moving = false
	move_node = -1
	_after_change()
	status = "Zpět (%d kroků zpátky)." % undo_stack.size()


# Ulozi stav jen kdyz je co ztratit. Prazdna mrizka nema co vracet a
# ukladat ji by jen zaplevelilo "zpet".
func _snapshot_if_used() -> void:
	if level.lane_count() > 0 or level.node_count() > 0:
		_snapshot()


# Kazdy novy level dostane VLASTNI jmeno, aby ten predchozi neprepsal.
# Prepsat cizi praci jednim klepnutim je to nejhorsi, co editor umi.
#
# Vyjimka: kdyz je ten soucasny level jeste PRAZDNY, novy ho prevezme.
# Bez toho by kazde klepnuti na "novy" nechalo za sebou prazdnou skolku
# a seznam by se zaplnil necem, co nikdo nikdy nechtel.
func _free_name() -> String:
	if level != null and local_name != "" \
			and level.lane_count() == 0 and level.node_count() == 0:
		return local_name
	var keys: Array = level.saved_keys()
	var n: int = 1
	while keys.has("level-%d" % n):
		n += 1
	return "level-%d" % n


func open_last() -> void:
	var keys: Array = level.saved_keys()
	if keys.is_empty():
		reset()
		return
	local_name = str(keys[keys.size() - 1])
	if level.load_from_disk(local_name):
		sel_lane = -1
		status = "Načteno: %s" % level.name
	else:
		reset()


# =========================================================================
# SEZNAM ULOZENYCH LEVELU
# =========================================================================

func is_list() -> bool:
	return mode == MODE_LIST


func open_list() -> void:
	mode = MODE_LIST


func close_list() -> void:
	mode = MODE_EDIT


# Prvni radek je NOVY level, pak vsechno ulozene, posledni je navrat.
func list_items() -> Array:
	var out: Array = [{"kind": "new", "name": "nový level", "key": ""}]
	for k in level.saved_keys():
		out.append({"kind": "level", "name": str(k), "key": k})
	out.append({"kind": "back", "name": "zpět do kreslení", "key": ""})
	return out


func pick(item: Dictionary) -> void:
	var kind: String = str(item["kind"])
	if kind == "new":
		reset()
		return
	if kind == "back":
		close_list()
		return
	var key: String = str(item["key"])
	# Nacitani jineho levelu je taky uprava: "zpet" musi vratit ten, ktery
	# tu byl predtim (i s jeho jmenem).
	var pre: Level = level.clone()
	var pre_name: String = local_name
	var pre_lane: int = sel_lane
	var pre_node: int = sel_node
	if level.load_from_disk(key):
		_push_state(pre_name, pre, pre_lane, pre_node)
		local_name = key
		sel_lane = -1
		sel_node = -1
		status = "Načteno: %s" % level.name
	else:
		status = "Level %s se nepodařilo načíst." % key
	close_list()


# =========================================================================
# PRUH A PANELY
# =========================================================================

# SPODNI PRUH. Tri taby (oteviraji panel nad pruhem) a ctyri akce, ktere se
# delaji hned. Kresleni, klepnuti i testy jdou pres tenhle jediny seznam:
# kdyby si kazdy stavil vlastni, tlacitko by bylo jinde, nez se macka.
func bar_entries() -> Array:
	return [
		{"tab": PANEL_TOOLS, "act": -1, "label": PANEL_LABELS[0]},
		{"tab": PANEL_SEL, "act": -1, "label": PANEL_LABELS[1]},
		{"tab": PANEL_LEVEL, "act": -1, "label": PANEL_LABELS[2]},
		{"tab": -1, "act": BTN_UNDO, "label": "zpět"},
		{"tab": -1, "act": BTN_LIST, "label": "seznam"},
		{"tab": -1, "act": BTN_EXPORT, "label": "export"},
		{"tab": -1, "act": BTN_PLAY, "label": "hrát"},
	]


# OBSAH OTEVRENEHO PANELU. Vraci RADKY ZDOLA NAHOR (prvni radek je u pruhu),
# kazda polozka je:
#   act   - cislo tlacitka pro press(); -1 = jen popisek hodnoty, ne tlacitko
#   label - co je na nem napsane
#   w     - vaha sirky (1.0 = obycejne tlacitko)
#   on    - je to prave zvolena vec (kresli se svetleji)
#   kind  - "tool" | "elem" | "danger" | "value" | "action" (podle toho barva)
func panel_rows() -> Array:
	match panel:
		PANEL_TOOLS:
			var row: Array = []
			for i in range(TOOL_COUNT):
				row.append({"act": i, "label": TOOL_LABELS[i], "w": 1.0,
					"on": tool == i, "kind": "tool"})
			return [row]
		PANEL_SEL:
			return _sel_rows()
		PANEL_LEVEL:
			return _level_rows()
	return []


# PANEL "VYBER". Co se da delat, zavisi na tom, co je oznacene - a kdyz nic,
# meni se tim, cim se bude kreslit DALSI cesta (jako driv tlacitko "mista").
# POCET MIST JE VIDET V HORNIM PRUHU (a v hlasce po kazdem klepnuti): tlacitka
# jsou proto jen "místa −" a "místa +", ne jedno pretáčecí.
func _sel_rows() -> Array:
	if sel_node >= 0 and sel_node < level.node_count():
		return [[
			{"act": BTN_SLOTS, "label": _kind_label(), "w": 1.6, "on": false, "kind": "action"},
			{"act": BTN_DELETE, "label": "smazat prvek", "w": 1.3, "on": false, "kind": "danger"},
		]]
	var row: Array = [
		{"act": BTN_ELEM, "label": Level.value_name(elem), "w": 1.4, "on": false, "kind": "elem"},
		{"act": BTN_SLOTS_DOWN, "label": "místa −", "w": 1.0, "on": false, "kind": "action"},
		{"act": BTN_SLOTS_UP, "label": "místa +", "w": 1.0, "on": false, "kind": "action"},
	]
	if sel_lane >= 0 and sel_lane < level.lane_count():
		row.append({"act": BTN_DELETE, "label": "smazat úsek", "w": 1.3, "on": false, "kind": "danger"})
	return [row]


# PANEL "LEVEL". Dva radky parametru, kazdy jako [−] [hodnota] [+] - hodnota
# je jen popisek, ne tlacitko (tlacitko, ktere nic nedela, je lez).
func _level_rows() -> Array:
	return [
		_param_row([0, 1, 2]),
		_param_row([3, 4]),
	]


func _param_row(ids: Array) -> Array:
	var row: Array = []
	for p in ids:
		var par: Dictionary = PARAMS[p]
		var key: String = str(par["key"])
		row.append({"act": BTN_PARAM_DOWN + int(p) * 2, "label": "%s −" % str(par["label"]),
			"w": 0.9, "on": false, "kind": "action"})
		row.append({"act": -1, "label": _param_text(key), "w": 1.0, "on": false, "kind": "value"})
		row.append({"act": BTN_PARAM_DOWN + int(p) * 2 + 1, "label": "%s +" % str(par["label"]),
			"w": 0.9, "on": false, "kind": "action"})
	return row


# HODNOTA PARAMETRU jako text (popisek mezi − a +). Cela cisla se kresli bez
# desetinne tecky, cas kola s jednotkou - jinak by "120.00" nikdo neprecetl.
# POZOR: Godot v `%` formatu NEMA `%g` (spadne to na "unsupported format
# character" a funkce se ukonci - popisek pak zustane syrovy s "%g" v sobe).
func _param_text(key: String) -> String:
	var v: float = float(level.get(key))
	for p in PARAMS:
		if str(p["key"]) == key:
			var txt: String = str(int(round(v))) if str(p["kind"]) == "i" else _fmt_num(v)
			return txt + (" s" if key == "round_time" else "")
	return _fmt_num(v)


func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(round(v)))
	return "%.1f" % v


# JE TO CISLO TLACITKA PARAMETRU? Jedno misto, kde se to rozhoduje - jinak by
# se "cislo nad BTN_PARAM_DOWN" pocitalo na vice mistech a nekde by uteklo.
func is_param_button(b: int) -> bool:
	return b >= BTN_PARAM_DOWN and b < BTN_COUNT


func param_of_button(b: int) -> int:
	if not is_param_button(b):
		return -1
	return int((b - BTN_PARAM_DOWN) / 2)


# OTEVRENI / ZAVRENI PANELU. Klepnuti na tentýž tab panel zavre - hrac tak
# muze panel schovat, aniž by musel nekam jinam.
func toggle_panel(p: int) -> void:
	if p < 0 or p > PANEL_COUNT:
		return
	if panel == p:
		panel = PANEL_NONE
		status = "Panel zavřen (klepni na tab a otevřeš ho znovu)."
		return
	panel = p
	status = str(PANEL_HINTS[p])


func close_panel() -> void:
	panel = PANEL_NONE


# PRUH: klepnuti na polozku pruhu. Tab otevira/zavira panel, akce se dela hned.
func tap_bar(i: int) -> void:
	var e: Array = bar_entries()
	if i < 0 or i >= e.size():
		return
	var it: Dictionary = e[i]
	if int(it["tab"]) >= 0:
		toggle_panel(int(it["tab"]))
		return
	press(int(it["act"]))


# KOLIK MIST UKAZUJE HORNI PRUH. Pocet mist neni na tlacitku ("místa −/+"),
# takze jedine, co hrac opravdu cte, je text vyberu nahore - testy se ptaji
# tady, aby nemerily neco jineho, nez je na obrazovce.
func slots_text() -> String:
	if sel_lane >= 0 and sel_lane < level.lane_count():
		return "úsek %d · míst %d" % [sel_lane, level.lane_bonus_slots(sel_lane)]
	return "míst %d" % selected_slot_count()


# POPISEK TLACITKA U VYBRANEHO PRVKU. Ukazuje DRUH uzlu, ktery stiskem
# prekaci (start -> cíl -> výhybka -> spojka -> uzel). Tlacitko NIKDY nelze:
# co je na nem napsane, to se stiskem zmeni.
func _kind_label() -> String:
	return "druh: %s" % level.kind_name(level.node_kind(sel_node))


# KOLIK MIST MA VYBRANY USEK (nula, kdyz na nem nejde stavet). Pouziva se
# i pro kresleni dalsich cest - `draw_slots` je vychozi hodnota.
func selected_slot_count() -> int:
	if sel_lane >= 0 and sel_lane < level.lane_count():
		return level.lane_slot_count(sel_lane)
	return draw_slots


# Je to tlačítko "hrát"? Pruh se kresli z jednoho seznamu a tohle je jedine
# misto, kde se rozhoduje, co se stane po klepnuti.
func is_play(button: int) -> bool:
	return button == BTN_PLAY


func sel_text() -> String:
	if sel_node >= 0 and sel_node < level.node_count():
		var ins: int = level.lanes_into(sel_node).size()
		var outs: int = level.lanes_from(sel_node).size()
		return "prvek %d · %s · %d vstupů · %d výstupů (tažením přesuneš, paletou změníš druh)" % [
			sel_node, level.kind_name(level.node_kind(sel_node)), ins, outs]
	if sel_lane >= 0 and sel_lane < level.lane_count():
		return "úsek %d · %s · míst %d · (úseků %d · uzlů %d)" % [sel_lane,
			level.lane_type_name(sel_lane),
			level.lane_bonus_slots(sel_lane), level.lane_count(), level.node_count()]
	return "úseků %d · uzlů %d · nové cesty: %s, míst %d — klepni na úsek nebo na prvek a vybereš ho" % [
		level.lane_count(), level.node_count(), Level.value_name(elem), selected_slot_count()]


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
		# KLEPNUTI, NE TAH: nic se nekresli, ale hrac si tim VYBRAL, co
		# lezi pod prstem - usek nebo PRVEK (uzel). Je to jedine gesto,
		# ktere se nerozchazi s kladenim prvku: tazenim se kresli,
		# klepnutim se vybira. Jan: "chybi mi moznost oznacit jiz
		# existujici prvek, abych ho mohl upravit".
		if _select_at(cs[0]):
			return
		status = "Cesta je krátká — nakresli aspoň dvě buňky."
		return
	var a: int = level.node_at_cell(cs[0])
	var b: int = level.node_at_cell(cs[cs.size() - 1])
	if a < 0 or b < 0:
		status = "Cesta musí začínat i končit v uzlu (start, výhybka, spojka, uzel)."
		return
	_snapshot()
	# VSTUPNI USEK (ten, ktery vede ze STARTu) SE KRESLI JAKO KMEN. Driv si
	# nesl barvu zvoleneho elementu, ale neposkozoval - hrac videl oranzovy
	# pruh a divil se, proc na nem nic nedela (Jan: "barvu má jak element
	# a je to matoucí"). Tlacitkem "typ" ho pak hrac muze prepnout na
	# element a zpet na kmen - je to normalni hodnota useku, zadny priznak.
	var start_node: int = level.first_start()
	var from_start: bool = (start_node >= 0 and a == start_node)
	var el: int = Level.KMEN if from_start else draw_elem
	level.lanes.append({"cells": cs, "elem": el, "entry": false,
		"slots": draw_slots})
	sel_lane = level.lane_count() - 1
	sel_node = -1
	_after_change()
	if from_start:
		status = "Úsek %d je vstupní — vede ze startu, proto se kreslí jako kmen (nepoškozuje). Tlacítkem \"typ\" ho přepneš na element." % level.lane_count()
	elif draw_elem == Level.KMEN:
		status = "Úsek %d je kmen — neposkozuje, takže na něm nejde stavět." % level.lane_count()
	elif draw_elem == Level.NEUTRAL:
		status = "Úsek %d je neutrální — poskozuje všechny stejně, stavět se na něm nedá." % level.lane_count()
	else:
		status = "Úsek %d (%s) přidán s %d místy." % [level.lane_count(),
			Level.value_name(draw_elem), draw_slots]


# OZNACENI PRVKU NEBO USEKU. Vraci true, kdyz neco naslo.
# Uzel ma prednost: je mensi nez usek, ktery pod nim vede, takze klepnuti
# na uzel musi vybrat uzel a ne cestu.
func _select_at(cell: Vector2i) -> bool:
	var n: int = level.node_at_cell(cell)
	if n >= 0:
		sel_node = n
		sel_lane = -1
		status = "Vybran prvek %d: %s (%d vstupů, %d výstupů)." % [n,
			level.kind_name(level.node_kind(n)),
			level.lanes_into(n).size(), level.lanes_from(n).size()]
		return true
	var sel: int = lane_through(cell)
	if sel >= 0:
		sel_lane = sel
		sel_node = -1
		status = "Vybran úsek %d (%s, míst %d)." % [sel, level.lane_type_name(sel),
			level.lane_bonus_slots(sel)]
		return true
	status = "Tady nic není — klepni na úsek nebo na prvek."
	return false


func _lane_element_name(lane: int) -> String:
	return level.lane_type_name(lane)


# =========================================================================
# KLEPNUTI
# =========================================================================

func tap_cell(cell: Vector2i) -> void:
	if not level.in_bounds(cell.x, cell.y):
		return
	mark = cell
	match tool:
		TOOL_ROAD:
			# Klepnutim nastrojem "cesta" se VYBIRA (uzel nebo usek), aby
			# hrac nemusel prepinat nastroj, kdyz chce neco upravit.
			if not _select_at(cell):
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
		if level.node_kind(existing) == kind:
			sel_node = existing
			sel_lane = -1
			status = "Prvek na %d,%d už je %s." % [cell.x, cell.y, level.kind_name(kind)]
			return
		_snapshot()
		level.nodes[existing]["kind"] = kind
		sel_node = existing
		sel_lane = -1
		_after_change()
		status = "Prvek na %d,%d je teď %s." % [cell.x, cell.y, level.kind_name(kind)]
		return
	# UPROSTRED CESTY: cesta se tam ROZDELI. Kdyby se nerozdělila, uzel by
	# ležel na úseku a ten by neměl v uzlu ani začátek, ani konec - graf by
	# se rozbil.
	var at: int = lane_through(cell)
	_snapshot()
	if at >= 0:
		_split_lane(at, cell)
		sel_lane = at
	level.nodes.append({"c": cell.x, "r": cell.y, "kind": kind})
	sel_node = level.node_count() - 1
	sel_lane = -1
	_after_change()
	status = "%s položen na %d,%d." % [level.kind_name(kind), cell.x, cell.y]


func _erase(cell: Vector2i) -> void:
	var n: int = level.node_at_cell(cell)
	if n >= 0:
		_snapshot()
		level.nodes.remove_at(n)
		# Indexy uzlu se posunuly - vyber musi zmizet, jinak by ukazoval
		# na jiny prvek, nez ktery hrac smazal.
		sel_lane = -1
		sel_node = -1
		_after_change()
		status = "Prvek smazán."
		return
	var l: int = lane_through(cell)
	if l >= 0:
		_snapshot()
		level.lanes.remove_at(l)
		sel_lane = -1
		sel_node = -1
		_after_change()
		status = "Úsek smazán."
		return
	status = "Tady nic není."


# =========================================================================
# PRESOUVANI UZLU
# =========================================================================

# Presouvat se da jen nastroji z palety. "cesta" kresli (tah = nova cesta)
# a "guma" maze - u tech dvou by tah znamenal neco jineho.
func can_move() -> bool:
	return tool != TOOL_ROAD and tool != TOOL_GUMA


# Zacatek tazeni na uzlu. Vraci true, kdyz se opravdu zacalo - klepnuti
# (tah bez pohybu) se vyhodnoti az pri pusteni, aby se druh uzlu menil
# stejne jako dosud.
func begin_move(cell: Vector2i) -> bool:
	if not can_move() or moving:
		return false
	var n: int = level.node_at_cell(cell)
	if n < 0:
		return false
	moving = true
	move_node = n
	move_from = cell
	move_steps = 0
	status = "Tažením uzel přesuneš, klepnutím mu změníš druh."
	return true


# Tahnuti na jinou bunku. Uzel jde PO BUNKACH, proto se krokuje - diky tomu
# se nikdy nepreskoci bunka a cesta zustane souvisla.
func extend_move(target: Vector2i) -> bool:
	if not moving:
		return false
	# Kopie stavu PRED prvnim krokem. Presun se dela po krocich, ale pro
	# "zpet" je to jedna uprava - jinak by hrac musel mackat zpet za kazdou
	# bunku, kterou uzel popojel.
	var first: bool = move_steps == 0
	var pre: Level = null
	if first:
		pre = level.clone()
	var moved := false
	var guard: int = 0
	while guard < 32:
		guard += 1
		var cur: Vector2i = level.node_cell(move_node)
		if cur == target:
			break
		if not _move_step(cur, target):
			break
		moved = true
		move_steps += 1
	if moved:
		if first and pre != null:
			_push_state(local_name, pre, sel_lane, sel_node)
		var at: Vector2i = level.node_cell(move_node)
		status = "Prvek %d přesunut na %d,%d." % [move_node, at.x, at.y]
	return moved


func end_move() -> void:
	if not moving:
		return
	moving = false
	var n: int = move_node
	var from: Vector2i = move_from
	move_node = -1
	move_from = Vector2i(-1, -1)
	if move_steps == 0:
		# TAH BEZ POHYBU = KLEPNUTI. Uzel meni druh podle zvoleneho nastroje,
		# presne jak to delalo pred tim, nez se dalo presouvat.
		tap_cell(from)
		return
	_after_change()
	var at: Vector2i = level.node_cell(n)
	status = "Uzel %d je teď na %d,%d." % [n, at.x, at.y]
	move_steps = 0


func _move_step(cur: Vector2i, target: Vector2i) -> bool:
	var dx: int = target.x - cur.x
	var dy: int = target.y - cur.y
	var tries: Array = []
	# Vetsi odchylka prvni - uzel se tak po mrizce plazi, misto aby skakal.
	if absi(dx) >= absi(dy):
		if dx != 0:
			tries.append(Vector2i(signi(dx), 0))
		if dy != 0:
			tries.append(Vector2i(0, signi(dy)))
	else:
		if dy != 0:
			tries.append(Vector2i(0, signi(dy)))
		if dx != 0:
			tries.append(Vector2i(signi(dx), 0))
	for t in tries:
		if _try_move_node(move_node, cur + t):
			return true
	return false


# Prestěhuje uzel na sousedni bunku a prepoji vsechny cesty, ktere se ho
# dotykaji. Kdyz by tim mapa prisla o neco, co platilo (kontrola mapy), krok
# se VZYZKOUSNE - presne jako u kazde jine chranene zmeny v tomto editoru.
func _try_move_node(n: int, to: Vector2i) -> bool:
	if not level.in_bounds(to.x, to.y):
		return false
	var other: int = level.node_at_cell(to)
	if other >= 0 and other != n:
		return false
	var from: Vector2i = level.node_cell(n)
	var touching: Array = level.lanes_at(n)
	for item in touching:
		var l: int = int(item)
		# pres jinou cestu uzel prejet nesmi - cesty se v tomto modelu nekrizi
		for j in range(level.lane_count()):
			if j == l:
				continue
			if _lane_uses_cell(j, to):
				return false
	var keep: Level = level.clone()
	level.nodes[n]["c"] = to.x
	level.nodes[n]["r"] = to.y
	for item in touching:
		_reroute_lane(int(item), from, to)
	var before: Array = keep.validate()
	var after: Array = level.validate()
	if after.size() > before.size():
		level = keep
		return false
	return true


# Prepojeni jednoho useku po presunu jeho krajniho uzlu.
#   * uzel se posunul po sve vlastni ceste  -> usek se ZKRATI,
#   * uzel se posunul mimo -> usek se prodlouzi o chybejici bunky, takze
#     zustane souvisly (a ohne se, kdyz hrac taha do strany).
func _reroute_lane(lane: int, from: Vector2i, to: Vector2i) -> void:
	var cs: Array = level.lane_cells(lane)
	if cs.size() < 2:
		return
	if cs[0] == from:
		var k: int = _index_of(cs, to)
		if k > 0:
			level.lanes[lane]["cells"] = _slice(cs, k, cs.size())
			return
		var head: Array = [to]
		head.append_array(_route_known(cs[1], to, cs))
		head.append_array(_slice(cs, 1, cs.size()))
		level.lanes[lane]["cells"] = head
		return
	var kk: int = _index_of(cs, to)
	if kk >= 0 and kk < cs.size() - 1:
		level.lanes[lane]["cells"] = _slice(cs, 0, kk + 1)
		return
	var tail: Array = _slice(cs, 0, cs.size() - 1)
	tail.append_array(_route_known(cs[cs.size() - 2], to, cs))
	tail.append(to)
	level.lanes[lane]["cells"] = tail


func _index_of(cells: Array, cell: Vector2i) -> int:
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		if c == cell:
			return i
	return -1


func _slice(cells: Array, a: int, b: int) -> Array:
	var out: Array = []
	for i in range(maxi(a, 0), mini(b, cells.size())):
		out.append(cells[i])
	return out


# Bunky MEZI `from` a `to` (beznich) po ose. Pro sousedni bunky je to
# prazdny seznam, pro vzdalenejsi se cesta prodlouzi a pro sikmy smer se ohne.
#
# PORADI OS SE VYBIRA: propojeni existuje ve dvou tvarech a ten, ktery
# pouzije bunky, ktere v ceste UZ BYLY, je ten spravny - druhy by z cesty
# udelal zbytecnou klucku tam a zpet.
func _route(from: Vector2i, to: Vector2i) -> Array:
	return _route_xy(from, to)


func _route_known(from: Vector2i, to: Vector2i, known: Array) -> Array:
	var a: Array = _route_xy(from, to)
	var b: Array = _route_yx(from, to)
	if _known_count(b, known) > _known_count(a, known):
		return b
	return a


func _known_count(route: Array, known: Array) -> int:
	var seen: int = 0
	for c in route:
		var v: Vector2i = c
		if known.has(v):
			seen += 1
	return seen


func _route_xy(from: Vector2i, to: Vector2i) -> Array:
	var out: Array = []
	var cur: Vector2i = from
	while cur.x != to.x:
		cur = Vector2i(cur.x + signi(to.x - cur.x), cur.y)
		if cur != to:
			out.append(cur)
	while cur.y != to.y:
		cur = Vector2i(cur.x, cur.y + signi(to.y - cur.y))
		if cur != to:
			out.append(cur)
	return out


func _route_yx(from: Vector2i, to: Vector2i) -> Array:
	var out: Array = []
	var cur: Vector2i = from
	while cur.y != to.y:
		cur = Vector2i(cur.x, cur.y + signi(to.y - cur.y))
		if cur != to:
			out.append(cur)
	while cur.x != to.x:
		cur = Vector2i(cur.x + signi(to.x - cur.x), cur.y)
		if cur != to:
			out.append(cur)
	return out


func _lane_uses_cell(lane: int, cell: Vector2i) -> bool:
	for c in level.lane_cells(lane):
		var v: Vector2i = c
		if v == cell:
			return true
	return false


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
	var sl: int = level.lane_slot_count(lane)
	level.lanes[lane]["cells"] = left
	level.lanes.append({"cells": right, "elem": el, "entry": en, "slots": sl})


# =========================================================================
# TLACITKA
# =========================================================================

func press(button: int) -> void:
	if button < 0 or button >= BTN_COUNT:
		return
	if button < TOOL_COUNT:
		tool = button
		if button == TOOL_GUMA:
			status = "Guma: klepni na prvek nebo na cestu."
		elif button == TOOL_ROAD:
			status = "Tažením prstu kresli cestu (%s). Klepnutím úsek nebo prvek vybereš." \
				% Level.value_name(elem)
		else:
			status = "Klepni, kam má %s přijít. Tažením z prvku ho přesuneš." \
				% TOOL_LABELS[button]
		return
	if is_param_button(button):
		_param_step(button)
		return
	match button:
		BTN_ELEM:
			_elem_press()
		BTN_SLOTS:
			_slots_press()
		BTN_SLOTS_UP:
			_slots_step(1)
		BTN_SLOTS_DOWN:
			_slots_step(-1)
		BTN_DELETE:
			_delete_press()
		BTN_UNDO:
			undo()
		BTN_LIST:
			open_list()
		BTN_EXPORT:
			_export()
		BTN_PLAY:
			pass


# ZIVEL. Kdyz je vybrany usek, meni se TYP TOHO USEKU (zivel, neutralni
# usek, kmen) - presne to, co Janovi chybelo ("upravovat jiz existujici
# zatim nejde"). Bez vyberu to je jen typ, kterym se kresli dalsi cesta.
#
# PLATI I PRO VSTUPNI USEK. Driv se u nej zmena odmitla ("ten neposkozuje,
# at ma na sobe cokoli") - jenze prave proto vypadal jako element a choval
# se jako kmen. Jan: "Melo by byt mozne rucne tuto vstupni cestu take
# prepnout na neco jineho nez kmen, nebo naopak prepnout na kmen."
func _elem_press() -> void:
	var at: int = TYPE_CYCLE.find(elem)
	elem = int(TYPE_CYCLE[(at + 1) % TYPE_CYCLE.size()]) if at >= 0 else int(TYPE_CYCLE[0])
	if sel_lane >= 0 and sel_lane < level.lane_count():
		_snapshot()
		level.set_lane_element(sel_lane, elem)
		_after_change()
		if level.lane_is_entry(sel_lane):
			status = "Vstupní úsek %d je teď %s. Kmen neposkozuje, na elementu se staví." % [sel_lane, Level.value_name(elem)]
		else:
			status = "Úsek %d je teď %s." % [sel_lane, Level.value_name(elem)]
		return
	status = "Kreslím typ cesty: %s." % Level.value_name(elem)


# TLACITKO "DRUH" U VYBRANEHO PRVKU. Existuje jen pro prvek - u useku se pocet
# mist meni tlacitky "místa −"/"místa +" (viz `_slots_step`).
func _slots_press() -> void:
	if sel_node >= 0 and sel_node < level.node_count():
		_kind_press()
		return
	status = "Tenhle stisk patří prvku — klepni na uzel a změníš jeho druh. Místa na úseku měň přes „místa − / +“."


# POCET MIST NA BONUS: JEDNO KLEPNUTI = JEDNO MISTO. Meni se bud na vybranem
# useku, nebo (bez vyberu) na tom, s cim se kresli dalsi cesta.
# Usek, ktery neposkozuje (vstupni usek, kmen), mista NEMA - rekne se proc,
# protoze tiche odmitnuti necha hrace klepat dokola a hledat chybu v sobe.
func _slots_step(dir: int) -> void:
	var cur: int = selected_slot_count()
	var nxt: int = clampi(cur + dir, 0, Level.MAX_SLOTS)
	if nxt == cur:
		if dir < 0:
			status = "Míň než 0 míst nejde — úsek je bez bonusů."
		else:
			status = "Víc než %d míst na jeden úsek nejde." % Level.MAX_SLOTS
		return
	if sel_node >= 0 and sel_node < level.node_count():
		status = "Vybraný je prvek, ne úsek — místa se mění na úseku."
		return
	if sel_lane >= 0 and sel_lane < level.lane_count():
		if not level.lane_deals_damage(sel_lane):
			status = "Úsek %d neposkozuje (vstupní úsek nebo kmen) — bonus na něm nemá co posílit." % sel_lane
			return
		_snapshot()
		level.set_lane_slots(sel_lane, nxt)
		_after_change()
		if nxt == 0:
			status = "Úsek %d je bez bonusů (0 míst)." % sel_lane
		else:
			status = "Úsek %d má teď %d míst na bonus." % [sel_lane, nxt]
		return
	draw_slots = nxt
	status = "Nové úseky se kreslí s %d místy." % draw_slots


# DRUH VYBRANEHO PRVKU. Prekaci se dokola: start -> cíl -> výhybka ->
# spojka -> uzel -> start. Zmena druhu vetsinou znamena, ze mapa prestane
# platit (napr. z výhybky se stane uzel a zbudou dva vystupy) - to se
# hracovi rekne hned a vzit zpet to jde tlacitkem "zpět". Kontrola se tu
# ZAMERNE nedela tvrde: hrac casto potrebuje druh zmenit driv, nez cesty
# dokreslí.
func _kind_press() -> void:
	var old: int = level.node_kind(sel_node)
	var nxt: int = (old + 1) % Level.KIND_NAMES.size()
	if old < 0:
		nxt = Level.START
	_snapshot()
	level.nodes[sel_node]["kind"] = nxt
	_after_change()
	if level.validate().is_empty():
		status = "Prvek %d je teď %s — mapa pořád platí." % [sel_node, level.kind_name(nxt)]
	else:
		status = "Prvek %d je teď %s, ale mapa teď neplatí: %s" % [
			sel_node, level.kind_name(nxt), level.validate()[0]]


# SMAZAT VYBER. Guma maze klepnutim na prvek nebo na cestu; tenhle button
# maze to, co je prave oznacene - hrac nemusi na maly uzel znovu trefovat,
# kdyz uz ho ma vybrany. Po smazani vyber zmizi (indexy se posunuly, takze
# drzet ho dal by znamenalo ukazovat na neco jineho, nez hrac smazal).
func _delete_press() -> void:
	if sel_node >= 0 and sel_node < level.node_count():
		_snapshot()
		level.nodes.remove_at(sel_node)
		sel_node = -1
		sel_lane = -1
		_after_change()
		status = "Prvek smazán."
		return
	if sel_lane >= 0 and sel_lane < level.lane_count():
		_snapshot()
		level.lanes.remove_at(sel_lane)
		sel_lane = -1
		sel_node = -1
		_after_change()
		status = "Úsek smazán."
		return
	status = "Není co smazat — klepni na úsek nebo na prvek."


# ZMENA PARAMETRU LEVELU. Hodnota se nejdriv spocita a teprve kdyz se opravdu
# zmeni, ulozi se krok "zpet" a zapise - klepnuti na doraz (cas kola na maximu)
# by jinak plnilo historii kroky, ktere nic nemeni.
func _param_step(act: int) -> void:
	var p: int = param_of_button(act)
	if p < 0:
		return
	var par: Dictionary = PARAMS[p]
	var key: String = str(par["key"])
	var up: bool = (act - BTN_PARAM_DOWN) % 2 == 1
	var cur: float = float(level.get(key))
	var nv: float = clampf(cur + (float(par["step"]) if up else -float(par["step"])),
		float(par["lo"]), float(par["hi"]))
	if str(par["kind"]) == "i":
		nv = float(int(round(nv)))
	if is_equal_approx(nv, cur):
		status = "%s už je na %s — dál to nejde." % [str(par["label"]), _param_text(key)]
		return
	_snapshot()
	if str(par["kind"]) == "i":
		level.set(key, int(nv))
	else:
		level.set(key, nv)
	_after_change()
	status = "Level: %s" % _level_text()


# VSE, CO SE V PANELU "LEVEL" DA NASTAVIT - jedna hlaska, aby hrac videl
# souvislosti (a aby se hodnoty nemusely cist z peti tlacitek).
func _level_text() -> String:
	return "kolo %s · rychlost %s · životy %s · zlato %s · síla úseku %s" % [
		_param_text("round_time"), _param_text("speed"), _param_text("lives"),
		_param_text("gold"), _param_text("zone_dmg")]


# EXPORT. Kod levelu se nejen vypise nad pruhem, ale ROVNOU SE ZKOPIRUJE do
# schranky: vypsany radek se na telefonu neda oznacit, takze hrac nemel jak
# kod dostat ven. Jan: "kod se sice zobrazí, ale nedá se zkopírovat".
# Vypis nad pruhem zustava jako druha sance, kdyz zapis do schranky prohlizec
# odmitne (a hrac to v hlasce vidi).
func _export() -> void:
	code = level.to_code()
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = "Mapa má chybu: %s" % errs[0]
		return
	if Clipboard.copy(code):
		status = "Kód (%d znaků) je ve schránce — vlož ho jako text." % code.length()
	else:
		status = "Kód se nepodařilo zkopírovat — zkus Export znovu."


# =========================================================================
# PO KAZDE ZMENE
# =========================================================================

# Jedno misto, ktere se stara o vsechno po zmene mapy:
#   * vstupni usek se pozná Z GRAFU (je to ten ze startu), ne z priznaku -
#     hrac ho nemusi nikde zapinat a nemuze ho zapomenout prenastavit,
#   * zkontroluje se cela mapa a prvni chyba jde do statusu,
#   * ulozi se. Save tlacitko nema smysl: hrac uklada kazdou zmenu.
func _after_change() -> void:
	# Vybrany usek i prvek musi po kazde zmene ukazovat na neco, co
	# existuje - po smazani by vyber visel na indexu, ktery uz neni.
	if sel_lane >= level.lane_count():
		sel_lane = -1
	if sel_node >= level.node_count():
		sel_node = -1
	var st: int = level.first_start()
	for i in range(level.lane_count()):
		level.lanes[i]["entry"] = (st >= 0 and level.lane_start_node(i) == st)
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = errs[0]
	level.save()
