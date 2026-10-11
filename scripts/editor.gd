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

# NASTROJE. Poradi v enumu je poradim TLACITEK (press(act)) - novy nastroj se
# proto pridava NA KONEC, aby se cisla tech starych neposunula. Ktere nastroje
# stoji vedle sebe v panelu, rozhoduje `_tools_row()`.
enum { TOOL_ROAD, TOOL_START, TOOL_CIL, TOOL_VYHYBKA, TOOL_SPOJKA, TOOL_UZEL, TOOL_GUMA,
	TOOL_VYBER }

const TOOL_LABELS := ["cesta", "start", "cíl", "výhybka", "spojka", "uzel", "guma",
	"výběr"]
const TOOL_COUNT := 8

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
const BTN_KIND := TOOL_COUNT + 1
# SMAZAT VYBER. Guma maze klepnutim na prvek nebo na cestu; tohle maze to,
# co je prave oznacene - hrac nemusi trefovat maly uzel, ktery uz ma vybrany.
const BTN_DELETE := TOOL_COUNT + 2
# "ZPET" - vraci posledni upravu. Nahradilo tlacitko "novy": novy level se
# da udelat prvnim radkem v seznamu (a "zpet" je pri kresleni potreba
# mnohem casteji nez novy level).
const BTN_UNDO := TOOL_COUNT + 3
const BTN_LIST := TOOL_COUNT + 4
const BTN_EXPORT := TOOL_COUNT + 5
const BTN_PLAY := TOOL_COUNT + 6
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
]
const PARAM_COUNT := 4
# PANEL "LEVEL" JE MRIZKA 3 SLOUPCU. Pocet sloupcu je tady, protoze se podle
# nej dorovnava druhy (kratsi) radek prazdnou bunkou.
const PARAM_COLS := 3
const BTN_PARAM_COUNT := PARAM_COUNT * 2

# --- OBSTARANI VYBERU (obdelnikovy tah) ------------------------------------
# Hromadny vyber funguje jako klavesnice: oznacit obdelnikem -> kopirovat ->
# (otocit / zrcadlit) -> vlozit. Jan: "Přidáme možnost prvky označit hromadně
# (pomocí obdélníkového tahu), případně je zkopírovat (přesně v tom formátu jak
# jsou, včetně velikosti, směru, a všech jiných parametrů) a vložit a otočit
# (například když chci udělat dvě protichůdné zrcadlové trasy)."
const BTN_COPY := BTN_PARAM_DOWN + BTN_PARAM_COUNT
const BTN_PASTE := BTN_COPY + 1
# OTOCENI A ZRCADLENI meni KOPII, ne desku: hrac si ji pripravi a teprve pak
# vlozi. Je to jedine poradi, ve kterem se da neco zkusit a vzit zpet.
const BTN_ROT := BTN_COPY + 2
const BTN_FLIP := BTN_COPY + 3
const BTN_DEL_SEL := BTN_COPY + 4
# DELKA HOTOVE CESTY. Je to akce NAD VYBEREM (hrac ma vybrany usek a meni
# ho), tak stoji vedle smazani - ne v palete, kde se jen vybira, cim se kresli.
const BTN_LANE_LONG := BTN_DEL_SEL + 1
const BTN_LANE_SHORT := BTN_LANE_LONG + 1
const BTN_COUNT := BTN_LANE_SHORT + 1

# SIRKA TLACITEK "-"/"+" V PANELU. Jan: "Tlačítka + a - jsou zbytečně velká.
# Tato tlačítka by měla být malá a ideálně přímo nalepená na hodnotu, kterou
# ovládají." Jsou proto pevne siroke (ne vahou zbytku radku), stoji ve skupine
# s hodnotou (bez mezery) a drzi dotykove minimum - mensi uz se prstem mine.
const STEP_W := ScreenLayout.MIN_TOUCH
# PRAZDNE MISTO V MRIZCE PANELU "LEVEL" (dorovnani sloupcu). Druhy radek ma
# jen dve polozky, takze treti bunka se doplni prazdnou - a aby sloupce sedely,
# ma stejnou stavbu jako bunka opravdova (text + dve tlacitka).
const CELL_SPACER := "spacer"

const TOOL_KINDS := [Level.NEUTRAL, Level.START, Level.CIL, Level.VYHYBKA,
	Level.SPOJKA, Level.UZEL, Level.NEUTRAL, Level.NEUTRAL]

# KOLIK UPRAV SE PAMATUJE NA "ZPET". Kazda polozka je kopie levelu (mala
# data), takze se jich par desitek vejde i na telefon.
const UNDO_MAX := 30

enum { MODE_EDIT, MODE_LIST }

var level: Level = null
var tool: int = TOOL_ROAD
var elem: int = Element.FIRE
# VYBRANY USEK. Klepnuti na caru useku (ne na uzel) ho vybere a pak uz
# tlacitko "typ" meni JEHO typ, ne typ dalsi kresby.
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

