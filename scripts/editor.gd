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
	"obdélník"]
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
	"Level: nepřátel = kolik jich posílá 1. vlna · rychlost · životy · zlato · mřížka.",
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
# ODCHOD Z EDITORU. Editor byl jedina obrazovka, ze ktere se hrac nemel jak
# dostat zpet do menu: pruh mel undo, seznam, export a hrat - a nic z toho
# obrazovku neopousti. Je to AKCE (ne tab) a stoji na konci rady, kde ji hrac
# hleda. Osm polozek se do pruhu vejde: na 640x360 zbude 73,6 px na polozku
# a popisky zustanou na 13 px (mereno sondou, 8 polozek vs 7 nic nemeni).
const BTN_MENU := BTN_PLAY + 1
# PARAMETRY LEVELU. Dva za sebou (dolu, nahoru) pro kazdy parametr.
const BTN_PARAM_DOWN := BTN_MENU + 1
# TABULKA PARAMETRU LEVELU je JEDNO misto, kde se o nich vi vsechno: jak se
# jmenuji, jaky je krok a meze. Popisek tlacitka, klepnuti i test se ptaji
# tady - jinak by popisek za chovani zaostal.
# "f" = desetinne cislo, "i" = cele cislo (do levelu se zapisuje jako int).
const PARAMS := [
	{"key": "wave_count", "label": "nepřátel",
		"kind": "i", "step": 1.0, "lo": 2.0, "hi": 40.0},
	{"key": "speed", "label": "rychlost", "kind": "f", "step": 4.0, "lo": 12.0, "hi": 200.0},
	{"key": "lives", "label": "životy", "kind": "i", "step": 2.0, "lo": 1.0, "hi": 99.0},
	{"key": "gold", "label": "zlato", "kind": "i", "step": 20.0, "lo": 0.0, "hi": 2000.0},
	# VELIKOST MRIZKY. Krok 2 od licheho zakladu = pocet zustava LICHY, takze
	# prostredni bunka (kde muze byt start i cil presne ve stredu) existuje
	# porad. Jan: "Grid by měl mít lichý počet řádků ... Ideálně si moci
	# zvolit počet řádků a sloupců v gridu."
	{"key": "cols", "label": "sloupce", "kind": "i", "step": 2.0, "lo": 9.0, "hi": 45.0},
	{"key": "rows", "label": "řádky", "kind": "i", "step": 2.0, "lo": 7.0, "hi": 31.0},
]
# PARAMETRY, KTERE MENI ROZMER MRIZKY. Zmena se ZKOUSI na kopii: zmenseni
# muze nechat prvek mimo mrizku a takova mapa by se uz nedala vyexportovat
# (a hrac by to zjistil az u exportu).
const GRID_KEYS := ["cols", "rows"]
# POCET PARAMETRU. Test hlida, ze sedi s `PARAMS` - kdyby se pridala polozka
# do tabulky a zapomnela tahle konstanta, UI by posledni parametr ztratilo.
const PARAM_COUNT := 6
# PANEL "LEVEL" JE TABULKA: kazda bunka je SLOUPEC POPISKU, SLOUPEC HODNOTY
# a dve tlacitka "−"/"+" - a vsechny tri sloupce maji ve vsech radcich STEJNOU
# sirku, takze hodnoty stoji presne pod sebou. Jan (Oct 2026): "Mělo by to mít
# vše nějaký řád. Řazeno do sloupců a řádků. Ať sloupce a řádky drží stejné
# rozměry pro všechny hodnoty. Například: Zlato | 200g | (-) (+)."
const PARAM_COLS := 2
const BTN_PARAM_COUNT := PARAM_COUNT * 2
# SIRKA SLOUPCE POPISKU (px, nasobi `ui`). Popisek je TEXT, ne tlacitko - nema
# dotykove minimum, jen musi mit vsechny popisky stejne misto, aby hodnoty
# vedle nich zacinay na jednom x.
const CELL_LABEL_W := 84.0
# SIRKA TLACITEK U USEKU ("typ cesty" a "smazat úsek"). Popisek typu se meni
# ("Oheň" je kratke, "neutrální" dlouhe), a kdyz se sirka meri podle popisku,
# tlacitko pri kazdem prepnuti poskoci - a s nim i tlacitko vedle. Jan
# (Oct 2026): "Šířka tlačítek by měla být fixní. Takhle to neustále skáče tam
# a zpět." Proto maji obe PEVNOU sirku, dost velkou na nejdelsi popisek.
const LANE_BTN_W := 132.0

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
const BTN_COUNT := BTN_DEL_SEL + 1

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

enum { MODE_EDIT, MODE_LIST, MODE_NAME }

# --- PREJMENOVANI LEVELU (klavesnice na obrazovce) -------------------------
# Jan (Oct 2026): "Přidáme možnost názvy levelů v seznamu editoru měnit,
# jednotlivé levely mazat, atd."
#
# Text na telefonu neni cim napsat: hra nema zadny textovy vstup (zadne Button
# nody, zadne tema) a nativni klavesku si na webu nevydupeme vsude. Klavesnice
# je proto NAKRESLENA hrou - vzdy stejna, na vsech platformach a da se
# otestovat headless.
#
# ZNAK JE CISLO ZNAKU (kladne), AKCE JSOU ZAPORNE. Jedno misto, kde se
# rozhoduje, co ktera klavesa dela.
const NAME_BACK := -1        # smazat posledni znak
const NAME_CLEAR := -2       # smazat cely nazev
const NAME_OK := -3          # ulozit
const NAME_CANCEL := -4      # zrusit
const NAME_MAX := 18
# Znaky, ktere jdou v nazvu pouzit. Mala pismena, cislice a pomlcka - nazev
# levelu neni veta, je to jmenovka (a velka pismena by na dotykovem displeji
# znamenala druhou rovinu klavesnice).
const NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789-"
const NAME_PER_ROW := 10

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
# JE KOD VYPSANY NA DESCE? Kod se sice kopiruje do schranky, ale ten zapis
# muze prohlizec i system odmitnout - a na telefonu se vypsany radek neda
# oznacit. Kdyz je kod cely na desce, hrac ho vzdycky dostane ven.
var code_show: bool = false
var local_name: String = ""
var mode: int = MODE_EDIT
# PREJMENOVANI: ktery soubor se prejmenovava (`rename_key`) a co je zatim
# napsane (`name_text`). Text se do souboru zapise az stiskem "hotovo" -
# kazdy znak by jinak znamenal prejmenovani souboru.
var rename_key: String = ""
var name_text: String = ""
# SMAZANI NA DVA KLEPNUTI. Soubor je jedina kopie hracovy prace, takze prvni
# klepnuti jen rekne, co se stane; maze se druhe klepnuti na TOTEZ tlacitko.
# Klepnuti jinam cekani zrusi (viz `clear_pending_delete`).
var pending_delete: String = ""
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
# POSUN CELEHO VYBERU: prst polozeny DO hotoveho obdelniku ho bere i s obsahem
# a tahne po bunkach (viz `begin_box_move`). `box_base` je snimek mapy pred
# tahem, ze ktereho se kazda poloha prstu stavi ZNOVU.
var box_move: bool = false
var box_grab: Vector2i = Vector2i(-1, -1)
var box_shape: Rect2i = Rect2i(0, 0, 0, 0)
var box_base: Level = null
var box_shift: Vector2i = Vector2i.ZERO
var box_sel_lanes: Array = []
var box_sel_nodes: Array = []
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
	box_move = false
	box_base = null
	box_shift = Vector2i.ZERO
	box_sel_lanes = []
	box_sel_nodes = []
	clip = {}
	clip_rot = 0
	clip_flip = false
	paste_armed = false
	paste_cell = Vector2i(-1, -1)
	# PRAZDNY LEVEL SE NEUKLADA. Hrac se mohl jen rozmyslet, jestli bude
	# kreslit - a v seznamu by za kazde takove klepnuti zustala prazdna
	# polozka (a pri starsi logice i jmeno te predchozi). Soubor vznikne
	# az s prvni opravdovou zmenou (viz `_after_change`).


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
# JMENO SE NIKDY NEPREVZIMA. Driv se prazdny level jmenoval po tom soucasnem
# ("at po sobe nenecha prazdnou skolku") - jenze pak se v seznamu po klepnuti
# na "novy level" neobjevilo nic noveho a hrac videl "nazev predchoziho
# zustava" (Jan, Oct 2026). Prazdny level si navic soubor vubec nedela
# (viz `reset`), takze se seznam plni jen tim, co ma obsah.
func _free_name() -> String:
	var keys: Array = level.saved_keys()
	var n: int = 1
	while keys.has("level-%d" % n) or ("level-%d" % n) == local_name:
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
	# Cekani na potvrzeni smazani plati jen pro tu navstevu seznamu, ve
	# ktere vzniklo - jinak by druhe klepnuti prislo o minutu pozdeji.
	pending_delete = ""


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
	# Nacteni levelu rusi cekani na smazani: hrac prave dela neco jineho.
	pending_delete = ""
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
# PREJMENOVANI A SMAZANI ULOZENYCH LEVELU
#
# Jan (Oct 2026): "Přidáme možnost názvy levelů v seznamu editoru měnit,
# jednotlivé levely mazat, atd." Obe veci se delaji z RADKU SEZNAMU, kde hrac
# na level vidi - nikam se neodchazi.
# =========================================================================

