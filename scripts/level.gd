class_name Level
extends RefCounted

# LEVEL. Jedno jezero dat: useky (lanes), jejich elementy, VYHYBKY (junctions),
# vystupy a obtiznost. Hra, testy i EDITOR pracuji s timhle jedinym objektem
# a Network z nej postavi geometrii.
#
# SOURADNICE JSOU NORMALIZOVANE (0..1 v ose hraci plochy), takze level se sam
# roztahne na displej hrace - a stejny level vypada na telefonu i na monitoru.
#
# Kdyz level chybi, pouzije se ZAKLADNI DESKA (base()) - presne ta, na ktere
# je hra vyladena. Je to jen level mezi ostatnimi, zadna vyjimka v kodu.
#
# ---------------------------------------------------------------- TOPOLOGIE
# Kmen vede do KORENOVE VYHYBKY (junction 0). Kazdy usek z ni vede bud do
# VYSTUPU (to >= 0) nebo do dalsi VYHYBKY (to < 0, viz target encoding nize).
# Z dalsi vyhybky vedou useky uz jen do vystupu - hloubka je omezena
# (MAX_DEPTH), protoze mezi vyhybkou a vystupem musi zustat misto na rovny
# usek, na kterem stoji bonusy.
#
# VYHYBKA JE VZDY CELY VENTILATOR: hrac na ni klepne (klepnutim na usek, ktery
# z ni vede) a dalsi poutnik po ni pujde. Vic vyhybek = vic nezavislych voleb,
# kazda se prepina tim usekem, ktery pod ni vede - proto zadna tlacitka.
#
# ZADNA GEOMETRIE SE V LEVELU NEDRZI. Radky, hloubky i souradnice vyhybek
# pocita relayout() - kdyby si je level drzel, rozejdou se s tim, co kresli
# Network, a ulozeny level by nebyl ten, ktery hrac videl.

const NEUTRAL := -1
const DEFAULT_NAME := "vlastni"
const MAX_LANES := 7
const MIN_LANES := 2
# Kolik useku muze vest z jedne vyhybky. Je to stejne jako MAX_LANES: kdyby
# byla hranice nizsi, prisel by hrac o moznost pridat usek tam, kam prave
# chce (a dostal by hlasku, ktera nic nevysvetluje).
const MAX_FAN := 7
const MAX_EXITS := 6
# Hloubka vyhybek. 0 = korenova, 1 = vyhybka na konci useku.
const MAX_DEPTH := 1

# Pas, do ktereho se mrizka radek rozmistuje. Nahore je HUD, dole okraj
# displeje; mezi tim se radky VYSTREDI - kdyz je jich min, drzi se u sebe ve
# stredu, a kdyz vic, mezera se zmensi. Diky tomu se prida usek, aniz by se
# vsechny ostatni posunuly.
const TOP := 0.05
const BOTTOM := 0.93

# --- ZAKLADNI DESKA -------------------------------------------------------
# Vsechno, co bylo driv natvrdo v Network. Je to zakladni level a zaroven
# zakladni deska balancu: na ni se ladi hratelnost, ne na novych levelech.
const BASE_LANE_ELEMENTS := [0, 1, 2, 3, NEUTRAL]
const BASE_EXITS := [0, 0, 1, 2, 3]
# Rozestup pruhu. Byl 0.175; Jan chtel mezi useky vic mista, proto 0.22.
const BASE_SPREAD := 0.22
const BASE_EXIT_X := 0.945
const BASE_DIVERT := 0.80

# KORENOVA VYHYBKA a krok hloubky. Kazda dalsi vyhybka stoji o krok dal od
# kraje, aby jeji useky mely pred vystupy misto na rovny usek.
const BASE_JUNCTION_X := 0.25
const DEPTH_DX := 0.24
# Vzdalenost stredu ventilatoru od bodu, kde konci privodni usek. Kresli se
# z toho "kratky kmen" uvnitr vyhybky.
const MERGE_GAP := 0.03