# --- OBSTARANI VYBERU (obdelnikovy tah, kopie, vlozeni) --------------------
# `sel_box` je obdelnik bunek, ktery hrac obtahl nastrojem "výběr"; prazdny
# obdelnik (size 0) znamena, ze zadny hromadny vyber neni. Drzi se VEDLE
# `sel_lane`/`sel_node`: klepnuti vybira jeden prvek, tah vybira obdelnik -
# a kdyz je obdelnik, jednoprvkovy vyber se uklidi (a naopak).
var sel_box: Rect2i = Rect2i(0, 0, 0, 0)
# PRAVE TAZENY OBDELNIK. Do levelu se nic nezapisuje - je to jen vyber.
var box_active: bool = false
var box_from: Vector2i = Vector2i(-1, -1)
# KOPIE VYBERU. Nese PRESNE to, co v obdelniku bylo: bunky useku (tedy tvar i
# smer), element, pocet mist i druhy prvku. Otoceni a zrcadleni meni ji, ne
# desku - hrac si ji pripravi a teprve pak vlozi.
var clip: Dictionary = {}
# 0..3 = o kolik ctvrttonin se kopie otoci po vlozeni (doprava).
var clip_rot: int = 0
# Zrcadleni se aplikuje PRED otocenim (tak to odpovida tomu, jak se o tom
# mluvi: "zrcadlovou trasu otocim/vlozim").
var clip_flip: bool = false
# VLOZENI SE PRIPRAVUJE: dalsi klepnuti na desku rekne, KAM. Dokud je
# pripravene, kresli se duch kopie - hrac vidi, co a kam polozi.
var paste_armed: bool = false
var paste_cell: Vector2i = Vector2i(-1, -1)

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
	moving = false
	move_node = -1
	move_from = Vector2i(-1, -1)
	move_steps = 0
	# Hromadny vyber i kopie patří k levelu, ktery prave skoncil - novy level
	# zacina s cistym stolem.
	sel_box = Rect2i(0, 0, 0, 0)
	box_active = false
	box_from = Vector2i(-1, -1)
	clip = {}
	clip_rot = 0
	clip_flip = false
	paste_armed = false
	paste_cell = Vector2i(-1, -1)
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
	# Rozpracovany obdelnik i pripravene vlozeni se uklidi: ukazovaly by na
	# stav, ktery uz "zpet" vratil.
	clear_box()
	box_active = false
	paste_armed = false
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
			# NASTROJE A PARAMETRY POD SEBOU. Radek s prvky stoji u pruhu
			# (dole) a parametry nad nim, takze hrac vidi, CIM pracuje i
			# CO tim prave meni (Jan: "Pri oznaceni prvku se musi v panelu
			# nastroju predvyplnit parametry podle vybraneho prvku").
			return [_tools_row(), _lane_params_row(false)]
		PANEL_SEL:
			return _sel_rows()
		PANEL_LEVEL:
			return _level_rows()
	return []


# NASTROJE VE DVOU SKUPINACH, kazdy svou velikosti: "cesta", "guma" a "výběr"
# jsou to, co delam PRSTEM (kreslim, maze se a vybira se tahem), "start/cíl/
# výhybka/spojka/uzel" je to, co POKLADAM klepnutim. Mezi skupinami je prazdne
# misto, aby to nebyl jeden nerozlisitelny pruh obdelniku. Tlacitka maji
# `compact`, takze je rozvrzeni zmiri podle popisku ("cíl" je uzke, "výhybka"
# siroke).
func _tools_row() -> Array:
	var row: Array = []
	for t in [TOOL_ROAD, TOOL_GUMA, TOOL_VYBER]:
		row.append(_tool_item(t))
	row.append({"act": -1, "label": "", "w": 0.5, "on": false, "kind": "spacer"})
	for t in [TOOL_START, TOOL_CIL, TOOL_VYHYBKA, TOOL_SPOJKA, TOOL_UZEL]:
		row.append(_tool_item(t))
	return row


func _tool_item(t: int) -> Dictionary:
	return {"act": t, "label": TOOL_LABELS[t], "w": 1.0, "on": tool == t,
		"kind": "tool", "compact": true}


# PANEL "VYBER". Co se da delat, zavisi na tom, co je oznacene:
#   * obdelnikovy vyber (tah nastrojem "výběr") -> obstarani kopie,
#   * jeden prvek -> jeho druh + smazani,
#   * jeden usek -> element, mista, smazani,
#   * nic -> cim se bude kreslit dalsi cesta.
#
# HODNOTA JE TEXT, TLACITKO JE JEN TO, CO SE MACKA. Hodnota a jeji "-"/"+" stoji
# v JEDNE SKUPINE (bez mezery), takze tlacitka jsou "přímo nalepená na hodnotu"
# (Jan) a maji pevnou, malou sirku - drive to byly dva velke obdelniky.
func _sel_rows() -> Array:
	if has_box():
		return _box_rows()
	if sel_node >= 0 and sel_node < level.node_count():
		return [[
			{"act": BTN_KIND, "label": _kind_label(), "w": 1.8, "on": false, "kind": "action"},
			{"act": BTN_DELETE, "label": "smazat prvek", "w": 1.3, "on": false, "kind": "danger"},
		]]
	return [_lane_params_row(true)]


# RADKY S PARAMETRY USEKU: dnes je to jedina vec - TYP cesty. Mista na bonus
# z panelu zmizela: veze se nestavi na mista na useku, ale do PASU kolem
# cesty (viz `Network.strip_lane`), takze by tlacitko "mista ±" menilo neco,
# co do hry nevstupuje. Tlacitko, ktere nic nedela, je lez.
#
# PREDVYPLNENI PODLE VYBERU: hodnota je z VYBRANEHO USEKU (`panel_element`),
# takze kdyz hrac klikne na ohnivou cestu, stoji v panelu "Oheň" a stisk meni
# PRESNE ten usek. Kdyz neni vybrany zadny usek, je to hodnota, se kterou se
# kresli dalsi cesta.
#
# `include_delete` - tlacitko "smazat úsek" patri do panelu "vyber" (je to
# akce nad vyberem), v panelu "nastroje" by byla jen dalsi nahodna vec
# vedle kreslicich nastroju.
func _lane_params_row(include_delete: bool) -> Array:
	var row: Array = [
		{"act": BTN_ELEM, "label": Level.value_name(panel_element()), "w": 1.0, "on": false,
			"kind": "elem", "compact": true},
	]
	if include_delete and sel_lane >= 0 and sel_lane < level.lane_count():
		row.append({"act": BTN_DELETE, "label": "smazat úsek", "w": 1.3, "on": false, "kind": "danger"})
		# DELKA CESTY. Jan (Oct 2026): "Ještě by to chtělo možnost
		# zvětšovat/zmenšovat existující cesty... abych nemusel vše dokola
		# mazat a znovu vkládat." Uzly se nehybou, meni se jen tvar cesty.
		row.append({"act": BTN_LANE_SHORT, "label": "kratší", "w": 0.8, "on": false})
		row.append({"act": BTN_LANE_LONG, "label": "delší", "w": 0.8, "on": false})
	return row