func is_name() -> bool:
	return mode == MODE_NAME


# KLAVESNICE PRO PREJMENOVANI. Radky jdou shora dolu, kazda polozka je
# {"label", "act"}: `act` >= 0 je znak (jeho kod), zaporna cisla jsou akce.
# Jeden zdroj pro kresleni, klepnuti i rozvrzeni - pocet klaves v radku se
# z toho pocita (`ScreenLayout.name_keys`), takze se klavesnice nemuze
# rozvrstvit jinak, nez vypada.
func name_grid() -> Array:
	var rows: Array = []
	var row: Array = []
	for i in range(NAME_CHARS.length()):
		row.append({"label": NAME_CHARS[i], "act": NAME_CHARS.unicode_at(i)})
		if row.size() >= NAME_PER_ROW:
			rows.append(row)
			row = []
	if not row.is_empty():
		rows.append(row)
	rows.append([
		{"label": "smazat znak", "act": NAME_BACK},
		{"label": "smazat vše", "act": NAME_CLEAR},
		{"label": "hotovo", "act": NAME_OK},
		{"label": "zrušit", "act": NAME_CANCEL},
	])
	return rows


# POCTY KLAVES V RADcICH pro rozvrzeni. Bere se z `name_grid`, aby se obe
# strany nemohly rozejit (klavesa nakreslena jinde, nez kde se macka, je ta
# nejhorsi chyba UI).
func name_row_counts() -> Array:
	var out: Array = []
	for row in name_grid():
		out.append(row.size())
	return out


func begin_rename(key: String) -> void:
	if key.is_empty():
		return
	rename_key = key
	name_text = key
	mode = MODE_NAME
	pending_delete = ""
	status = "Název levelu — piš na klávesnici, pak „hotovo“."


# STISK KLAVESY. Zapisuje se JEN do textu; soubor se prejmenuje az "hotovo".
func name_press(item: Dictionary) -> void:
	var act: int = int(item.get("act", -1))
	if act >= 0:
		if name_text.length() < NAME_MAX:
			name_text += String.chr(act)
		return
	match act:
		NAME_BACK:
			if name_text.length() > 0:
				name_text = name_text.substr(0, name_text.length() - 1)
		NAME_CLEAR:
			name_text = ""
		NAME_OK:
			commit_name()
		NAME_CANCEL:
			close_name()
			status = "Přejmenování zrušeno."


# ULOZENI NOVEHO NAZVU. Je to PRESUN SOUBORU (viz `Level.rename_key`): kdyby
# se jen zapsalo nove jmeno, zustal by v seznamu i stary soubor a hrac by mel
# dve verze te same mapy.
#
# Kdyz je prejmenovavany level prave otevreny, drzi si editor i jeho jmeno -
# jinak by dalsi autosave zapsal praci pod STARYM jmenem a smazany level by
# se vratil zpet.
func commit_name() -> void:
	var want: String = Level.safe_key(name_text)
	if want.is_empty():
		status = "Název nesmí být prázdný."
		return
	if want == rename_key:
		close_name()
		status = "Název zůstal stejný."
		return
	if not Level.rename_key(rename_key, want):
		status = "Název %s už existuje (nebo level zmizel) — vyber jiný." % want
		return
	if local_name == rename_key:
		local_name = want
		if level != null:
			level.name = want
	close_name()
	status = "Přejmenováno: %s → %s." % [rename_key, want]


func close_name() -> void:
	mode = MODE_EDIT
	rename_key = ""
	name_text = ""


# SMAZANI NA DVE KLEPNUTI. Prvni klepnuti rekne, co se stane, druhe maze -
# soubor je jedina kopie hracovy prace a omylem smazany level se neda vratit.
func ask_delete(key: String) -> void:
	if key.is_empty():
		return
	if pending_delete != key:
		pending_delete = key
		status = "Smazat level %s? Klepni na „smazat“ znovu." % key
		return
	pending_delete = ""
	var was_open: bool = key == local_name
	if not Level.delete_key(key):
		status = "Level %s se nepodařilo smazat." % key
		return
	# SMAZANY LEVEL SE NESMI VRATIT AUTOSAVEM. Kdyz ho hrac mel otevreny,
	# drzi ho editor v pameti a dalsi zmena by ho znovu ulozila - takze se
	# z pameti uklidi taky (a "zpet" ho umi vratit, dokud je v historii).
	if was_open:
		reset()
		status = "Level %s smazán (a v editoru je prázdná mřížka)." % key
	else:
		status = "Level %s smazán." % key


func clear_pending_delete() -> void:
	pending_delete = ""


# =========================================================================
# PRUH A PANELY
# =========================================================================

# SPODNI PRUH. Tri taby (oteviraji panel nad pruhem) a pet akci, ktere se
# delaji hned. Kresleni, klepnuti i testy jdou pres tenhle jediny seznam:
# kdyby si kazdy stavil vlastni, tlacitko by bylo jinde, nez se macka.
#
# "menu" stoji na KONCI rady: je to odchod z obrazovky, ne prace s levelem -
# a klepnuti na nej level necha byt (autosave uz probehl pri kazde zmene).
func bar_entries() -> Array:
	return [
		{"tab": PANEL_TOOLS, "act": -1, "label": PANEL_LABELS[0]},
		{"tab": PANEL_SEL, "act": -1, "label": PANEL_LABELS[1]},
		{"tab": PANEL_LEVEL, "act": -1, "label": PANEL_LABELS[2]},
		{"tab": -1, "act": BTN_UNDO, "label": "zpět"},
		{"tab": -1, "act": BTN_LIST, "label": "seznam"},
		{"tab": -1, "act": BTN_EXPORT, "label": "export"},
		{"tab": -1, "act": BTN_PLAY, "label": "hrát"},
		{"tab": -1, "act": BTN_MENU, "label": "menu"},
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
			"kind": "elem", "abs_w": LANE_BTN_W},
	]
	if include_delete:
		row.append(_delete_lane_item())
	# DELKA CESTY SE NEMENI TLACITKY. Jan (Oct 2026): "Nechci měnit velikost
	# pomocí tlačítek. Chci ji měnit tahem prstem." Cesta se tvaruje tahem
	# za ni (viz begin_move / _extend_lane_bump), zadna tlacitka na to nejsou.
	return row