# Podil drahy, ktery zustava PRED rovným usekem a ZA nim. 0.22 z rozpeti
# 0.25..0.945 da presne pas 0.40..0.80 zakladni desky, na ktere je hra
# vyladena. Usek, ktery vede do dalsi vyhybky, je kratky - bere se skoro cely,
# aby se na nem bonusy nemačkaly (0.06).
const RUN_FRAC := 0.22
const RUN_FRAC_CONNECTOR := 0.06
# Nejmensi rovny usek, na ktery se jeste vejdou tri bonusy vedle sebe.
const MIN_RUN := 0.12

# Obtiznost. Cisla jsou zakladni deska; level si je muze prepsat.
const BASE_ZONE_DMG := 30.0
const BASE_SPEED := 52.0
# Mezera mezi poutniky v sekundach. Byla 1.05, pak 1.35; Jan chtel jeste vic
# mista ("o dost větší"), proto 1.9 (52 px/s * 1.9 = 99 px mezi poutniky).
const BASE_SPAWN := 1.9
const BASE_LIVES := 12
const BASE_GOLD := 260

# Krok, o ktery se hybou rucky v editoru.
const SPREAD_STEP := 0.01
const ZONE_STEP := 2.0
const SPEED_STEP := 2.0
const SPAWN_STEP := 0.05
const DIVERTS := [0.62, 0.72, 0.80, 0.88]

var name: String = DEFAULT_NAME
# Useky. Kazdy je slovnik:
#   from   - z ktere vyhybky vede (index do junctions)
#   el     - element (0..3) nebo NEUTRAL (-1)
#   to     - kam vede: >= 0 je index vystupu, < 0 je vyhybka (-1 - index)
#   divert - podil delky rovneho useku, kde se usek ohne ke svemu cili
var lanes: Array = []
# Vyhybky. Kazda je jen "ventilator" - seznam jejich useku se pocita z lanes
# (kdo ma from == index). Vlastni stav (ktera vetev je vybrana) drzi az hra:
# je to stav rozehrane partie, ne level.
var junctions: Array = []
# Vystupy z mapy. Normalizovane souradnice [x, y]. Vystup je dira v mape -
# nema element a nikdo ho "nevlastni".
var exits: Array = []
var spread: float = BASE_SPREAD
var exit_x: float = BASE_EXIT_X
var zone_dmg: float = BASE_ZONE_DMG
var speed: float = BASE_SPEED
var spawn: float = BASE_SPAWN
var lives: int = BASE_LIVES
var gold: int = BASE_GOLD

# Vypoctena geometrie. NENI soucasti levelu - pocita ji relayout() a do
# souboru se neuklada.
# POZOR: useky a vyhybky maji kazde svuj slovnik rozpeti. Kdyby sdilely jeden,
# prekryl by se usek 0 s vyhybkou 0 (oba maji index 0) - a prvni usek by se
# prekreslil doprostred mrizky.
var _row: Dictionary = {}      # usek -> normalizovana y rovneho useku
var _jrow: Dictionary = {}     # vyhybka -> normalizovana y stredu ventilatoru
var _span: Dictionary = {}     # usek -> [prvni radek, posledni radek]
var _jspan: Dictionary = {}    # vyhybka -> [prvni radek, posledni radek]
var _rows_total: int = 0


# ---------------------------------------------------------------- useky

func lane_count() -> int:
	return lanes.size()


func el_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l["el"])


# Kam usek vede: >= 0 vystup, < 0 vyhybka (-1 - index).
func to_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l["to"])


func from_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l.get("from", 0))


func lane_is_exit(lane: int) -> bool:
	return to_of(lane) >= 0


# Vystup, do ktereho usek usti. -1, kdyz usek vede do dalsi vyhybky.
func exit_of(lane: int) -> int:
	return to_of(lane) if lane_is_exit(lane) else -1


# Vyhybka, do ktere usek vede. -1, kdyz usek konci ve vystupu.
func junction_of(lane: int) -> int:
	if lane_is_exit(lane):
		return -1
	return -1 - to_of(lane)


func is_neutral(lane: int) -> bool:
	return el_of(lane) == NEUTRAL