# PARAMETRY V PANELU SE BEROU Z VYBERU. Kdyz je oznaceny usek, panel stoji
# na JEHO typu a mistech; kdyz neni, jsou to hodnoty, se kterymi se kresli
# dalsi cesta. Klepnuti na "typ" nebo "−"/"+" pak meni to, co je v panelu -
# u vybraneho useku tedy jeho vlastnosti.
#
# Jan: "Kdyz kliknu na ohnivou cestu se 2 upgrade body, tak se musi v panelu
# nastroju vsechny tyto udaje predvyplnit." Driv panel ukazoval hodnoty, se
# kterymi se naposledy KRESLILO, takze u jineho useku lhal.
#
# `elem` a `draw_slots` zustavaji VYCHOZI HODNOTY PRO NOVOU CESTU a vyber je
# NEMENI: kdyby je menil, nakresleni vstupniho useku (kmen) by preplo dalsi
# cestu na kmen a hrac by kreslil neposkozujici pruhy, ani by nevedel proc.
func panel_element() -> int:
	if sel_lane >= 0 and sel_lane < level.lane_count():
		return level.lane_element(sel_lane)
	return elem


# TLACITKO "−"/"+" (KROKOVAC). Vzdy ma pevnou malou sirku a stoji ve skupine
# s hodnotou, kterou ovlada - jedno misto, kde se to rozhoduje, takze se vsechna
# krokovaci v editoru chovaji stejne.
func _step_item(act: int, label: String, group: String) -> Dictionary:
	return {"act": act, "label": label, "w": 1.0, "on": false, "kind": "action",
		"abs_w": STEP_W, "group": group}


# PANEL PRO OBDELNIKOVY VYBER: co se da s hromadnym vyberem delat. Poradi je
# jako u klavesnice (oznacit -> kopirovat -> pripravit -> vlozit) a "smazat
# vyber" je na konci, aby se na nej nedalo klepnout omylem.
func _box_rows() -> Array:
	var row: Array = [
		{"act": BTN_COPY, "label": "kopírovat", "w": 1.0, "on": false, "kind": "action",
			"compact": true},
	]
	if not clip.is_empty():
		row.append({"act": BTN_PASTE, "label": "vložit", "w": 1.0, "on": paste_armed,
			"kind": "action", "compact": true})
		row.append({"act": BTN_ROT, "label": "otoč", "w": 1.0, "on": false, "kind": "action",
			"compact": true})
		row.append({"act": BTN_FLIP, "label": "zrcadli", "w": 1.0, "on": clip_flip,
			"kind": "action", "compact": true})
	row.append({"act": BTN_DEL_SEL, "label": "smazat výběr", "w": 1.0, "on": false,
		"kind": "danger", "compact": true})
	return [row]


# PANEL "LEVEL" JE MRIZKA: kazdy parametr je jedna bunka a bunky maji VSECHNY
# STEJNOU SIRKU (proto `spacer` v druhem radku - prazdne misto, aby sloupce
# sedely a radky nesplyvaly). V bunce je nazev s hodnotou jako TEXT a vedle
# jen dve kompaktni tlacitka "−" a "+": driv mel kazdy parametr dva velke
# obdelniky s napisem "kolo −" a "kolo +", coz bylo na kratky text zbytecne
# siroke a vsechno se tvarilo stejne velke (Jan: "Hodnoty u prvků ohledně
# levelů mohou být daleko úspornější na prostor").
func _level_rows() -> Array:
	var row: Array = _param_row([0, 1, 2])
	return [row, _param_row([3])]


func _param_row(ids: Array) -> Array:
	var row: Array = []
	for p in ids:
		var g: String = "p%d" % int(p)
		row.append({"act": -1, "label": _param_label(p), "w": 1.0, "on": false,
			"kind": "value", "align": "right", "group": g})
		row.append(_step_item(BTN_PARAM_DOWN + int(p) * 2, "−", g))
		row.append(_step_item(BTN_PARAM_DOWN + int(p) * 2 + 1, "+", g))
	# DOROVNANI SLOUPCU. Chybejici bunka se doplni PRAZDNymi polozkami tak,
	# aby mel kazdy radek STEJNY POCET POLOZek i stejny SOUCET VAH - jinak
	# se rozjede jak deleni sirky, tak mezery mezi polozkami a sloupce
	# v obou radcich prestanou sedet (odhalila to az vizualni kontrola).
	# Prazdna bunka ma STEJNOU STAVBU jako opravdova (text + dve tlacitka):
	# jinak by mel druhy radek jiny soucet pevnych sirek a sloupce by ujely.
	var missing: int = PARAM_COLS - ids.size()
	for i in range(missing):
		var g: String = "f%d" % i
		# text, "−", "+" - stejne poradi i stejna pevna sirka jako u opravdove
		# bunky, aby sloupce v obou radcich sedely na pixel.
		row.append({"act": -1, "label": "", "w": 1.0, "on": false,
			"kind": CELL_SPACER, "group": g})
		for k in range(2):
			row.append({"act": -1, "label": "", "w": 1.0, "on": false,
				"kind": CELL_SPACER, "group": g, "abs_w": STEP_W})
	return row