# TLAČITKO "smazat úsek". Stoji VZDY na stejnem miste a ma stejnou pevnou
# sirku; kdyz neni co smazat, je na tom miste jen prazdno se stejnou sirkou -
# jinak by radek poskocil ve chvili, kdy si hrac usek vybere.
func _delete_lane_item() -> Dictionary:
	if sel_lane >= 0 and sel_lane < level.lane_count():
		return {"act": BTN_DELETE, "label": "smazat úsek", "w": 1.0, "on": false,
			"kind": "danger", "abs_w": LANE_BTN_W}
	return {"act": -1, "label": "", "w": 1.0, "on": false, "kind": CELL_SPACER,
		"abs_w": LANE_BTN_W}


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
	var rows: Array = []
	var ids: Array = []
	for p in range(PARAM_COUNT):
		ids.append(p)
		if ids.size() == PARAM_COLS:
			rows.append(_param_row(ids))
			ids = []
	if not ids.is_empty():
		rows.append(_param_row(ids))
	return rows


# JEDEN RADEK TABULKY = PARAM_COLS BUNEK. Chybejici bunka se doplni PRAZDNou
# se STEJNOU stavbou (popisek + hodnota + dve tlacitka) a stejnymi pevnymi
# sirkami - jinak by mel kratsi radek jiny soucet siriek a sloupce by ujely.
func _param_row(ids: Array) -> Array:
	var row: Array = []
	for p in ids:
		row.append_array(_param_cell(int(p)))
	for i in range(PARAM_COLS - ids.size()):
		row.append_array(_param_cell(-1))
	return row


# BUNKA TABULKY: popisek (text, pevna sirka) | hodnota (text, doplni zbytek,
# tiskne se k pravemu okraji) | "−" "+" (pevna mala sirka, nalepena na hodnotu).
func _param_cell(p: int) -> Array:
	var g: String = "p%d" % p
	var label: String = ""
	var value: String = ""
	var kind: String = CELL_SPACER
	if p >= 0:
		label = str(PARAMS[p]["label"])
		value = _param_text(str(PARAMS[p]["key"]))
		kind = "value"
	var out: Array = [
		{"act": -1, "label": label, "w": 1.0, "on": false, "kind": kind,
			"align": "left", "abs_w": CELL_LABEL_W, "cell": g},
		{"act": -1, "label": value, "w": 1.0, "on": false, "kind": kind,
			"align": "right", "group": g, "cell": g},
	]
	if p < 0:
		for k in range(2):
			out.append({"act": -1, "label": "", "w": 1.0, "on": false,
				"kind": CELL_SPACER, "abs_w": STEP_W, "group": g})
	else:
		out.append(_step_item(BTN_PARAM_DOWN + p * 2, "−", g))
		out.append(_step_item(BTN_PARAM_DOWN + p * 2 + 1, "+", g))
	return out


# HODNOTA PARAMETRU jako text (popisek mezi − a +). Cela cisla se kresli bez
# desetinne tecky - jinak by "12.00" nikdo neprecetl.
# POZOR: Godot v `%` formatu NEMA `%g` (spadne to na "unsupported format
# character" a funkce se ukonci - popisek pak zustane syrovy s "%g" v sobe).
func _param_text(key: String) -> String:
	var v: float = float(level.get(key))
	for p in PARAMS:
		if str(p["key"]) == key:
			return str(int(round(v))) if str(p["kind"]) == "i" else _fmt_num(v)
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


# Je to tlacitko "menu"? Plati pro nej to same co pro "hrát": pruh je jeden
# seznam a obrazovku podle nej meni `game_view` - bez toho by se hrac z
# editoru nikdy nedostal zpet (presne to Janovi chybelo).
func is_menu(button: int) -> bool:
	return button == BTN_MENU


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
		if box_shift != Vector2i.ZERO:
			s += " · posun %s" % _shift_text(box_shift)
		return s
	if sel_node >= 0 and sel_node < level.node_count():
		var ins: int = level.lanes_into(sel_node).size()
		var outs: int = level.lanes_from(sel_node).size()
		return "prvek %d · %s · %d vstupů · %d výstupů (tažením přesuneš, paletou změníš druh)" % [
			sel_node, level.kind_name(level.node_kind(sel_node)), ins, outs]
	if sel_lane >= 0 and sel_lane < level.lane_count():
		# PRST TVARUJE CESTU. Jan (Oct 2026): "Stále nám nefunguje upravování
		# cest pomocí tahu prstem... Chtěl bych vybrat jednu cestu a upravit
		# ji." Vyber useku se pozna podle toho, ze je v pruhu napsany - a aby
		# hrac nemusel hádat, ze se da tvarovat, rekne se to rovnou tady.
		# U NASTROJE "VÝBĚR" TO ALE NENI PRAVDA: tam tah obtahne obdelnik.
		# Napoveda, ktera u vyberu slibuje tvarovani, posle hrace hledat
		# funkci, ktera v tom nastroji neexistuje.
		if tool == TOOL_VYBER:
			return "úsek %d · %s — tažením obtáhneš obdélník, tvaruj ho nástrojem „cesta“" % [
				sel_lane, level.lane_type_name(sel_lane)]
		return "úsek %d · %s — tažením prstem ho posuneš, prodloužíš nebo ohneš" % [
			sel_lane, level.lane_type_name(sel_lane)]
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
	# KLEPNUTI DO PRAZDNEHO MISTA VYBER RUSI. Bez toho by se vyber, ktery kryje
	# celou desku, nedal zrusit vubec - mimo nej uz neni kam klepnout
	# (Jan: "vyber teď nelze zrušit").
	sel_lane = -1
	sel_node = -1
	status = "Nic nevybráno — klepni na úsek nebo na prvek."
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

# TAZENIM SE UPRAVUJE. Jen "guma" (tah = mazani) a "cesta" (tah = nova cesta)
# maji tah pro neco jineho; VSECHNO ostatni tazenim upravuje - uzel se presune,
# cesta ohne nebo posune.
#
# Jan (Oct 2026): "Stále nám nefunguje upravování cest pomocí tahu prstem. Tah
# prstem teď dělá rectangle select. Chtěl bych vybrat jednu cestu a upravit ji."
# Tvarovani je na "ceste" a na palete, kde tah nic jineho neznamena; nastroj
# "obdélník" tahá obdelnik (a presun celeho vyberu) - proto se v nem cesta
# nechyta. Kdo si plete nastroje, uvidi v hornim pruhu, ktery prave ma.
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
		# PRST NENI NA UZLU: chytá se CESTA SAMA. Uzel je na telefonu maly
		# cil, cesta je tlustá - a hrac chce tvarovat cestu, ne se strefovat
		# do krouzku.
		return _begin_lane_grab(cell)
	moving = true
	move_node = n
	move_from = cell
	move_steps = 0
	drag_lane = -1
	drag_end = -1
	drag_cell = Vector2i(-1, -1)
	drag_bump = false
	status = "Tažením uzel přesuneš, klepnutím mu změníš druh."
	return true


# Tahnuti na jinou bunku. Uzel jde PO BUNKACH, proto se krokuje - diky tomu
# se nikdy nepreskoci bunka a cesta zustane souvisla.
func extend_move(target: Vector2i) -> bool:
	if not moving:
		return false
	# CHYCENA CESTA UPROSTRED (ne uzel): kus se ohne nebo posune. Chyceny
	# KONEC cesty se naopak hybe jako uzel (niz) - proto se pozna podle
	# `drag_lane`, ne podle `move_node`.
	if drag_lane >= 0 and (drag_end < 0 or move_node < 0):
		if drag_p != Vector2i.ZERO:
			return _extend_lane_run(target)
		return _extend_lane_bump(target)
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
		if drag_lane >= 0:
			# Chyceny KONEC cesty: hrac tvaruje usek, ne uzel - a to i v hlásce.
			status = "Úsek %d · %d buněk." % [drag_lane + 1, level.lane_cells(drag_lane).size()]
		else:
			var at: Vector2i = level.node_cell(move_node)
			status = "Prvek %d přesunut na %d,%d." % [move_node, at.x, at.y]
	return moved