# Na neutralni usek nema smysl stavet - uz bere vsem stejne.
func accepts(lane: int, element: int) -> bool:
	if is_neutral(lane):
		return false
	return element == el_of(lane)


# Sirka useku v podilu delky rovneho useku, kde se ohne ke svemu cili.
func divert_of(lane: int) -> float:
	var l: Dictionary = lanes[lane]
	return float(l.get("divert", BASE_DIVERT))


# ---------------------------------------------------------------- vyhybky

func junction_count() -> int:
	return junctions.size()


# Useky, ktere vedou Z te vyhybky - v poradi, v jakem jsou pod sebou.
func lanes_of(j: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if from_of(i) == j:
			out.append(i)
	return out


# Hloubka vyhybky: 0 = korenova (do ni vede kmen), 1 = na konci useku, ...
func junction_depth(j: int) -> int:
	var d := 0
	var guard := 0
	var cur := j
	while cur > 0 and guard < 16:
		var parent := -1
		for i in range(lanes.size()):
			if junction_of(i) == cur:
				parent = from_of(i)
				break
		if parent < 0:
			break
		cur = parent
		d += 1
		guard += 1
	return d


func junction_row(j: int) -> float:
	return float(_jrow.get(j, TOP))


func junction_x(j: int) -> float:
	return clampf(BASE_JUNCTION_X + float(junction_depth(j)) * DEPTH_DX, BASE_JUNCTION_X, 0.86)


# Vystup, ktery nema zadny usek. Pouziva se pri pridavani useku - novy usek
# ma jit nekam, kde jeste nikdo neni.
func _exit_used(idx: int) -> bool:
	for i in range(lanes.size()):
		if exit_of(i) == idx:
			return true
	return false


func free_exit() -> int:
	for i in range(exits.size()):
		if not _exit_used(i):
			return i
	return maxi(exits.size() - 1, 0)


# ---------------------------------------------------------------- zmeny

# Novy usek z dane vyhybky. Element se vybere tak, aby v mape nechybel
# zadny zivly (a neutralni az kdyz uz vsechny jsou) - nova kolej tak nikdy
# nerozbije matici zivlu.
func _free_element() -> int:
	var seen := {}
	for i in range(lanes.size()):
		seen[el_of(i)] = true
	for e in range(Element.COUNT):
		if not seen.has(e):
			return e
	return NEUTRAL


func add_lane(from_j: int = 0) -> bool:
	if lanes.size() >= MAX_LANES:
		return false
	var j: int = clampi(from_j, 0, maxi(junctions.size() - 1, 0))
	if lanes_of(j).size() >= MAX_FAN:
		return false
	lanes.append({
		"from": j,
		"el": _free_element(),
		"to": free_exit(),
		"divert": BASE_DIVERT,
	})
	_ensure_junctions()
	relayout()
	return true


# Odebere usek. Kdyz po nem zustane prazdna vyhybka, odebere se i ta (jinak by
# v mape zustal ventilator, do ktereho nikdo nevede).
func remove_lane(at: int = -1) -> bool:
	if lanes.size() <= MIN_LANES:
		return false
	var i: int = at
	if i < 0:
		i = lanes.size() - 1
	if i < 0 or i >= lanes.size():
		return false
	var j: int = from_of(i)
	lanes.remove_at(i)
	if j > 0 and lanes_of(j).is_empty():
		_drop_junction(j)
	else:
		relayout()
	return true


# ROZDĚLENÍ ÚSEKU. Vybrany usek prestane koncit ve vystupu a skonci v NOVE
# vyhybce; z te vedou dva useky - jeden pokracuje tam, kam vedl puvodni usek
# (a nese jeho element), druhy vede do noveho vystupu. Presne to je "rozdelit
# usek": hrac si vyrobi dalsi volbu na ceste, ktera dosud volbu nemela.
func split_lane(lane: int) -> int:
	if lane < 0 or lane >= lanes.size():
		return -1
	if not lane_is_exit(lane):
		return -1
	if junction_depth(from_of(lane)) + 1 > MAX_DEPTH:
		return -1
	if lanes.size() + 2 > MAX_LANES:
		return -1
	var j_new: int = junctions.size()
	var keep_el: int = el_of(lane)
	var keep_to: int = to_of(lane)
	var l: Dictionary = lanes[lane]
	l["to"] = -1 - j_new
	lanes[lane] = l
	if exits.size() < MAX_EXITS:
		exits.append([exit_x, TOP])
	var new_to: int = free_exit()
	junctions.append({})
	lanes.append({"from": j_new, "el": keep_el, "to": keep_to, "divert": BASE_DIVERT})
	lanes.append({"from": j_new, "el": _free_element(), "to": new_to, "divert": BASE_DIVERT})
	relayout()
	return j_new


# SLITÍ ÚSEKU ZPĚT. Vybrany usek vede do vyhybky, do ktere vede sam a jeji
# useky konci ve vystupech: usek se prepoji na prvni z nich a vyhybka zmizi.
func merge_lane(lane: int) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	var j: int = junction_of(lane)
	if j < 0:
		return false
	var incoming: Array = []
	for i in range(lanes.size()):
		if junction_of(i) == j:
			incoming.append(i)
	if incoming.size() != 1:
		return false
	var kids: Array = lanes_of(j)
	if kids.is_empty():
		return false
	for k in kids:
		if not lane_is_exit(k):
			return false
	var target: int = to_of(kids[0])
	var l: Dictionary = lanes[lane]
	l["to"] = target
	lanes[lane] = l
	_drop_junction(j)
	return true


# Zrusi vyhybku a vsechny jeji useky. Indexy ostatnich vyhybek se posunou,
# proto se premapuji i odkazy v usecich.
func _drop_junction(j: int) -> void:
	var kids: Array = lanes_of(j)
	kids.sort()
	for k in range(kids.size() - 1, -1, -1):
		lanes.remove_at(int(kids[k]))
	junctions.remove_at(j)
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		var to: int = int(l["to"])
		if to < 0:
			var t: int = -1 - to
			if t > j:
				t -= 1
			l["to"] = -1 - t
		var f: int = int(l.get("from", 0))
		if f > j:
			l["from"] = f - 1
		lanes[i] = l
	relayout()


# CIL VYBRANEHO USEKU. Cykli se pres vsechny vystupy a pak pres vsechny
# vyhybky, do kterych se z toho useku da vubec dojet - tim se daji useky
# SPOJOVAT (dva useky do stejne vyhybky) i ROZDELOVAT (vyhybka sama).
# Preskakuji se cile, ktere by vyrobily smycku nebo moc hlubokou vyhybku.
func target_choices(lane: int) -> Array:
	var out: Array = []
	for e in range(exits.size()):
		out.append(e)
	var from_j: int = from_of(lane)
	for j in range(junctions.size()):
		if j == from_j:
			continue
		if junction_depth(from_j) + 1 + junction_depth(j) > MAX_DEPTH:
			continue
		out.append(-1 - j)
	return out


func cycle_target(lane: int) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	var choices: Array = target_choices(lane)
	if choices.size() < 2:
		return false
	var at: int = choices.find(to_of(lane))
	var next: int = 0 if at < 0 else (at + 1) % choices.size()
	var l: Dictionary = lanes[lane]
	l["to"] = int(choices[next])
	lanes[lane] = l
	relayout()
	return true


# ---------------------------------------------------------------- geometrie

# Kdo vsechno vede do te vyhybky (jeji privodni usek).
func lanes_into(j: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if junction_of(i) == j:
			out.append(i)
	return out


# Vyhybky musi existovat, i kdyz o nich level jeste nic nevi (stare kody).
func _ensure_junctions() -> void:
	var need := 1
	for i in range(lanes.size()):
		need = maxi(need, from_of(i) + 1)
		if not lane_is_exit(i):
			need = maxi(need, junction_of(i) + 1)
	while junctions.size() < need:
		junctions.append({})
	while junctions.size() > need:
		junctions.remove_at(junctions.size() - 1)


# Rozvrzi radky. Kazdy usek koncici ve vystupu je jeden radek; usek, ktery vede
# do dalsi vyhybky, zabira tolik radku, kolik ma ta vyhybka useku - a sedi
# uprostred nich (proto jeho vetve "rozkvetou" na obe strany presne jako
# zakladni deska). Radky se VYSTREDI: pri peti usecich je mezera presne
# `spread`, pri trech se neroztahne pres celou plochu, ale zustane uprostred.
func relayout() -> void:
	_ensure_junctions()
	_row = {}
	_jrow = {}
	_span = {}
	_jspan = {}
	_rows_total = _walk(0, 0, 0)
	var n: int = maxi(_rows_total, 1)
	var gap: float = spread
	var span: float = gap * float(n - 1)
	if span > BOTTOM - TOP:
		gap = (BOTTOM - TOP) / float(maxi(n - 1, 1))
		span = gap * float(n - 1)
	var y0: float = TOP + (BOTTOM - TOP - span) * 0.5
	for j in _jspan:
		var s: Array = _jspan[j]
		_jrow[int(j)] = y0 + gap * (float(int(s[0])) + float(int(s[1]))) * 0.5
	for i in range(lanes.size()):
		# Usek sedi uprostred sveho vlastniho rozpeti. U useku do vystupu je to
		# proste jeho radek; u useku do vyhybky prostredek jejich vetvi.
		_row[i] = y0 + gap * _lane_row_index(i)
	# Vystupy jsou diry v mape: drzi si radek podle sveho indexu v mrizce.
	for idx in range(exits.size()):
		var e: Array = exits[idx]
		var keep_x: float = float(e[0])
		exits[idx] = [keep_x, y0 + gap * float(mini(idx, n - 1))]


# Rekurzivni prichod mrizkou: kazdemu useku priridi rozpeti radku a vrati
# index prvniho volneho radku.
func _walk(j: int, cursor: int, depth: int) -> int:
	var first: int = cursor
	var jl: Array = lanes_of(j)
	for lane in jl:
		if lane_is_exit(lane) or depth >= MAX_DEPTH:
			_span[lane] = [cursor, cursor]
			cursor += 1
		else:
			var k: int = junction_of(lane)
			cursor = _walk(k, cursor, depth + 1)
			_span[lane] = _jspan.get(k, [cursor, cursor])
	if jl.is_empty():
		_jspan[j] = [cursor, cursor]
	else:
		_jspan[j] = [first, cursor - 1]
	return cursor


# Stred rozpeti daneho useku jako index radku.
func _lane_row_index(lane: int) -> float:
	var s: Array = _span.get(lane, [0, 0])
	return (float(int(s[0])) + float(int(s[1]))) * 0.5


func row_of(lane: int) -> float:
	return float(_row.get(lane, TOP))


func exit_row(idx: int) -> float:
	var e: Array = exits[clampi(idx, 0, exits.size() - 1)]
	return float(e[1])


# Rovny usek toho useku v podilu sirky plochy: od bodu, kde se ohne z vyhybky,
# k bodu, kde se ohne ke svemu cili.
func run_of(lane: int) -> float:
	var frac: float = RUN_FRAC if lane_is_exit(lane) else RUN_FRAC_CONNECTOR
	var t: float = exit_x if lane_is_exit(lane) else junction_x(junction_of(lane)) - MERGE_GAP
	return (t - junction_x(from_of(lane))) * (1.0 - 2.0 * frac)


# ---------------------------------------------------------------- zakladni

static func base() -> Level:
	var l := Level.new()
	l.name = "zakladni"
	for i in range(BASE_LANE_ELEMENTS.size()):
		l.lanes.append({
			"from": 0,
			"el": int(BASE_LANE_ELEMENTS[i]),
			"to": int(BASE_EXITS[i]),
			"divert": BASE_DIVERT,
		})
	l.exits = []
	for r in BASE_EXITS:
		l.exits.append([BASE_EXIT_X, TOP])
	l.junctions = [{}]
	l.relayout()
	return l


func clone() -> Level:
	return Level.from_dict(to_dict())


# ---------------------------------------------------------------- data

func to_dict() -> Dictionary:
	# Radky, hloubky ani souradnice vyhybek se NEUKLADaji: pocita je relayout().
	# V souboru by byly jen balast a kod levelu by se zbytecne prodlouzil -
	# pritom se musi vejit do jedne rady Telegramu.
	var brief: Array = []
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		brief.append({
			"from": from_of(i),
			"el": int(l["el"]),
			"to": to_of(i),
			"divert": float(l.get("divert", BASE_DIVERT)),
		})
	return {
		"name": name,
		"lanes": brief,
		"exits": exits.duplicate(true),
		"spread": spread,
		"exit_x": exit_x,
		"zone_dmg": zone_dmg,
		"speed": speed,
		"spawn": spawn,
		"lives": lives,
		"gold": gold,
	}


static func from_dict(d: Dictionary) -> Level:
	var l := Level.new()
	l.name = str(d.get("name", DEFAULT_NAME))
	var raw: Array = d.get("lanes", [])
	for item in raw:
		var m: Dictionary = item
		# "exit" je stary nazev klice pro cil useku - stare levely se musi
		# nacist taky, jinak by hrac prisel o to, co ma ulozene.
		var to: int = int(m.get("to", m.get("exit", 0)))
		l.lanes.append({
			"from": int(m.get("from", 0)),
			"el": int(m.get("el", NEUTRAL)),
			"to": to,
			"divert": float(m.get("divert", BASE_DIVERT)),
		})
	if l.lanes.is_empty():
		return Level.base()
	var ex: Array = d.get("exits", [])
	for item in ex:
		var p: Array = item
		l.exits.append([float(p[0]), float(p[1])])
	if l.exits.is_empty():
		l.exits.append([BASE_EXIT_X, TOP])
	l.spread = float(d.get("spread", BASE_SPREAD))
	l.exit_x = float(d.get("exit_x", BASE_EXIT_X))
	l.zone_dmg = float(d.get("zone_dmg", BASE_ZONE_DMG))
	l.speed = float(d.get("speed", BASE_SPEED))
	l.spawn = float(d.get("spawn", BASE_SPAWN))
	l.lives = int(d.get("lives", BASE_LIVES))
	l.gold = int(d.get("gold", BASE_GOLD))
	l.clamp_all()
	l.relayout()
	return l


func to_json() -> String:
	return JSON.stringify(to_dict())


# KOD LEVELU pro predani mimo hru. Je to stejny JSON, jen zbaveny mezer,
# aby se vesel do jedne rady Telegramu i z telefonu:
#   ZILY1;{"name":"...","lanes":[...],...}
# Cislo za ZILY je verze formatu - kdyby se data jednou zmenila, stary kod
# se pozna a necte se naslepo.
const CODE_PREFIX := "ZILY1;"


func to_code() -> String:
	var t: String = to_json()
	t = t.replace(": ", ":").replace(", ", ",")
	return CODE_PREFIX + t


static func from_code(code: String) -> Level:
	var t: String = code.strip_edges()
	# Hrac muze poslat i cely JSON ze souboru - oboji je stejny format.
	if t.begins_with(CODE_PREFIX):
		t = t.substr(CODE_PREFIX.length())
	if not t.begins_with("{"):
		return Level.base()
	return Level.from_json(t)


# LEVEL ZAKOTVENY VE HRE. Cte se z BuiltinLevels - to je jedina cesta, jak
# se level dostane natrvalo do hry na vsechny platformy. Vraci null, kdyz
# takovy level neni (pak se hleda lokalne ulozeny).
static func builtin(n: String) -> Level:
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		if str(d.get("name", "")) != n:
			continue
		var lv := from_code(str(d.get("code", "")))
		lv.name = n
		return lv
	return null


static func builtin_names() -> Array:
	var out: Array = []
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		out.append(str(d.get("name", "")))
	return out


static func from_json(text: String) -> Level:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return Level.base()
	var d: Dictionary = parsed
	return Level.from_dict(d)


# Rucky se daji utect mimo rozumne meze; level se po kazde zmene srovna, aby
# se z nej nedal vyrobit level, ktery se nevejde na displej.
func clamp_all() -> void:
	spread = clampf(spread, 0.06, 0.30)
	exit_x = clampf(exit_x, 0.80, 0.99)
	zone_dmg = clampf(zone_dmg, 10.0, 90.0)
	speed = clampf(speed, 20.0, 120.0)
	spawn = clampf(spawn, 0.6, 3.0)
	lives = clampi(lives, 3, 40)
	gold = clampi(gold, 0, 5000)
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		l["from"] = clampi(int(l.get("from", 0)), 0, 16)
		l["el"] = clampi(int(l["el"]), NEUTRAL, Element.COUNT - 1)
		var to: int = int(l["to"])
		if to >= 0:
			l["to"] = clampi(to, 0, maxi(exits.size() - 1, 0))
		else:
			l["to"] = to
		l["divert"] = clampf(float(l.get("divert", BASE_DIVERT)), 0.0, 0.98)
		lanes[i] = l


# ---------------------------------------------------------------- ulozeni

# Levely se ukladaji jako JSON. Ve webovem exportu do localStorage (aby hrac
# o svou praci neprisel zavrenim panelu), na desktopu do user://.
# Cteni i zapis jsou synchronni, takze k nim nepotrebujeme zadny callback.
const WEB_PREFIX := "zily.level."
const DIR := "user://levels"
const INDEX_KEY := "zily.levels"
const LAST_KEY := "zily.last"


func storage_key() -> String:
	return WEB_PREFIX + name


static func _web() -> Object:
	if not OS.has_feature("web"):
		return null
	return Engine.get_singleton("JavaScriptBridge")


static func _js_get(key: String) -> String:
	var jb: Object = _web()
	if jb == null:
		return ""
	var t: Variant = jb.call("eval", "localStorage.getItem(%s)||''" % JSON.stringify(key), false)
	if typeof(t) == TYPE_STRING:
		return str(t)
	return ""


static func _js_set(key: String, value: String) -> void:
	var jb: Object = _web()
	if jb != null:
		jb.call("eval", "localStorage.setItem(%s,%s)" % [
			JSON.stringify(key), JSON.stringify(value)], false)


func save() -> bool:
	var text: String = to_json()
	if _web() != null:
		_js_set(storage_key(), text)
		_remember(str(name))
		save_last(str(name))
		return true
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/" + name + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	_remember(str(name))
	save_last(str(name))
	return true


static func load_named(n: String) -> Level:
	var t: String = _js_get(WEB_PREFIX + n)
	if not t.is_empty():
		var lv := Level.from_json(t)
		lv.name = n
		return lv
	if _web() != null:
		return Level.base()
	var f: FileAccess = FileAccess.open(DIR + "/" + n + ".json", FileAccess.READ)
	if f == null:
		return Level.base()
	var text: String = f.get_as_text()
	f.close()
	var lv2 := Level.from_json(text)
	lv2.name = n
	return lv2


static func _remember(n: String) -> void:
	if _web() != null:
		var jb: Object = _web()
		jb.call("eval", "(function(){var k=%s;var l=JSON.parse(localStorage.getItem(k)||'[]');" % INDEX_KEY +
			"if(l.indexOf(%s)<0){l.push(%s);localStorage.setItem(k,JSON.stringify(l));}})()" % [
				JSON.stringify(n), JSON.stringify(n)], false)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/_index.txt", FileAccess.READ)
	var known: String = f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	if not known.contains("\n" + n + "\n"):
		var w: FileAccess = FileAccess.open(DIR + "/_index.txt", FileAccess.WRITE)
		if w != null:
			w.store_string(known + "\n" + n + "\n")
			w.close()


# Seznam ulozenych levelu. Pouziva ho editor v seznamu.
static func saved_names() -> Array:
	var out: Array = []
	var t: String = _js_get(INDEX_KEY)
	if _web() != null:
		var parsed: Variant = JSON.parse_string(t)
		if typeof(parsed) == TYPE_ARRAY:
			for x in parsed:
				out.append(str(x))
		return out
	var f: FileAccess = FileAccess.open(DIR + "/_index.txt", FileAccess.READ)
	if f == null:
		return out
	var text: String = f.get_as_text()
	f.close()
	for line in text.split("\n", false):
		out.append(str(line))
	return out


# Posledni otevreny level. Editor se po otevreni vrati presne tam, kde hrac
# skoncil - jinak by pri kazdem vstupu do editoru prisel o to, co delal.
static func save_last(n: String) -> void:
	if _web() != null:
		_js_set(LAST_KEY, n)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/_last.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(n)
		f.close()


static func last_name() -> String:
	if _web() != null:
		return _js_get(LAST_KEY)
	var f: FileAccess = FileAccess.open(DIR + "/_last.txt", FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t.strip_edges()


# Jmeno pro novy level: "level-1", "level-2", ... Prvni, ktere jeste nikdo
# nepouziva. Nahodne jmeno by se v seznamu nedalo najit.
static func next_free_name() -> String:
	var used := {}
	for n in saved_names():
		used[str(n)] = true
	var i := 1
	while used.has("level-%d" % i):
		i += 1
	return "level-%d" % i


# Export levelu do souboru, ktery si hrac muze poslat. Ve webu se soubor
# stahne (blob), na desktopu se zapise do user://export.
func export_to_file() -> String:
	var text: String = to_json()
	if _web() != null:
		var js := """
		(() => {
		  const blob = new Blob([%s], {type: 'application/json'});
		  const a = document.createElement('a');
		  a.href = URL.createObjectURL(blob);
		  a.download = 'zily-%s.json';
		  document.body.appendChild(a); a.click(); a.remove();
		  return 'ok';
		})()
		""" % [JSON.stringify(text), name]
		var jb: Object = _web()
		jb.call("eval", js, false)
		return "zily-%s.json (staženo)" % name
	DirAccess.make_dir_recursive_absolute("user://export")
	var path: String = "user://export/zily-%s.json" % name
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path(path)


# Rychla kontrola, ze level dava smysl. Editor ji pousti pred exportem -
# prazdny nebo rozbity level by hrac poznal az ve hre.
func validate() -> Array:
	var errs: Array = []
	if lanes.size() < MIN_LANES:
		errs.append("méně než %d úseky" % MIN_LANES)
	if lanes.size() > MAX_LANES:
		errs.append("více než %d úseků" % MAX_LANES)
	if exits.is_empty():
		errs.append("žádný výstup")
	for i in range(exits.size()):
		if exits[i].size() < 2:
			errs.append("výstup %d nemá souřadnice" % (i + 1))
	for i in range(lanes.size()):
		if from_of(i) < 0 or from_of(i) >= junctions.size():
			errs.append("úsek %d vede z neexistující výhybky" % (i + 1))
		if not lane_is_exit(i):
			var k: int = junction_of(i)
			if k < 0 or k >= junctions.size():
				errs.append("úsek %d vede do neexistující výhybky" % (i + 1))
			elif junction_depth(from_of(i)) + 1 > MAX_DEPTH:
				errs.append("úsek %d vede do výhybky, která je moc hluboko" % (i + 1))
		elif exit_of(i) >= exits.size():
			errs.append("úsek %d míří na neexistující výstup" % (i + 1))
		if lanes_of(from_of(i)).size() > MAX_FAN:
			errs.append("z výhybky %d vede víc než %d úseků" % [from_of(i) + 1, MAX_FAN])
		if run_of(i) < MIN_RUN:
			errs.append("úsek %d je moc krátký na to, aby na něm stály bonusy" % (i + 1))
	for j in range(1, junctions.size()):
		var kids: Array = lanes_of(j)
		if kids.size() < 2:
			errs.append("výhybka %d má míň než dva úseky" % (j + 1))
		if lanes_into(j).is_empty():
			errs.append("do výhybky %d nikdo nevede" % (j + 1))
		for k in kids:
			if not lane_is_exit(k):
				errs.append("z výhybky %d vede úsek do další výhybky" % (j + 1))
	if lanes_of(0).size() < MIN_LANES:
		errs.append("z první výhybky nevedou aspoň dva úseky")
	var killable := 0
	for i in range(lanes.size()):
		if not is_neutral(i):
			killable += 1
	if killable < 2:
		errs.append("v mapě není dost úseků, které umí zabíjet")
	return errs