# NAZEV PARAMETRU S HODNOTOU DOHROMADY ("kolo 120 s"). Je to jedna informace
# a jedno misto, kde se sklada - jinak by se nazev a hodnota rozešly.
func _param_label(p: int) -> String:
	var par: Dictionary = PARAMS[p]
	return "%s %s" % [str(par["label"]), _param_text(str(par["key"]))]


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
# Mez je `BTN_PARAM_DOWN + BTN_PARAM_COUNT`: za parametry uz zacinaji tlacitka
# obdelnikoveho vyberu a ta se nesmi plest s krokem parametru.
func is_param_button(b: int) -> bool:
	return b >= BTN_PARAM_DOWN and b < BTN_PARAM_DOWN + BTN_PARAM_COUNT


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


# POPISEK TLACITKA U VYBRANEHO PRVKU. Ukazuje DRUH uzlu, ktery stiskem
# prekaci (start -> cíl -> výhybka -> spojka -> uzel). Tlacitko NIKDY nelze:
# co je na nem napsane, to se stiskem zmeni.
func _kind_label() -> String:
	return "druh: %s" % level.kind_name(level.node_kind(sel_node))


# Je to tlačítko "hrát"? Pruh se kresli z jednoho seznamu a tohle je jedine
# misto, kde se rozhoduje, co se stane po klepnuti.
func is_play(button: int) -> bool:
	return button == BTN_PLAY


# TEXT VYBERU V HORNIM PRUHU. Zacina NASTROJEM: panel se da zavrit a hrac
# musi i tak videt, jestli prave kresli cestu, nebo klade prvek - driv to
# hlidal pruh, kde byly nastroje porad na ocich.
func sel_text() -> String:
	return "%s · %s" % [TOOL_LABELS[tool], _sel_body()]


func _sel_body() -> String:
	if has_box():
		var ln: int = box_lanes().size()
		var nd: int = box_nodes().size()
		var s: String = "výběr %d×%d · %d úseků · %d prvků" % [
			sel_box.size.x, sel_box.size.y, ln, nd]
		if not clip.is_empty():
			var sz: Vector2i = clip_size()
			s += " · kopie %d×%d%s" % [sz.x, sz.y, _clip_turn_text()]
		if paste_armed:
			s += " · klepni, kam vložit (%d,%d)" % [paste_cell.x, paste_cell.y]
		return s
	if sel_node >= 0 and sel_node < level.node_count():
		var ins: int = level.lanes_into(sel_node).size()
		var outs: int = level.lanes_from(sel_node).size()
		return "prvek %d · %s · %d vstupů · %d výstupů (tažením přesuneš, paletou změníš druh)" % [
			sel_node, level.kind_name(level.node_kind(sel_node)), ins, outs]
	if sel_lane >= 0 and sel_lane < level.lane_count():
		return "úsek %d · %s · (úseků %d · uzlů %d)" % [sel_lane,
			level.lane_type_name(sel_lane), level.lane_count(), level.node_count()]
	return "úseků %d · uzlů %d · nové cesty: %s — klepni na úsek nebo na prvek a vybereš ho" % [
		level.lane_count(), level.node_count(), Level.value_name(elem)]


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
	# STARTU MUZE BYT VIC, takze se ptame na DRUH uzlu, ne na "prvni start".
	var from_start: bool = (level.node_kind(a) == Level.START)
	var el: int = Level.KMEN if from_start else draw_elem
	level.lanes.append({"cells": cs, "elem": el, "entry": false,
		"slots": Level.SLOTS})
	sel_lane = level.lane_count() - 1
	sel_node = -1
	_after_change()
	if from_start:
		status = "Úsek %d je vstupní — vede ze startu, proto se kreslí jako kmen. Tlacítkem \"typ\" ho přepneš na element." % level.lane_count()
	elif draw_elem == Level.KMEN:
		status = "Úsek %d je kmen — šedý pás u něj bere všem 100 %%." % level.lane_count()
	elif draw_elem == Level.NEUTRAL:
		status = "Úsek %d je neutrální — šedý pás u něj bere všem 100 %%." % level.lane_count()
	else:
		status = "Úsek %d (%s) přidán." % [level.lane_count(), Level.value_name(draw_elem)]


# OZNACENI PRVKU NEBO USEKU. Vraci true, kdyz neco naslo.
# Uzel ma prednost: je mensi nez usek, ktery pod nim vede, takze klepnuti
# na uzel musi vybrat uzel a ne cestu.
func _select_at(cell: Vector2i) -> bool:
	# VYBER JE VZDY JEN JEDEN: klepnuti uklidi obdelnikovy vyber.
	clear_box()
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
		status = "Vybran úsek %d (%s)." % [sel, level.lane_type_name(sel)]
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
		TOOL_VYBER:
			# Klepnutim se vybira jeden prvek, tahem obdelnik - rozhodne se
			# az pri pusteni prstu (`end_box`).
			begin_box(cell)
		TOOL_GUMA:
			_erase(cell)
		_:
			_place_node(cell, TOOL_KINDS[tool])