func end_move() -> void:
	if not moving:
		return
	moving = false
	var n: int = move_node
	var from: Vector2i = move_from
	var ln: int = drag_lane
	var held: Vector2i = drag_cell
	move_node = -1
	move_from = Vector2i(-1, -1)
	drag_lane = -1
	drag_end = -1
	drag_cell = Vector2i(-1, -1)
	drag_bump = false
	drag_run_cell = Vector2i(-1, -1)
	drag_p = Vector2i.ZERO
	drag_moved = 0
	drag_d = Vector2i.ZERO
	drag_along = false
	drag_node_start = false
	drag_node_end = false
	drag_snapshot = null
	if move_steps == 0:
		# TAH BEZ POHYBU = KLEPNUTI. U "vyberu" se jen VYBIRA: klepnuti na cestu
		# ji oznaci (a v pruhu se rekne, ze se da tvarovat prstem), neze se
		# po ni obtahne obdelnik a neze se na ni neco polozi.
		if tool == TOOL_VYBER:
			_select_at(held if ln >= 0 else from)
			return
		# U prvku z palety meni druh, presne jak to delalo pred tim, nez se
		# dalo presouvat.
		tap_cell(from)
		return
	_after_change()
	if ln >= 0:
		status = "Úsek %d · %d buněk — tažením prstem ho zkrátíš, prodloužíš nebo ohneš." % [
			ln + 1, level.lane_cells(ln).size()]
		return
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
#
# `skip_lane` = usek, ktery si bunky spočítá sám (posun kusu, ktery uzel veze
# s sebou) - u nej se prepojovani preskoci, jinak by se posunul dvakrat.
# `check` = kontrola mapy na konci. U posunu kusu, kde se hned po uzlu posouva
# jeste druhy uzel (a mezi tim je mapa nutne "rozestavěná"), ji dela az volajici
# pro CELY krok - jinak by se krok spatne vracel zpet.
func _try_move_node(n: int, to: Vector2i, skip_lane: int = -1, check: bool = true) -> bool:
	if not level.in_bounds(to.x, to.y):
		return false
	var other: int = level.node_at_cell(to)
	if other >= 0 and other != n:
		return false
	var from: Vector2i = level.node_cell(n)
	var touching: Array = level.lanes_at(n)
	for item in touching:
		var l: int = int(item)
		if l == skip_lane:
			continue
		# PRES JINOU CESTU UZEL PREJET NESMI - cesty se v tomto modelu nekrizi.
		# CESTY, KTERE SE TOHOTO UZLU DOTYKAJI, SE ALE PRESKAKUJI: vsechny se
		# prepoji na novou polohu uzlu, takze jejich bunky nejsou "cizi".
		# Cilova bunka je casto DRUHA bunka jedne z nich (posun po smeru
		# napojene cesty) - presne to branilo presunu spojky, na ktere visi
		# vic cest. Jan (Oct 2026): "Mělo by být možné chytit například spojku
		# a pohnout s ní i když jsou na ní napojené cesty."
		for j in range(level.lane_count()):
			if touching.has(j):
				continue
			if _lane_uses_cell(j, to):
				return false
	var keep: Level = level.clone()
	level.nodes[n]["c"] = to.x
	level.nodes[n]["r"] = to.y
	for item in touching:
		if int(item) == skip_lane:
			continue
		_reroute_lane(int(item), from, to)
	var before: Array = keep.validate()
	var after: Array = level.validate()
	if check and after.size() > before.size():
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
		# POSUN CELY KUSU DO STRANY (viz _shift_run) - kdyz to nejde, plati
		# puvodni chovani: kus se prodlouzi nebo ohne.
		if _index_of(cs, to) < 0 and _shift_run(lane, cs, false, to - from, to):
			return
		var k: int = _index_of(cs, to)
		if k > 0:
			level.lanes[lane]["cells"] = _slice(cs, k, cs.size())
			return
		var head: Array = [to]
		head.append_array(_route_known(cs[1], to, cs, lane))
		head.append_array(_slice(cs, 1, cs.size()))
		level.lanes[lane]["cells"] = head
		return
	if cs[cs.size() - 1] == from and _index_of(cs, to) < 0 and _shift_run(lane, cs, true, to - from, to):
		return
	var kk: int = _index_of(cs, to)
	if kk >= 0 and kk < cs.size() - 1:
		level.lanes[lane]["cells"] = _slice(cs, 0, kk + 1)
		return
	var tail: Array = _slice(cs, 0, cs.size() - 1)
	tail.append_array(_route_known(cs[cs.size() - 2], to, cs, lane))
	tail.append(to)
	level.lanes[lane]["cells"] = tail


# POSUN CELEHO ROVNEHO KUSU DO STRANY.
# Jan (Oct 2026): "Chci posouvat konce cesty. Jakože celé úseky. Horizontální,
# vertikální. Jako jeden úsek počítám kus po nejbližší rohy, nebo uzly."
#
# Kdyz hrac taha za KONEC cesty do strany, cesta se neohne jen v posledni
# bunce - posune se CELY rovny kus za poslednim rohem (nebo uzlem) o bunku
# vedle a zustane rovny; konec jde s nim.
#
# Na mrizce to jinak nejde: posunuty kus se musi s puvodni cestou nekde
# spojit, takze cesta se o JEDNU bunku prodlouzi (spojka je ta jedna bunka
# u rohu, ktera zustava na miste).
#
# Vraci false, kdyz tah neni do strany (po smeru kusu = prodlouzeni/zkraceni)
# nebo kdyz by posunuty kus prejel neco jineho.
func _shift_run(lane: int, cs: Array, at_end: bool, p: Vector2i, to: Vector2i) -> bool:
	var n: int = cs.size()
	if n < 2 or absi(p.x) + absi(p.y) != 1:
		return false
	var d: Vector2i = (cs[n - 1] - cs[n - 2]) if at_end else (cs[0] - cs[1])
	if absi(d.x) + absi(d.y) != 1:
		return false
	# PO SMERU KUSU se cesta jen prodluzuje nebo zkracuje - to umi puvodni
	# cesta kodu a je to jina operace nez posun.
	if p == d or p == -d:
		return false
	# ROVNY KUS: od konce (nebo od zacatku) se jde, dokud se smer nemeni.
	var a: int = 0
	var b: int = n - 1
	if at_end:
		var k: int = n - 1
		while k > 0 and (cs[k] - cs[k - 1]) == d:
			k -= 1
		a = k
	else:
		var k2: int = 0
		while k2 < n - 1 and (cs[k2 + 1] - cs[k2]) == d:
			k2 += 1
		b = k2
	# JEDNOBUNKOVY "KUS" NENI KUS. Kdyz cesta od uzlu odchazi KOLMO, je rovny
	# usek u uzlu jen ta jedna bunka - a "posun kusu" by z ni udelal okliku
	# pres bunku, kterou uzel prave opousti (a ta casto patri jine napojene
	# ceste, takze by vzniko krizeni). Ohnuti ma na starosti az volajici
	# (`_reroute_lane`), ktery umi vybrat ohyb mimo cizi cesty.
	if (at_end and a >= n - 1) or (not at_end and b <= 0):
		return false
	# SESTAVENI: jedna bunka kusu zustava na miste (spojka u rohu), zbytek
	# kusu se posune. Jinak by cesta nebyla souvisla.
	var out: Array = []
	var added: Array = []
	if at_end:
		out.append_array(_slice(cs, 0, a + 1))
		for k3 in range(a, n):
			var c1: Vector2i = cs[k3] + p
			out.append(c1)
			added.append(c1)
	else:
		for k4 in range(0, b + 1):
			var c2: Vector2i = cs[k4] + p
			out.append(c2)
			added.append(c2)
		out.append_array(_slice(cs, b, n))
	# POSUNUTY KUS NESMI PREJET NIC JINEHO: vlastni cestu, jinou cestu, uzel
	# ani okraj mapy.
	for item in added:
		var c: Vector2i = item
		if not level.in_bounds(c.x, c.y):
			return false
		# CILOVA bunka uz patri PRESUNUTEMU uzlu - `_try_move_node` ji pred
		# tim proveril (nema na ni byt jiny uzel ani cizi cesta).
		if c == to:
			continue
		if level.node_at_cell(c) >= 0:
			return false
		var idx: int = _index_of(cs, c)
		if idx >= 0 and (idx < a or idx > b):
			return false
		for j in range(level.lane_count()):
			if j != lane and _lane_uses_cell(j, c):
				return false
	level.lanes[lane]["cells"] = out
	return true


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