func _place_node(cell: Vector2i, kind: int) -> void:
	if kind == Level.NEUTRAL:
		return
	# Položení prvku je jiná práce než hromadný výběr - obdélník se uklidi,
	# aby panel neukazoval tlacitka na vyber, ktery uz neplati.
	clear_box()
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
	clear_box()
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

# Presouvat se da jen nastroji z palety. "cesta" kresli (tah = nova cesta),
# "guma" maze a "výběr" obtahuje obdelnik - u tech trech by tah znamenal neco
# jineho.
func can_move() -> bool:
	return tool != TOOL_ROAD and tool != TOOL_GUMA and tool != TOOL_VYBER


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
# OBDELNIKOVY VYBER, KOPIE A VLOZENI
#
# Jan: "Přidáme možnost prvky označit hromadně (pomocí obdélníkového tahu),
# případně je zkopírovat (přesně v tom formátu jak jsou, včetně velikosti,
# směru, a všech jiných parametrů) a vložit a otočit (například když chci udělat
# dvě protichůdné zrcadlové trasy)."
#
# TAZENIM se obtahne obdelnik, KLEPNUTIM (tah bez pohybu) se vybere jeden
# prvek - stejne jako nastrojem "cesta". Vyber je VZDY jen jeden: bud obdelnik,
# nebo jeden usek/prvek.
# =========================================================================

func has_box() -> bool:
	return sel_box.size.x > 0 and sel_box.size.y > 0


func box_cells() -> Array:
	var out: Array = []
	for r in range(sel_box.position.y, sel_box.end.y):
		for c in range(sel_box.position.x, sel_box.end.x):
			out.append(Vector2i(c, r))
	return out


# USEKY CELE VE VYBERU. Usek, ktery obdelnik jen prekrocil, se nekopiruje:
# z jeho zbytku by vznikla cesta, ktera nezacina ani nekonci v uzlu - a takova
# mapa neplati. Hrac to v hlasce vidi, takze vi, proc je v kopii min useku.
func box_lanes() -> Array:
	var out: Array = []
	if not has_box():
		return out
	for i in range(level.lane_count()):
		var inside := true
		for c in level.lane_cells(i):
			var v: Vector2i = c
			if not _box_has(v):
				inside = false
				break
		if inside:
			out.append(i)
	return out


func box_nodes() -> Array:
	var out: Array = []
	if not has_box():
		return out
	for n in range(level.node_count()):
		if _box_has(level.node_cell(n)):
			out.append(n)
	return out


func _box_has(cell: Vector2i) -> bool:
	if not has_box():
		return false
	return cell.x >= sel_box.position.x and cell.y >= sel_box.position.y \
		and cell.x < sel_box.end.x and cell.y < sel_box.end.y


# ZACATEK TAZENI OBDELNIKU. Klepnuti (tah bez pohybu) se vyhodnoti az pri
# pusteni - jinak by si obe gesta lezla pod rukama.
func begin_box(cell: Vector2i) -> void:
	if not level.in_bounds(cell.x, cell.y):
		return
	box_active = true
	box_from = cell
	sel_box = Rect2i(cell, Vector2i(1, 1))
	sel_lane = -1
	sel_node = -1
	status = "Tažením obtáhni, co chceš vzít. Klepnutím vybereš jeden prvek."


func extend_box(cell: Vector2i) -> void:
	if not box_active:
		return
	var c := Vector2i(clampi(cell.x, 0, level.cols - 1), clampi(cell.y, 0, level.rows - 1))
	var x0: int = mini(box_from.x, c.x)
	var y0: int = mini(box_from.y, c.y)
	var x1: int = maxi(box_from.x, c.x)
	var y1: int = maxi(box_from.y, c.y)
	sel_box = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func end_box() -> void:
	if not box_active:
		return
	box_active = false
	if sel_box.size.x <= 1 and sel_box.size.y <= 1:
		# KLEPNUTI, NE TAH: vybere se jeden prvek (nebo usek) pod prstem.
		sel_box = Rect2i(0, 0, 0, 0)
		_select_at(box_from)
		return
	var ln: int = box_lanes().size()
	var nd: int = box_nodes().size()
	if ln == 0 and nd == 0:
		sel_box = Rect2i(0, 0, 0, 0)
		status = "V obdélníku nic není — obtáhni úseky a prvky."
		return
	status = "Vybráno obdélníkem: %d úseků, %d prvků. Kopíruj nebo smaž." % [ln, nd]


func clear_box() -> void:
	sel_box = Rect2i(0, 0, 0, 0)


# KOPIE VYBERU. Do kopie jdou CELA data useku (bunky = tvar i smer, element,
# pocet mist) i druhy prvku. Neni to "zkopiruj tvar" - je to presna kopie toho,
# co hrac v obdelniku vidi.
func copy_box() -> bool:
	if not has_box():
		status = "Nejdřív obtažením označ, co chceš kopírovat."
		return false
	var lanes: Array = box_lanes()
	var nodes: Array = box_nodes()
	if lanes.is_empty() and nodes.is_empty():
		status = "V obdélníku nic není — není co kopírovat."
		return false
	var w: int = sel_box.size.x
	var h: int = sel_box.size.y
	var ox: int = sel_box.position.x
	var oy: int = sel_box.position.y
	var nlist: Array = []
	for n in nodes:
		var c: Vector2i = level.node_cell(int(n))
		nlist.append({"c": c.x - ox, "r": c.y - oy, "kind": level.node_kind(int(n))})
	var llist: Array = []
	for l in lanes:
		var cells: Array = []
		for cc in level.lane_cells(int(l)):
			var v: Vector2i = cc
			cells.append(Vector2i(v.x - ox, v.y - oy))
		llist.append({"cells": cells, "elem": level.lane_element(int(l)),
			"slots": level.lane_slot_count(int(l))})
	var skipped: int = 0
	for i in range(level.lane_count()):
		if lanes.has(i):
			continue
		for c in level.lane_cells(i):
			var v: Vector2i = c
			if _box_has(v):
				skipped += 1
				break
	clip = {"nodes": nlist, "lanes": llist, "w": w, "h": h, "skipped": skipped}
	clip_rot = 0
	clip_flip = false
	paste_armed = false
	status = "Zkopírováno (%d úseků, %d prvků)." % [llist.size(), nlist.size()]
	if skipped > 0:
		status += " %d úseků je v obdélníku jen částí — ty se nekopírují." % skipped
	return true