func _route_known(from: Vector2i, to: Vector2i, known: Array, lane: int = -1) -> Array:
	var a: Array = _route_xy(from, to)
	var b: Array = _route_yx(from, to)
	# CESTY SE NESMI KRIZIT, A TO PLATI I PRO SPOJOVACI BUNKY: trasa, ktera by
	# projela cizi cestou, je horsi nez trasa, ktera jen nevyuzije bunky, ktere
	# uz v teto ceste jsou. Bez toho se usek po posunu uzlu "vratil" pres
	# bunku, kterou mezitim zabrala jina cesta - a krok zpet se pak odmitl
	# ("usek 3 se krizi s usekem 2 v bunce 10,5").
	var sa: int = _known_count(a, known) - 100 * _foreign_count(a, lane)
	var sb: int = _known_count(b, known) - 100 * _foreign_count(b, lane)
	if sb > sa:
		return b
	return a


# Kolik bunek trasy lezi na NEJINE ceste (krizeni by vzniklo hned).
func _foreign_count(route: Array, lane: int) -> int:
	var out: int = 0
	for c in route:
		var v: Vector2i = c
		for j in range(level.lane_count()):
			if j == lane:
				continue
			if _lane_uses_cell(j, v):
				out += 1
	return out


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


# USEKY, KTERE OBDELNIK JEN PROTINA. Do kopie ani do smazani nepatri (viz
# `box_lanes`), ale hrac se to MUSI DOZVEDIT: "V obdélníku nic není" u obdelniku,
# ktery pres cesty zretelne vede, je lez a hrac ji vidi jako rozbity vyber.
func box_lanes_cut() -> Array:
	var out: Array = []
	if not has_box():
		return out
	for i in range(level.lane_count()):
		var any: bool = false
		var whole: bool = true
		for c in level.lane_cells(i):
			var v: Vector2i = c
			if _box_has(v):
				any = true
			else:
				whole = false
		if any and not whole:
			out.append(i)
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
		var cut: int = box_lanes_cut().size()
		sel_box = Rect2i(0, 0, 0, 0)
		if cut > 0:
			status = "Obdélník protíná %d úseků, ale ani jeden celý — obtáhni úsek od uzlu k uzlu." % cut
		else:
			status = "V obdélníku nic není — obtáhni úseky a prvky."
		return
	status = "Vybráno obdélníkem: %d úseků, %d prvků. Kopíruj nebo smaž." % [ln, nd]


func clear_box() -> void:
	sel_box = Rect2i(0, 0, 0, 0)
	box_move = false
	box_base = null
	box_shift = Vector2i.ZERO
	box_sel_lanes = []
	box_sel_nodes = []


# =========================================================================
# POSUN CELEHO VYBERU
# =========================================================================
# Jan (Oct 2026): "Ted by jeste melo byt mozne cely vyber uchopit a posunout
# libovolnym smerem." Prst polozeny DO obdelniku bere CELY VYBER - vsechny
# cesty i prvky v nem - a tahne ho po bunkach libovolnym smerem (i diagonalne).
# Prst mimo obdelnik obtahne novy obdelnik.
#
# Kazda poloha prstu se stavi ZNOVU ze snimku (`box_base`), takze tah zpet vraci
# presne puvodni mapu a cely tah je JEDNA polozka "zpet" - stejny vzor jako
# u posunu vystupku. Snimek se uklada pri chyceni, "zpet" se zapise az pri
# pusteni prstu (klepnuti do obdelniku nema co vracet).
func begin_box_move(cell: Vector2i) -> bool:
	if box_move or not has_box() or not _box_has(cell):
		return false
	var ls: Array = box_lanes()
	var ns: Array = box_nodes()
	if ls.is_empty() and ns.is_empty():
		return false
	box_move = true
	box_grab = cell
	box_shape = sel_box
	box_base = level.clone()
	box_shift = Vector2i.ZERO
	box_sel_lanes = ls
	box_sel_nodes = ns
	status = "Tažením posuneš celý výběr — libovolným směrem."
	return true


# TAH: cely vyber jede s prstem. Posun se KLAMPUJE, aby vsechno zustalo v mrizce -
# cesta vyjeta z mrizky by spadla na `validate()` a hrac by videl, ze "se nedeje
# nic", presne tu chybu, kterou tu resime u kazdeho gesta.
func extend_box_move(target: Vector2i) -> bool:
	if not box_move:
		return false
	var want: Vector2i = _box_shift_limit(target - box_grab)
	if want == box_shift:
		return false
	box_shift = want
	level = box_base.clone()
	level.shift_cells(box_sel_lanes, box_sel_nodes, want)
	sel_box = Rect2i(box_shape.position + want, box_shape.size)
	# VSTUPNI USEKY SE MUSI PREPOCITAT UZ BEHEM TAHU: posun muze odtahnout START
	# a usek, ktery z nej vedl, se pak kresli jako poskozujici pruh, i kdyz
	# vstupni je. Ukladani na disk patri az do `end_box_move`.
	_refresh_entry_flags()
	var errs: Array = level.validate()
	if errs.is_empty():
		status = "Výběr posunut: %s." % _shift_text(want)
	else:
		status = "Výběr posunut: %s — mapa teď neplatí: %s" % [_shift_text(want), errs[0]]
	return true


func end_box_move() -> void:
	if not box_move:
		return
	var moved: Vector2i = box_shift
	var at: Vector2i = box_grab
	box_move = false
	if moved == Vector2i.ZERO:
		# TAH BEZ POHYBU = KLEPNUTI, ne posun. Klepnuti znamena "vyber, co je pod
		# prstem" - a kdyz je pod prstem prazdno, vyber se ZRUSI. Bez toho by
		# vyber, ktery kryje celou desku, nesel zrusit vubec: mimo obdelnik uz
		# neni kam klepnout (Jan: "vyber teď nelze zrušit").
		clear_box()
		_select_at(at)
		_after_change()
		return
	# CELY tah je jedna polozka "zpet": do historie jde mapa pred tahem.
	_push_state(local_name, box_base, sel_lane, sel_node)
	_after_change()
	status = "Výběr posunut: %s." % _shift_text(moved)
	box_base = null
	box_shift = Vector2i.ZERO
	box_sel_lanes = []
	box_sel_nodes = []


# MEZE POSUNU: pres ne by vyber vyjel z mrizky. Pocita se ze SNIMKU (nikdy
# z posunute mapy), takze kazda poloha prstu dava stejny vysledek a tah zpet
# vraci presne puvodni bunky.
func _box_shift_limit(want: Vector2i) -> Vector2i:
	var base: Level = box_base
	if base == null:
		return Vector2i.ZERO
	var mn := Vector2i(1000000, 1000000)
	var mx := Vector2i(-1000000, -1000000)
	var any: bool = false
	for i in box_sel_lanes:
		for c in base.lane_cells(int(i)):
			var v: Vector2i = c
			mn.x = mini(mn.x, v.x)
			mn.y = mini(mn.y, v.y)
			mx.x = maxi(mx.x, v.x)
			mx.y = maxi(mx.y, v.y)
			any = true
	for n in box_sel_nodes:
		var vn: Vector2i = base.node_cell(int(n))
		mn.x = mini(mn.x, vn.x)
		mn.y = mini(mn.y, vn.y)
		mx.x = maxi(mx.x, vn.x)
		mx.y = maxi(mx.y, vn.y)
		any = true
	if not any:
		return Vector2i.ZERO
	return Vector2i(
		clampi(want.x, -mn.x, level.cols - 1 - mx.x),
		clampi(want.y, -mn.y, level.rows - 1 - mx.y))