# ROZMER KOPIE PO OTOceni A ZRCADLENI. Jedno misto, kde se to pocita - kresleni
# ducha vlozeni, kontrola meze i samotne vlozeni se musi ptat tady, jinak by
# duch ukazoval neco jineho, nez co se opravdu vlozi.
func clip_size() -> Vector2i:
	if clip.is_empty():
		return Vector2i.ZERO
	var w: int = int(clip["w"])
	var h: int = int(clip["h"])
	if clip_rot % 2 == 1:
		return Vector2i(h, w)
	return Vector2i(w, h)


# PREMENA BUNKY KOPIE: nejdriv zrcadleni (vodorovne), pak otoceni po ctvrtinach
# doprava. Vraci bunku v prostoru kopie (od 0,0).
func clip_map(dx: int, dy: int) -> Vector2i:
	var w: int = int(clip["w"])
	var h: int = int(clip["h"])
	var x: int = dx
	var y: int = dy
	if clip_flip:
		x = w - 1 - x
	for i in range(clip_rot % 4):
		var nx: int = h - 1 - y
		var ny: int = x
		x = nx
		y = ny
		var t: int = w
		w = h
		h = t
	return Vector2i(x, y)


# BUNKY KOPIE V PROSTORU DESKY pri vlozeni na `at` (levy horni roh kopie).
# Pouziva je kresleni ducha i vlozeni.
func clip_cells_at(at: Vector2i) -> Array:
	var out: Array = []
	if clip.is_empty():
		return out
	for ln in clip["lanes"]:
		for cc in ln["cells"]:
			var v: Vector2i = cc
			out.append(at + clip_map(v.x, v.y))
	return out


# PRIPRAVA VLOZENI. Kopie se polozi VEDLE vyberu (napravo, pri nedostatku
# misto dolu) - hrac tak hned vidi, kam se chysta, a muze klepnout jinam.
func arm_paste() -> bool:
	if clip.is_empty():
		status = "Není co vložit — nejdřív výběr zkopíruj."
		return false
	var sz: Vector2i = clip_size()
	var at := Vector2i(sel_box.end.x + 1, sel_box.position.y)
	if at.x + sz.x > level.cols:
		at.x = sel_box.position.x
	if at.y + sz.y > level.rows:
		at.y = maxi(level.rows - sz.y, 0)
	at.x = clampi(at.x, 0, maxi(level.cols - sz.x, 0))
	at.y = clampi(at.y, 0, maxi(level.rows - sz.y, 0))
	paste_armed = true
	paste_cell = at
	status = "Klepni na buňku, kam vložit (%d×%d%s). Nebo zmáčkni „vložit“ znovu." % [
		sz.x, sz.y, _clip_turn_text()]
	return true


func _clip_turn_text() -> String:
	var t: String = ""
	if clip_flip:
		t += ", zrcadleno"
	if clip_rot % 4 == 1:
		t += ", otočeno 90°"
	elif clip_rot % 4 == 2:
		t += ", otočeno 180°"
	elif clip_rot % 4 == 3:
		t += ", otočeno 270°"
	return t


# OTOCENI KOPIE O CTVRTTINU DOPRAVA / ZRCADLENI. Meni se KOPIE, ne deska -
# dokud hrac nevlozi, nic se v mape nedeje.
func turn_clip() -> void:
	if clip.is_empty():
		status = "Není co otáčet — nejdřív výběr zkopíruj."
		return
	clip_rot = (clip_rot + 1) % 4
	_seat_paste()
	status = "Kopie je připravená%s (vložit ji můžeš klepnutím na buňku)." % _clip_turn_text()


func flip_clip() -> void:
	if clip.is_empty():
		status = "Není co zrcadlit — nejdřív výběr zkopíruj."
		return
	clip_flip = not clip_flip
	_seat_paste()
	status = "Kopie je připravená%s (vložit ji můžeš klepnutím na buňku)." % _clip_turn_text()


# Změna otoceni muze posunout pripravene misto (kopie ma jiny rozmer) - drzi se
# proto znovu u vyberu, aby duch nevisel nekde v poli.
func _seat_paste() -> void:
	if paste_armed:
		arm_paste()


# VLOZENI NA BUNKU. Vsechna pravidla jsou tady:
#   * kopie se musi vejit do mrizky,
#   * v miste nesmi vest cizi usek (cesty se nekrizi) ani lezet cizi prvek
#     tam, kam pada usek kopie,
#   * prvek kopie, ktery padne NA existujici prvek, se SLOUCI - presne tim se
#     da nova trasa napojit na stavajici sit (dva prvky v jedne bunce by
#     rozbily graf),
#   * a kdyby vlozeni mapu zhorsilo, VZYZKOUSI se (jako kazda chranena zmena).
func paste_at(cell: Vector2i) -> bool:
	if clip.is_empty():
		status = "Není co vložit — nejdřív výběr zkopíruj."
		return false
	var sz: Vector2i = clip_size()
	if cell.x < 0 or cell.y < 0 or cell.x + sz.x > level.cols or cell.y + sz.y > level.rows:
		status = "Sem se kopie nevejde (%d×%d) — klepni blíž ke středu." % [sz.x, sz.y]
		return false
	var moved: Array = box_lanes()
	# KAM VSECHNO PADNE: bunky useku i bunky prvku. Pres ne nesmi vest cizi
	# usek (cesty se nekrizi) a na bunku useku nesmi lezet cizi prvek (rozdělil
	# by vlozenou cestu).
	var inside: Dictionary = {}
	for cc in clip_cells_at(cell):
		var v: Vector2i = cc
		inside[v] = true
	for n in clip["nodes"]:
		var v: Vector2i = cell + clip_map(int(n["c"]), int(n["r"]))
		inside[v] = true
	for v in inside.keys():
		var p: Vector2i = v
		# BUNKA PRVKU JE SPOLECNA: v uzlu se cesty potkavaji, takze vlozena
		# cesta se smi napojit presne na existujici prvek - stejne pravidlo
		# ma i `validate()` (bunku uzlu smi mit vic useku).
		if level.node_at_cell(p) >= 0:
			continue
		for i in range(level.lane_count()):
			if moved.has(i):
				continue
			if _lane_uses_cell(i, p):
				status = "Na %d,%d už vede jiný úsek — vyber jiné místo." % [p.x, p.y]
				return false
	# PRVEK KOPIE NA CIZIM PRVKU SE SLOUCI (dva prvky v jedne bunce by rozbily
	# graf) - a presne tim se da vlozena trasa napojit na stavajici sit.
	var merged: int = 0
	var clip_nodes: Dictionary = {}
	for n in clip["nodes"]:
		var v: Vector2i = cell + clip_map(int(n["c"]), int(n["r"]))
		clip_nodes[v] = true
		if level.node_at_cell(v) >= 0:
			merged += 1
	for cc in clip["lanes"]:
		for q in cc["cells"]:
			var w: Vector2i = q
			var p: Vector2i = cell + clip_map(w.x, w.y)
			if clip_nodes.has(p):
				continue
			if level.node_at_cell(p) >= 0:
				status = "Buňka %d,%d je prvek — úsek kopie se přes něj nesmí položit." % [p.x, p.y]
				return false
	# VLOZENI. Chranena zmena jako kazda jina: je z ni krok "zpet".
	#
	# Vlozeni se NEPOSUZUJE podle `validate()`: hrac si trasu sklada po
	# castech a vlozena cast muze byt zatim nepřipojena (visici vyhybka).
	# Presne proto tu je hlaska - a "zpet" - a ne tiche odmitnuti, ktere by
	# hrace nechalo hádat, proc se nic nestalo (stejne pravidlo jako u zmeny
	# druhu prvku).
	_snapshot()
	var new_box := Rect2i(cell, sz)
	var added_nodes: Array = []
	for n in clip["nodes"]:
		var v: Vector2i = cell + clip_map(int(n["c"]), int(n["r"]))
		if level.node_at_cell(v) >= 0:
			# SLOUCENI: prvek uz tam je, druhy by rozbil graf. Vlozena cesta
			# se tim napoji na stavajici sit.
			continue
		level.nodes.append({"c": v.x, "r": v.y, "kind": int(n["kind"])})
		added_nodes.append(level.node_count() - 1)
	var added_lanes: Array = []
	for ln in clip["lanes"]:
		var cells: Array = []
		for q in ln["cells"]:
			var w: Vector2i = q
			cells.append(cell + clip_map(w.x, w.y))
		level.lanes.append({"cells": cells, "elem": int(ln["elem"]), "entry": false,
			"slots": int(ln["slots"])})
		added_lanes.append(level.lane_count() - 1)
	paste_armed = false
	sel_box = new_box
	clip_rot = 0
	clip_flip = false
	_after_change()
	status = "Vloženo (%d úseků, %d prvků%s)." % [added_lanes.size(), added_nodes.size(),
		(" · %d prvků se sloučilo s existujícími" % merged) if merged > 0 else ""]
	var errs: Array = level.validate()
	if not errs.is_empty():
		status += " Mapa teď neplatí: %s" % errs[0]
	return true


# SMAZAT CELY VYBER. Indexy se uklizi od nejvyssiho - jinak by se pri kazdem
# smazani posunuly a hrac by mazal neco jineho, nez oznacil.
func delete_box() -> void:
	if not has_box():
		status = "Nejdřív obtažením označ, co chceš smazat."
		return
	var lanes: Array = box_lanes()
	var nodes: Array = box_nodes()
	if lanes.is_empty() and nodes.is_empty():
		status = "V obdélníku nic není — není co smazat."
		return
	_snapshot()
	var ls: Array = lanes.duplicate()
	ls.sort()
	ls.reverse()
	for l in ls:
		level.lanes.remove_at(int(l))
	var ns: Array = nodes.duplicate()
	ns.sort()
	ns.reverse()
	for n in ns:
		level.nodes.remove_at(int(n))
	sel_box = Rect2i(0, 0, 0, 0)
	sel_lane = -1
	sel_node = -1
	_after_change()
	status = "Smazáno obdélníkem: %d úseků, %d prvků." % [lanes.size(), nodes.size()]


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
		elif button == TOOL_VYBER:
			status = "Výběr: tažením obtáhni obdélník, klepnutím vybereš jeden prvek. Pak kopíruj, otoč a vlož."
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
		BTN_KIND:
			_kind_press()
		BTN_DELETE:
			_delete_press()
		BTN_COPY:
			copy_box()
		BTN_PASTE:
			_paste_press()
		BTN_ROT:
			turn_clip()
		BTN_FLIP:
			flip_clip()
		BTN_DEL_SEL:
			delete_box()
		BTN_LANE_LONG:
			_lane_len_press(true)
		BTN_LANE_SHORT:
			_lane_len_press(false)
		BTN_UNDO:
			undo()
		BTN_LIST:
			open_list()
		BTN_EXPORT:
			_export()
		BTN_PLAY:
			pass