# POSUN SE PISE RUCNE: Godot v `%` nema "%+d" (spadlo by to stejne jako "%g") a
# "o 2,-1 bunek" bez znamenka se cte spatne - u posunu je smer to hlavni.
func _shift_text(v: Vector2i) -> String:
	var sx: String = ("+%d" % v.x) if v.x > 0 else str(v.x)
	var sy: String = ("+%d" % v.y) if v.y > 0 else str(v.y)
	return "%s,%s buněk" % [sx, sy]


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
		# VOLBA NASTROJE JE VOLBA MODU, NE UPRAVA LEVELU - a panel stoji NAD
		# deskou, takze by hrac prvni tah na desku "obetoval" na jeho zavreni
		# (klepnuti na desku s otevrenym panelem panel jen zavre). Zmereno na
		# 932x430 pres game_view: zvolil "výběr", obtahl obdelnik a nestalo se
		# NIC - teprve druhy tah vybral. Presne tak vypada "rectangle select
		# nefunguje".
		close_panel()
		if button == TOOL_GUMA:
			status = "Guma: klepni na prvek nebo na cestu."
		elif button == TOOL_ROAD:
			status = "Tažením prstu kresli cestu (%s). Klepnutím úsek nebo prvek vybereš." \
				% Level.value_name(elem)
		elif button == TOOL_VYBER:
			status = "Obdélník: tažením obtáhni výběr, klepnutím vybereš jeden prvek. Cesty tvaruj nástrojem „cesta“."
		else:
			status = "Klepni, kam má %s přijít. Tažením z prvku ho přesuneš, tažením po cestě ji ohneš." \
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
		BTN_UNDO:
			undo()
		BTN_LIST:
			open_list()
		BTN_EXPORT:
			_export()
		BTN_PLAY:
			pass
		BTN_MENU:
			# ODCHOD Z EDITORU neni uprava levelu: obrazovku prepina
			# `game_view` (stejne jako u "hrát"), editor o nem vi jen tolik,
			# ze to je jeho tlacitko (`is_menu`). Level zustava, jak je -
			# autosave probehl pri kazde zmene.
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
	# ZMENA VELIKOSTI MRIZKY SE ZKOUSI NA KOPII. Zmenseni muze nechat prvek
	# mimo mrizku, a takova mapa se neda vyexportovat - hrac by to zjistil
	# az u exportu, kde uz je pozde. Jine parametry (cas kola, zlato...) mapu
	# nerozbiji, takze se zkousi jen tyhle.
	var trial: Level = level.clone()
	if str(par["kind"]) == "i":
		trial.set(key, int(nv))
	else:
		trial.set(key, nv)
	if GRID_KEYS.has(key):
		var errs: Array = trial.validate()
		if errs.size() > level.validate().size():
			var why: String = str(errs[0]) if not errs.is_empty() else "mapa by přestala platit"
			status = "Mřížku takto změnit nejde — %s" % why
			return
	_snapshot()
	level = trial
	_after_change()
	status = "Level: %s" % _level_text()


# VSE, CO SE V PANELU "LEVEL" DA NASTAVIT - jedna hlaska, aby hrac videl
# souvislosti (a aby se hodnoty nemusely cist z peti tlacitek).
func _level_text() -> String:
	return "nepřátel %s · rychlost %s · životy %s · zlato %s · mřížka %s×%s" % [
		_param_text("wave_count"), _param_text("speed"), _param_text("lives"),
		_param_text("gold"), _param_text("cols"), _param_text("rows")]


# EXPORT. Kod levelu se nejen vypise nad pruhem, ale ROVNOU SE ZKOPIRUJE do
# schranky: vypsany radek se na telefonu neda oznacit, takze hrac nemel jak
# kod dostat ven. Jan: "kod se sice zobrazí, ale nedá se zkopírovat".
# Vypis nad pruhem zustava jako druha sance, kdyz zapis do schranky prohlizec
# odmitne (a hrac to v hlasce vidi).
func _export() -> void:
	code = level.to_code()
	# KOD SE VZDY VYPISE NA DESKU. Zapis do schranky umi selhat - prohlizec
	# ho odmitne, system vraci jiny text, na telefonu se vypsany radek neda
	# oznacit. Kdyz je kod na desce cely a citelny, hrac ho vzdy dostane ven
	# (precte ho nebo vyfoti), at se schranka zachova jakkoli.
	code_show = true
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = "Mapa má chybu: %s (kód je na desce)" % errs[0]
		return
	if Clipboard.copy(code):
		status = "Kód (%d znaků) je ve schránce — vlož ho jako text." % code.length()
	else:
		status = "Kód (%d znaků) se nepodařilo zkopírovat — je vypsaný na desce, přečti ho odtud." % code.length()


# KOD JE VYPSANY NA DESCE, dokud ho hrac nezavre. Klepnuti kamkoli ho zavre.
func close_code() -> void:
	code_show = false


# ZALOMENI KODU NA RADKY. Kod levelu je jedno dlouhe slovo (bez mezer), takze
# se lama PO ZNACICH - `Guide.caption` (po slovech) by vratil jeden radek pres
# cely displej. Kolik znaku se vejde, se pocita ze sirky jednoho znaku: merit
# cely radek pro kazdy znak znovu by bylo mereni stokrát za snimek.
static func code_lines(font: Font, px: int, max_w: float, text: String) -> Array:
	var per: int = code_chars_per_line(font, px, max_w)
	var out: Array = []
	if per <= 0:
		return out
	var i: int = 0
	while i < text.length():
		out.append(text.substr(i, per))
		i += per
	return out


# Kolik znaku se vejde na jeden radek pri velikosti pisma `px`.
static func code_chars_per_line(font: Font, px: int, max_w: float) -> int:
	if px <= 0:
		return 0
	var one: float = font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if one <= 0.0:
		return 0
	return maxi(int(max_w / one), 1)


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
# =========================================================================
# TVAROVANI CESTY PRSTEM (bez tlacitek)
# =========================================================================

# Jan (Oct 2026): "Nechci měnit velikost pomocí tlačítek. Chci ji měnit tahem
# prstem." Cesta se chytá PRSTEM ZA SEBE SAMA:
#   * u kraje cesty se chyti jeji KONEC (uzel na tom konci) - tahem po smeru
#     se cesta prodlouzi nebo zkrati, tahem do strany se cely rovny kus
#     posune (viz `_shift_run`);
#   * na ROVNEM KUSE UPROSTRED ("vystupek") se chyti TEN KUS a tahem do strany
#     se cely posune - bocni strany se pritom natahnou (viz `Level.shift_run`);
#   * na obycejnem rovnem kuse se tahem do strany kus ohne (vybouleni).
# Uzel je na telefonu maly cil, cesta je tlustá - proto se da chytit cesta.
var drag_lane: int = -1
# Ktery konec cesty se chytil: 0 = u startu, 1 = u cile, -1 = kus uprostred.
var drag_end: int = -1
# Bunka, za kterou hrac cestu chytil (podle ni se ohne ten spravny kus).
var drag_cell: Vector2i = Vector2i(-1, -1)
# Je kus uz ohne­ty? Tah zpet ho srovna.
var drag_bump: bool = false
# ROVNY KUS ("vystupek"): bunka kusu, pod kterou prst lezi (hybe se s kusem),
# smer, kterym se kus posouva ven z tvaru, a o kolik bunek uz se posunul.
# Prazdny smer = kus se nenasel (chytil se obycejny rovny kus - ohne se).
var drag_run_cell: Vector2i = Vector2i(-1, -1)
var drag_p: Vector2i = Vector2i.ZERO
var drag_moved: int = 0
# Smer sameho kusu - podle nej se vrsek rozsiruje a zuzuje (tah PODEL kusu).
var drag_d: Vector2i = Vector2i.ZERO
# Taha se po ose kusu (sirka), nebo kolmo na ni (vyska)?
var drag_along: bool = false
# Koncil kus pri chyceni v UZLU? Jen takovy kus smi uzel posunout - kus, ktery
# se pri tahu zplostil, by se jinak zacal "vozit" po mape.
var drag_node_start: bool = false
var drag_node_end: bool = false
# CELY LEVEL PRI CHYCENI. Kazda poloha prstu se stavi ZNOVU z nej - jen tak tah
# zpet vrati presne puvodni tvar (a zplosteni jde zase zvednout).
var drag_snapshot: Level = null