# "VLOZIT" JE DVOJAK: prvni stisk vlozeni PRIPRAVI (a rekne, kam by padlo),
# druhy stisk vlozi na pripravene misto. Klepnuti na desku vklada hned -
# proto ma hrac obe cesty a nemusi se strefovat do jednoho poradi.
func _paste_press() -> void:
	if clip.is_empty():
		status = "Není co vložit — nejdřív výběr zkopíruj."
		return
	if paste_armed:
		paste_at(paste_cell)
		return
	arm_paste()


# ZIVEL. Kdyz je vybrany usek, meni se TYP TOHO USEKU (zivel, neutralni
# usek, kmen) - presne to, co Janovi chybelo ("upravovat jiz existujici
# zatim nejde"). Bez vyberu to je jen typ, kterym se kresli dalsi cesta.
#
# PLATI I PRO VSTUPNI USEK. Driv se u nej zmena odmitla ("ten neposkozuje,
# at ma na sobe cokoli") - jenze prave proto vypadal jako element a choval
# se jako kmen. Jan: "Melo by byt mozne rucne tuto vstupni cestu take
# prepnout na neco jineho nez kmen, nebo naopak prepnout na kmen."
func _elem_press() -> void:
	# CYKLUS VYCHAZI Z TOHO, CO JE V PANELU (u vybraneho useku z JEHO typu).
	# Kdyby se cyklilo z "kresliciho" typu, prvni stisk by u jineho useku
	# preskocil na hodnotu, ktera s tim, co hrac vidi, nesouvisi.
	var cur: int = panel_element()
	var at: int = TYPE_CYCLE.find(cur)
	var nxt: int = int(TYPE_CYCLE[(at + 1) % TYPE_CYCLE.size()]) if at >= 0 else int(TYPE_CYCLE[0])
	# S VYBRANYM USEKEM SE MENI ON a s nim i to, cim se kresli dal (hrac
	# upravuje typ a chce pokracovat ve stejnem) - jen KRESLENI samo `elem`
	# nikdy nemeni, jinak by nakresleni vstupniho useku preplo dalsi cestu
	# na kmen.
	elem = nxt
	if sel_lane >= 0 and sel_lane < level.lane_count():
		_snapshot()
		level.set_lane_element(sel_lane, nxt)
		_after_change()
		if level.lane_is_entry(sel_lane):
			status = "Vstupní úsek %d je teď %s. Kmen neposkozuje, na elementu se staví." % [sel_lane, Level.value_name(nxt)]
		else:
			status = "Úsek %d je teď %s." % [sel_lane, Level.value_name(nxt)]
		return
	status = "Kreslím typ cesty: %s." % Level.value_name(elem)


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
	return "kolo %s · rychlost %s · životy %s · zlato %s" % [
		_param_text("round_time"), _param_text("speed"), _param_text("lives"),
		_param_text("gold")]


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
#     hrac ho nemusi nikde zapinat a nemuze ho zapomenout prenastavit.
#     STARTU MUZE BYT VIC, takze se znacka "entry" nastavi pro usek z
#     KAZDEHO z nich - driv ji dostal jen usek z prvniho startu.
#   * parametry v panelu se vezmou z vybraneho useku (`panel_element`,
#   * zkontroluje se cela mapa a prvni chyba jde do statusu,
#   * ulozi se. Save tlacitko nema smysl: hrac uklada kazdou zmenu.
# PRODLOUZENI / ZKRATENI VYBRANE CESTY. Uzly (start, vyhybka, spojka, cil)
# se NEHYBOU, meni se jen tvar cesty mezi nimi - hrac tak nemusi cestu smazat
# a nakreslit znovu. Projde to kontrolou mapy jako kazda jina zmena.
func _lane_len_press(grow: bool) -> void:
	if sel_lane < 0 or sel_lane >= level.lane_count():
		status = "Nejdřív klepni na cestu, kterou chceš upravit."
		return
	var pre: Level = level.clone()
	var before: Array = pre.validate()
	var was: int = level.lane_cells(sel_lane).size()
	if not level.bend_lane(sel_lane, grow):
		level = pre
		status = "Cesta se tudy nedá %s — vedle už něco je." % (
			"prodloužit" if grow else "zkrátit")
		return
	var after: Array = level.validate()
	if after.size() > before.size():
		level = pre
		status = after[0]
		return
	_push_state(local_name, pre, sel_lane, sel_node)
	_after_change()
	var now: int = level.lane_cells(sel_lane).size()
	status = "Cesta %d: %d -> %d buněk." % [sel_lane + 1, was, now]


func _after_change() -> void:
	# Vybrany usek i prvek musi po kazde zmene ukazovat na neco, co
	# existuje - po smazani by vyber visel na indexu, ktery uz neni.
	if sel_lane >= level.lane_count():
		sel_lane = -1
	if sel_node >= level.node_count():
		sel_node = -1
	var starts: Array = level.start_nodes()
	for i in range(level.lane_count()):
		var a: int = level.lane_start_node(i)
		level.lanes[i]["entry"] = (a >= 0 and starts.has(a))
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = errs[0]
	level.save()