# CESTA POD PRSTEM SE CHYTA A TAHNE. Je to JEDNO misto, kde se rozhoduje, ze
# hrac vzal do ruky CESTU (a tvaruje ji) - plati pro "cestu" a paletu. Nastroj
# "obdélník" ji NECHYTA: tam tah znamena obdelnik (a posun celeho vyberu), takze
# by se cestu upravit nedalo - a prave to Jan popsal jako "stale funguje jen
# rectangle select".
#
# Jan (Oct 2026): "Stále nám nefunguje upravování cest pomocí tahu prstem. Tah
# prstem teď dělá rectangle select. Chtěl bych vybrat jednu cestu a upravit ji."
#
# UZEL MA PREDNOST: klepnuti na uzel kresli novou cestu (nastrojem "cesta"),
# klade prvek (paleta) nebo prvek presouva. Teprve kdyz pod prstem uzel neni
# a je tam cesta, chyta se cesta.
func begin_lane_drag(cell: Vector2i) -> bool:
	if tool == TOOL_GUMA or moving:
		return false
	if level.node_at_cell(cell) >= 0:
		return false
	return _begin_lane_grab(cell)


func _begin_lane_grab(cell: Vector2i) -> bool:
	# NASTROJ "VÝBĚR" NECHYTÁ CESTU. Jeho gestem je obdelnik a ten se musi dat
	# spustit KDEKOLI - i pres cestu a v jejim sousedstvi, protoze prave tam
	# hrac obtahuje to, co chce vzit. Dokud cesta vyhravala, prst kousek od
	# cesty, prst obtahnul obdelnik jen na 42 % mrizky (mereno na zakladni desce)
	# jinde se cestou nechtene posunulo - presne to bylo "rectangle select
	# zase nefunguje". Tvarovani cesty je na "cesta" a na palete.
	if tool == TOOL_VYBER:
		return false
	var hit: Array = _lane_grab(cell)
	if hit.is_empty():
		return false
	var lane: int = int(hit[0])
	var on: Vector2i = hit[1]
	var cs: Array = level.lane_cells(lane)
	if cs.size() < 2:
		return false
	var at: int = _index_of(cs, on)
	if at < 0:
		return false
	moving = true
	move_node = -1
	move_from = cell
	move_steps = 0
	drag_lane = lane
	drag_cell = on
	drag_bump = false
	drag_end = -1
	drag_node_start = false
	drag_node_end = false
	drag_snapshot = null
	drag_along = false
	drag_moved = 0
	drag_run_cell = Vector2i(-1, -1)
	drag_p = Vector2i.ZERO
	drag_moved = 0
	# ROVNY KUS ("vystupek" i cela rovna cara) MA PREDNOST: hybe se CELY KUS.
	# Kdyz kus konci v uzlu, posune se i ten uzel - takze se da hýbat celou
	# rovnou carou (Jan: "Posouvání celých úseku teď funguje maximálně o 2
	# pozice. Bylo by fajn, kdyby s tím šlo hýbat neomezeně.").
	var pc: Dictionary = level.piece_at(lane, on)
	if not pc.is_empty():
		drag_run_cell = on
		drag_d = pc["d"]
		# Kolma osa tahu ("vyska"): smer urcuje TVAR, znamenko dava prst.
		drag_p = Vector2i(-drag_d.y, drag_d.x)
		drag_node_start = (int(pc["a"]) == 0)
		drag_node_end = (int(pc["b"]) == cs.size() - 1)
		drag_along = false
		drag_snapshot = level.clone()
		status = "Tažením kusu ho posuneš, rozšíříš nebo zúžíš — strany se hýbou s ním."
		return true
	# Dve krajni bunky = konec cesty, zbytek = kus uprostred.
	if at <= 1:
		move_node = level.lane_start_node(lane)
		if move_node >= 0:
			drag_end = 0
	elif at >= cs.size() - 2:
		move_node = level.lane_end_node(lane)
		if move_node >= 0:
			drag_end = 1
	if drag_end >= 0:
		status = "Tažením za cestu posuneš její konec (a rovný kus s ním)."
	else:
		status = "Tažením za kus cesty ho ohneš, tahem zpet srovnáš."
	return true


# KTERA CESTA JE POD PRSTEM. Vraci [cislo cesty, bunka cesty], nebo prazdny
# seznam. Presna bunka se zkousi prvni - v uzlu se cesty potkavaji, ale uzel se
# chyta jako uzel (viz begin_move).
#
# U NASTROJE "CESTA" se zkousi i ctyri sousedni bunky: prst neni mys a cesta je
# na obrazovce jen tenká cara, takze hrac jinak cestu netrefi. Prave tam nema
# chytnuti cesty zadny jiny vyznam: nova cesta MUSI zacit v uzlu, takze tah z
# prostredku cesty by skoncil jen hlasenim. U PALETY se vedle NEHLEDA - tam hrac
# KLADE prvek a polozit vyhybku vedle cesty je bezna prace; s toleranci by prst
# chytil cestu misto položení a mapa by se nedala stavet.
func _lane_grab(cell: Vector2i) -> Array:
	for j in range(level.lane_count()):
		if _lane_uses_cell(j, cell):
			return [j, cell]
	if tool != TOOL_ROAD:
		return []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = cell + d
		if not level.in_bounds(c.x, c.y):
			continue
		for j in range(level.lane_count()):
			if _lane_uses_cell(j, c):
				return [j, c]
	return []


# SMER ROVNEHO KUSU V TÉ BUNCE. Bunky jsou sousedni, takze je to jednotkovy
# vektor; u rohu se vezme prvni rameno.
func _piece_dir(cs: Array, cell: Vector2i) -> Vector2i:
	for i in range(cs.size() - 1):
		var a: Vector2i = cs[i]
		var b: Vector2i = cs[i + 1]
		if b == a:
			continue
		if a == cell or b == cell:
			return b - a
	return Vector2i.ZERO


# TAH ZA KUS CESTY UPROSTRED: prst do strany kus ohne (o dve bunky), prst
# zpet na puvodni misto ho zase srovna. Jeden krok tahu = jedna zmena, aby
# se to dalo vzit zpet jedinym "zpet".
func _extend_lane_bump(target: Vector2i) -> bool:
	if drag_lane < 0 or drag_lane >= level.lane_count():
		return false
	var cs: Array = level.lane_cells(drag_lane)
	var d: Vector2i = _piece_dir(cs, drag_cell)
	if d == Vector2i.ZERO:
		return false
	var p: Vector2i = Vector2i(-d.y, d.x)
	# Vector2i `dot()` nema - pocita se rucne (je to jen skalarni soucin).
	var off: int = (target.x - drag_cell.x) * p.x + (target.y - drag_cell.y) * p.y
	var pre: Level = null
	if move_steps == 0:
		pre = level.clone()
	var changed: bool = false
	if off != 0 and not drag_bump:
		changed = level.bend_lane(drag_lane, true, drag_cell)
		if changed:
			drag_bump = true
	elif off == 0 and drag_bump:
		changed = level.bend_lane(drag_lane, false, drag_cell)
		if changed:
			drag_bump = false
	if changed:
		move_steps += 1
		if pre != null:
			_push_state(local_name, pre, sel_lane, sel_node)
		status = "Kus cesty ohnutý." if drag_bump else "Kus cesty srovnaný."
	return changed


# TAH ZA ROVNY KUS: dve osy tahu, obe se pocitaji z TVARU kusu (`drag_d` =
# smer kusu, `drag_p` = kolma osa):
#   * KOLMO na kus = VYSKA: cely kus se posune o tolik bunek, o kolik prst
#     odesel; bocni strany se natahnou nebo zkrati (a kus, ktery konci v uzlu,
#     posune i ten uzel - cela rovna cara se tak da hýbat neomezeně).
#   * PODEL kusu = SIRKA: vrsek se rozsiri/zuzi, a kdyz kus konci v uzlu,
#     posune se ten uzel po sve ose (cara se prodlouzi nebo zkrati).
#
# KAZDA POLOHA PRSTU SE STAVI ZNOVU ZE SNIMKU (`drag_snapshot`): tah zpet vrati
# presne puvodni tvar, zplosteni jde zase zvednout a krok se nikdy nepreskoci.
# Cely tah = jedna polozka "zpet".
func _extend_lane_run(target: Vector2i) -> bool:
	if drag_lane < 0 or drag_lane >= level.lane_count() or drag_snapshot == null:
		return false
	var p: Vector2i = drag_p
	if p == Vector2i.ZERO:
		return false
	var dx: int = target.x - drag_cell.x
	var dy: int = target.y - drag_cell.y
	var along: int = dx * drag_d.x + dy * drag_d.y
	var perp: int = dx * p.x + dy * p.y
	# KTERA OSA: rozhoduje vetsi odchylka, pri stejne vyhrava vyska (prst nikdy
	# nejde presne po ose a tvar se tak nepreklapi).
	var width: bool = absi(along) > absi(perp)
	var want: int = along if width else perp
	if want == drag_moved and width == drag_along:
		return false
	level = drag_snapshot.clone()
	var cell: Vector2i = drag_run_cell
	var moved: int = 0
	while moved != want:
		var step: int = 1 if want > moved else -1
		var before: Level = level.clone()
		var ok: bool = _piece_step(width, step, cell)
		if not ok:
			level = before
			break
		var errs: Array = level.validate()
		if errs.size() > before.validate().size():
			# Krok neco rozbil (mapa prisla o to, co platilo) - koncime.
			level = before
			break
		if width:
			if not level.lane_cells(drag_lane).has(cell):
				# Zuzovani vzalo bunku, kterou prst drzi - drzi se sousedni.
				cell += drag_d
			else:
				cell += drag_d * step
		else:
			# Kus se posunul s prstem - chycena bunka jde s nim.
			cell += p * step
		moved += step
	if moved == drag_moved and width == drag_along:
		return false
	var pre: Level = null
	if move_steps == 0:
		pre = drag_snapshot.clone()
	level.lanes[drag_lane]["cells"] = level.lane_cells(drag_lane)
	drag_moved = moved
	drag_along = width
	move_steps += 1
	if pre != null:
		_push_state(local_name, pre, sel_lane, sel_node)
	var cs: Array = level.lane_cells(drag_lane)
	if drag_moved == 0:
		status = "Úsek %d zpět na původní tvar (%d buněk)." % [drag_lane + 1, cs.size()]
	elif width:
		status = "%s o %d %s · úsek %d má %d buněk." % [
			"Vršek rozšířený" if drag_moved > 0 else "Vršek zúžený",
			absi(drag_moved), "buňku" if absi(drag_moved) == 1 else "buňky",
			drag_lane + 1, cs.size()]
	else:
		status = "%s o %d %s · úsek %d má %d buněk." % [
			"Kus posunutý" if drag_moved > 0 else "Kus posunutý zpět",
			absi(drag_moved), "buňku" if absi(drag_moved) == 1 else "buňky",
			drag_lane + 1, cs.size()]
	return true


# JEDEN KROK TAHU ZA KUS. Pracuje se na `level` - volajici si pred krokem dela
# kopii a pri selhani ji vrati (a uzel se posouva pres `_try_move_node`, ktery
# hlida i to, co je na uzel napojene).
func _piece_step(width: bool, step: int, cell: Vector2i) -> bool:
	if width:
		var side: int = 1 if step > 0 else -1
		var at_node: bool = (side > 0 and drag_node_end) or (side < 0 and drag_node_start)
		if at_node:
			# Uzel na tom konci se posune PO OSE kusu - cara se prodlouzi nebo
			# zkrati. Naseho useku se to tyka taky, takze se nepreskakuje.
			var ni: int = level.lane_end_node(drag_lane) if side > 0 else level.lane_start_node(drag_lane)
			if ni < 0:
				return false
			return _try_move_node(ni, level.node_cell(ni) + drag_d * step)
		# PRST TAHNE PO OSE KUSU, ALE NA JEHO KONCI V TOM SMERU UZEL NENI (je
		# tam roh, za kterym cesta pokracuje). Nejdric se zkusi rozsireni vrsku
		# (vystupek ma vlastni operaci) a kdyz to nejde, hybe se VOLNY KONEC
		# CELE CESTY - cesta se prodlouzi (tah ven), nebo zkrati (tah zpet).
		# Driv se tu delalo jen rozsireni, takze u kazde cesty, ktera ma na
		# konci kusu roh a ne uzel, se NEDELO NIC - presne to Jan popsal jako
		# "chytit existujici usek a prodlouzit ho nebo zkratit".
		if level.widen_run(drag_lane, cell, side, step > 0):
			return true
		# KTERY KONEC: dopredu se prodluzuje KONEC cesty, dozadu se bud vraci
		# ZACATEK (kdyz kus zacina na zacatku cesty), nebo se konec cesty
		# stahuje zpet - to je zkraceni.
		var free_i: int = level.lane_start_node(drag_lane) if (side < 0 and drag_node_start) \
			else level.lane_end_node(drag_lane)
		if free_i < 0:
			return false
		return _try_move_node(free_i, level.node_cell(free_i) + drag_d * step)
	# VYSKA
	var res: Dictionary = level.move_piece(drag_lane, cell, drag_p * step, drag_d)
	if not bool(res.get("ok", false)):
		return false
	for item in res["nodes"]:
		var ni2: int = int(item["i"])
		# UZEL SE POSOUVA JEN KDYZ UZ TAM BYL PRI CHYCENI - jinak by se kus,
		# ktery se prave zplostil, zacal "vozit" po mape.
		if ni2 == level.lane_start_node(drag_lane) and not drag_node_start:
			return false
		if ni2 == level.lane_end_node(drag_lane) and not drag_node_end:
			return false
	# NASE BUNKY SE PREPISOU PRVNI, teprve pak se posune uzel: kdyz se uzel
	# posune driv, kontrola mapy vidi cestu, ktera na uzel jeste nesedi (a krok
	# se zbytecne vrati zpet). Naseho useku se pri prestěhování uzlu
	# neprepojuje - bunky si pise tenhle krok sam, jinak by se kus posunul
	# dvakrat.
	level.lanes[drag_lane]["cells"] = res["cells"]
	for item2 in res["nodes"]:
		if not _try_move_node(int(item2["i"]), item2["to"], drag_lane, false):
			return false
	return true


#   * zkontroluje se cela mapa a prvni chyba jde do statusu,
#   * ulozi se. Save tlacitko nema smysl: hrac uklada kazdou zmenu.
func _after_change() -> void:
	# Vybrany usek i prvek musi po kazde zmene ukazovat na neco, co
	# existuje - po smazani by vyber visel na indexu, ktery uz neni.
	if sel_lane >= level.lane_count():
		sel_lane = -1
	if sel_node >= level.node_count():
		sel_node = -1
	_refresh_entry_flags()
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = errs[0]
	level.save()


# PRIZNAK "VSTUPNI USEK" JE ODVOZENY Z GRAFU (kdo vede ze STARTU), takze se musi
# prepsat po kazde zmene, ktera muze pohnout se startem nebo s usekem. Je to
# zvlast a bez ukladani na disk: posun celeho vyberu se prekresluje pri KAZDEM
# kroku prstu a ukladat pri tom pokazde level na disk nema smysl.
func _refresh_entry_flags() -> void:
	var starts: Array = level.start_nodes()
	for i in range(level.lane_count()):
		var a: int = level.lane_start_node(i)
		level.lanes[i]["entry"] = (a >= 0 and starts.has(a))
