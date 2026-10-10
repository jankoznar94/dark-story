class_name Level
extends RefCounted

# =========================================================================
# LEVEL JE GRAF V MRÍŽCE. Zadne automaticke rozvrhovani, zadne radky.
#
# Jan (Oct 2026): "Cesty budu kreslit prstem, libovolneho smeru a tvaru.
# Vzdy bude drzet rovinu. Bude se lamat v 90 stupnovych uhlech."
#
# Dve veci, ktere z toho plynou a ktere urcuji cely tento soubor:
#
#   1. GRAF NENI STROM. Nekresli se jen "fan" z vyhybky do cile - cesta se
#      ohne, vrati se zpatky a spoji se s jinou (v nakresu ma mapa DIAMANTY:
#      rozdel -> dve paralelni trasy -> spoj). Proto ma usek SEZNAM PRITOKU,
#      ne jednoho predchudce, a proto je "spojka" (N vstupu -> 1 vystup)
#      rovnocenny prvek s "vyhybkou" (1 vstup -> N vystupu).
#
#   2. UZEL JE BUNKA. Usek (hrana) zacina a konci ve STREDU bunky uzlu.
#      Diky tomu staci na prechod poutnika z useku na usek jen "dosel jsem
#      na konec useku -> v uzlu vyber dalsi usek", bez vstupniho bodu,
#      bez lane_entry_s a bez TO_LANE (vlej se do jineho useku). Napojovani
#      cest nahrazuje UZEL polozeny na cizi usek - usek se tam ROZDELI.
#
# Co z puvodniho modelu zmizelo: relayout, rows_fit, MIN_ROW_GAP, NODE_FRACS,
# run_frac_for, divert, MAX_DEPTH, span/_jspan, automaticke umistovani.
# Co zustalo: damage model (Element + zone_dmg), bonusy na usek, rng a vlny
# (ty jsou ve Game, ne tady).
# =========================================================================

# --------------------------------------------------------------- mrizka
# MRIZKA VYPLNUJE ARENU: `Network` pocita cell_w = arena.w/cols a
# cell_h = arena.h/rows, takze bunka neni ctvercova a okraj nezustava
# zadny. Natazeni po ose ale nic nelame - cesty vedou PO OSE, takze se
# z kazdeho ohybu stane i tak pravy uhel.
#
# HUSTOTA. Jan (Oct 2026): "Mohl by být grid ještě hustší? Aby byly
# čtverečky menší a tím pádem se mohly cesty stavět o něco flexibilněji."
# 20x10 -> 28x14 (krok 0.4): na 932x430 je bunka v editoru 33x23 px misto
# 47x32, takze ohyb cesty stoji 33 px a dve trasy se daji slozit tesne
# vedle sebe. Hranici je prst: na 640x360 (nejmensi podporovany displej)
# vyjde bunka na 23x18 px a mensi uz by se nedala trefit.
const COLS := 28
const ROWS := 14

# --------------------------------------------------------------- druhy uzlu
const START := 0      # vstup poutniku, 1 vystup
const CIL := 1        # konec cesty, >= 1 vstup, zadny vystup
const VYHYBKA := 2    # 1 vstup, >= 2 vystupy - hrac voli, kterym poutnik pujde
const SPOJKA := 3     # >= 2 vstupy, 1 vystup - trasu slucuje, nerozhoduje
const UZEL := 4       # 1 vstup, 1 vystup - pruchozi bod (bonus, pripojeni)

const KIND_NAMES := ["start", "cíl", "výhybka", "spojka", "uzel"]

# Element useku. Neutralni usek nema element a dava vsem 100 %.
const NEUTRAL := -1
# KMEN je druhy usek BEZ ELEMENTU: neposkozuje vubec (jako vstupni usek ze
# startu). Jan: "v nabidce typu cest chybi neutralni a kmen (nedava zadne
# poskozeni)". Neni to element, proto se nikdy nesmi dostat do
# Element.name_of - na jmena je tu `value_name()`.
const KMEN := -2

# --------------------------------------------------------------- zakladni cisla
const BASE_ZONE_DMG := 30.0
const BASE_SPEED := 52.0
const BASE_SPAWN := 1.9
const BASE_LIVES := 12
const BASE_GOLD := 260
# Kolik bonusu se vejde na jeden usek. Neni to geometrie - je to pocet
# mist, kam hrac muze klepnout. KAZDY USEK SI SVUJ POCET DRZI SAM
# ("slots" v datech useku) - Jan: "Nekde jen 1, nekde 3, nekde i vice a
# nekde uplne bez bonusu." SLOTS je jen vychozi hodnota pro nove useky.
const SLOTS := 3
# Strop poctu mist na jednom useku. Neni to geometrie (mista se vejdou i
# vic), je to mez, za kterou uz by se klepnuti na jedno misto nedalo
# odlisit od sousedniho. Editor cykluje 0..MAX_SLOTS.
const MAX_SLOTS := 6

var name: String = ""
var cols: int = COLS
var rows: int = ROWS

# UZLY: [{c:int, r:int, kind:int}]
var nodes: Array = []
# USEKY: [{cells: Array[Vector2i], elem:int, entry:bool, slots:int}]
#   cells[0] je bunka pocatecniho uzlu, cells[-1] bunka koncoveho uzlu.
#   entry = vede ze STARTu (odvozeno z grafu, ne z ruky hrace). Je to
#   STRUKTURALNI priznak: z takoveho useku poutnici vstupuji do mapy a
#   prodluzuje se na okraj displeje. O poskozeni ROZHODUJE HODNOTA USEKU,
#   ne tenhle priznak - vstupni usek je od vychoziho stavu KMEN, ale hrac
#   ho muze prepnout na element.
#   slots = kolik mist na bonus tenhle usek ma (0 = zadne bonusy).
var lanes: Array = []

var zone_dmg: float = BASE_ZONE_DMG
var speed: float = BASE_SPEED
var spawn: float = BASE_SPAWN
var lives: int = BASE_LIVES
var gold: int = BASE_GOLD

# Stav posledni kontroly - editor i UI z nej ctou, co se prave stalo.
var last_error: String = ""


# =========================================================================
# UZLY A USEKY - zakladni pristup
# =========================================================================

func node_count() -> int:
	return nodes.size()


func lane_count() -> int:
	return lanes.size()


func node_kind(n: int) -> int:
	if n < 0 or n >= nodes.size():
		return -1
	return int(nodes[n]["kind"])


func node_cell(n: int) -> Vector2i:
	if n < 0 or n >= nodes.size():
		return Vector2i(-1, -1)
	return Vector2i(int(nodes[n]["c"]), int(nodes[n]["r"]))


func kind_name(kind: int) -> String:
	if kind < 0 or kind >= KIND_NAMES.size():
		return "?"
	var s: String = KIND_NAMES[kind]
	return s


# Uzel lezi na te bunce? -1 kdyz tam nic neni.
func node_at(c: int, r: int) -> int:
	for i in range(nodes.size()):
		if int(nodes[i]["c"]) == c and int(nodes[i]["r"]) == r:
			return i
	return -1


func node_at_cell(cell: Vector2i) -> int:
	return node_at(cell.x, cell.y)


func lane_cells(lane: int) -> Array:
	if lane < 0 or lane >= lanes.size():
		return []
	var a: Array = lanes[lane]["cells"]
	return a


func lane_element(lane: int) -> int:
	if lane < 0 or lane >= lanes.size():
		return NEUTRAL
	return int(lanes[lane]["elem"])


func lane_is_neutral(lane: int) -> bool:
	return lane_element(lane) == NEUTRAL


func lane_is_kmen(lane: int) -> bool:
	return lane_element(lane) == KMEN


# USEK, KTERY VUBEC NEPOSKOZUJE. Je to JEN kmen - a nic vic. Driv se tu
# ptalo i na priznak "entry" (usek ze startu), takze vstupni usek nemel
# poskozeni, i kdyz na sobe mel barvu elementu: vypadal jako ohen a choval
# se jako kmen. Presne to Janovi vadilo ("barvu má jak element a je to
# matoucí"). Vstupni usek je proto od zacatku KMEN (kresli se sedy) a hrac
# ho muze tlacitkem "typ" prepnout na element - a tim padem i na zpet na
# kmen. JEDNO pravidlo: o poskozeni rozhoduje jen hodnota useku.
func lane_deals_damage(lane: int) -> bool:
	return not lane_is_kmen(lane)


# USEK, NA KTERY SE DA STAVET BONUS. Na neutralni usek ne (uz poskozuje
# vsechny stejne) a na kmen taky ne - bonus by nemel co posilit a hrac by
# vyhodil zlato.
func lane_takes_bonus(lane: int) -> bool:
	if lane_is_neutral(lane) or lane_is_kmen(lane):
		return false
	return lane_deals_damage(lane)


# JMENO HODNOTY USEKU. `Element.name_of` se na neutralni usek a kmen NESMI
# volat: dostane -1/-2 a v GDScriptu to neni chyba, ale tichy nesmysl
# (NAMES[-1] je "Vzduch"), takze by hra lhala o tom, na co se hrac kouka.
static func value_name(e: int) -> String:
	if e == NEUTRAL:
		return "neutrální"
	if e == KMEN:
		return "kmen"
	if e < 0 or e >= Element.COUNT:
		return "?"
	return Element.name_of(e)


func lane_type_name(lane: int) -> String:
	return Level.value_name(lane_element(lane))


func lane_accepts(lane: int, element: int) -> bool:
	if not lane_takes_bonus(lane):
		return false
	return lane_element(lane) == element


# KOLIK MIST NA BONUS TENHLE USEK MA. Neni to konstanta: Jan chce, aby si to
# kazdy usek nesl sam ("nekde jen 1, nekde 3, nekde i vice a nekde uplne bez
# bonusu"). Nula je platna hodnota - usek bez bonusu.
func lane_slot_count(lane: int) -> int:
	if lane < 0 or lane >= lanes.size():
		return 0
	return clampi(int(lanes[lane].get("slots", SLOTS)), 0, MAX_SLOTS)


func set_lane_slots(lane: int, n: int) -> void:
	if lane < 0 or lane >= lanes.size():
		return
	lanes[lane]["slots"] = clampi(n, 0, MAX_SLOTS)


func set_lane_element(lane: int, element: int) -> void:
	if lane < 0 or lane >= lanes.size():
		return
	lanes[lane]["elem"] = element


# Usek, ze ktereho poutnici vstupuji do mapy. Odvozeno z grafu (usek ze
# STARTu), ne z priznaku - prislo by o nej pri kazde zmene tvaru mapy.
# Sam o sobe NERIKA nic o poskozeni: to je vec hodnoty useku (KMEN = zadne).
func lane_is_entry(lane: int) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	return bool(lanes[lane]["entry"])


func lane_start_node(lane: int) -> int:
	var cs: Array = lane_cells(lane)
	if cs.is_empty():
		return -1
	var c: Vector2i = cs[0]
	return node_at_cell(c)


func lane_end_node(lane: int) -> int:
	var cs: Array = lane_cells(lane)
	if cs.is_empty():
		return -1
	var c: Vector2i = cs[cs.size() - 1]
	return node_at_cell(c)


# Useky, ktere z uzlu VYCHAZEJI (zacina v nem jejich prvni bunka).
func lanes_from(n: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if lane_start_node(i) == n:
			out.append(i)
	return out


# Useky, ktere do uzlu USTI.
func lanes_into(n: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if lane_end_node(i) == n:
			out.append(i)
	return out


# Useky, ktere se uzlu dotykaji z jakekoli strany.
func lanes_at(n: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if lane_start_node(i) == n or lane_end_node(i) == n:
			out.append(i)
	return out


func first_start() -> int:
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == START:
			return i
	return -1


func exit_count() -> int:
	var c := 0
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == CIL:
			c += 1
	return c


func exit_nodes() -> Array:
	var out: Array = []
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == CIL:
			out.append(i)
	return out


# =========================================================================
# PRECHOD UZLEM - jedine misto, kde se rozhoduje, kam poutnik pujde dal
# =========================================================================

# Kolik voleb uzel nabizi. Pro hrace je to pocet vystupu z vyhybky.
func node_choice_count(n: int) -> int:
	return lanes_from(n).size()


# Vystup c. `sel` z uzlu. -1 = nikam (slepota).
func node_choice(n: int, sel: int) -> int:
	var outs: Array = lanes_from(n)
	if sel < 0 or sel >= outs.size():
		return -1
	return int(outs[sel])


# Dalsi usek pri pruchodu uzlem. `sel` je volba hrace pro VYHYBKU;
# start, spojka a uzel zadnou volbu nemaji - maji jeden vystup, takze se
# `sel` ignoruje. -1 = poutnik dosel na konec (vstup do cile).
#
# START vystup MA: poutnici do mapy vstupuji prave tudy, takze se z nej
# odchazi stejne jako ze spojky. Kdyby vracel -1, nikdo by se nikdy
# nerozesel.
func next_lane(n: int, sel: int = 0) -> int:
	var kind: int = node_kind(n)
	if kind == CIL:
		return -1
	if kind == VYHYBKA:
		return node_choice(n, sel)
	return node_choice(n, 0)


# =========================================================================
# ZIVLY V MAPE
# =========================================================================

# Zivly, ktere se v teto mape posilaji. Neutralni useky se nepocitaji.
# Neni to kosmetika: poutnik s elementem, ktery v mape nema svuj protiklad,
# se neda zabit (vlastni usek dava 0 %), takze by level byl nevyhratelny.
func spawn_elements() -> Array:
	var seen: Array = []
	for i in range(lanes.size()):
		var e: int = lane_element(i)
		# Neutralni usek ani kmen nejsou element - z nich se posilat nesmi.
		if e < 0:
			continue
		if not seen.has(e):
			seen.append(e)
	seen.sort()
	return seen


# =========================================================================
# ROZMERY
# =========================================================================

func cell_center(c: int, r: int) -> Vector2:
	var cc: int = maxi(cols, 1)
	var rr: int = maxi(rows, 1)
	return Vector2((float(c) + 0.5) / float(cc), (float(r) + 0.5) / float(rr))


# Sirka/vyska mrizky v normalizovanych jednotkach - Network z ni pocita
# velikost bunky. Mrizka se do areny vejde CELA (bunka ctvercova), takze
# na sirokem displeji zustanou po stranach okraje. To je zamer.
func grid_aspect() -> float:
	return float(cols) / float(maxi(rows, 1))


func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < cols and r < rows


# =========================================================================
# KOPIE
# =========================================================================

func clone() -> Level:
	var lv := Level.new()
	lv.name = name
	lv.cols = cols
	lv.rows = rows
	lv.zone_dmg = zone_dmg
	lv.speed = speed
	lv.spawn = spawn
	lv.lives = lives
	lv.gold = gold
	lv.last_error = last_error
	for n in nodes:
		lv.nodes.append({"c": int(n["c"]), "r": int(n["r"]), "kind": int(n["kind"])})
	for ln in lanes:
		var cells: Array = []
		for cell in ln["cells"]:
			var v: Vector2i = cell
			cells.append(Vector2i(v.x, v.y))
		lv.lanes.append({
			"cells": cells,
			"elem": int(ln["elem"]),
			"entry": bool(ln["entry"]),
			"slots": clampi(int(ln.get("slots", SLOTS)), 0, MAX_SLOTS),
		})
	return lv


# =========================================================================
# KONTROLA MAPY
#
# Vsechno, co kdy mohlo vzniknout jen rukou, se kontroluje tady. Editor
# a nacteni kodu se ptaji teto jedne funkce - kdyby si kazdy kontroloval
# sve, casem se rozejdou a mapa, ktera se v editoru tvari dobre, se ve
# hre neda dohrat.
#
# Navratova hodnota je seznam ceskych vet - prazdny = mapa je v poradku.
# =========================================================================

func validate() -> Array:
	var errs: Array = []
	var starts: int = 0
	for n in range(nodes.size()):
		if node_kind(n) == START:
			starts += 1
	if starts != 1:
		errs.append("mapa musí mít právě jeden start (má %d)." % starts)
	if exit_count() < 1:
		errs.append("mapa nemá žádný cíl.")

	# --- rozmery a poloha
	for n in range(nodes.size()):
		var c: Vector2i = node_cell(n)
		if not in_bounds(c.x, c.y):
			errs.append("uzel %d leží mimo mřížku." % n)
	if nodes.size() > cols * rows:
		errs.append("uzlů je víc než buněk.")

	# --- kolik ma ktery uzel vstupu a vystupu
	for n in range(nodes.size()):
		var ins: int = lanes_into(n).size()
		var outs: int = lanes_from(n).size()
		var kn: String = kind_name(node_kind(n))
		match node_kind(n):
			START:
				if ins != 0:
					errs.append("start má %d vstupních úseků (má jich být 0)." % ins)
				if outs != 1:
					errs.append("start má %d výstupních úseků (má být 1)." % outs)
			CIL:
				if outs != 0:
					errs.append("cíl má %d výstupních úseků (má jich být 0)." % outs)
				if ins < 1:
					errs.append("do cíle nevede žádný úsek.")
			VYHYBKA:
				if ins != 1:
					errs.append("výhybka má %d vstupních úseků (má být 1)." % ins)
				if outs < 2:
					errs.append("výhybka má %d výstupních úseků (mají být aspoň 2)." % outs)
			SPOJKA:
				if ins < 2:
					errs.append("spojka má %d vstupních úseků (mají být aspoň 2)." % ins)
				if outs != 1:
					errs.append("spojka má %d výstupních úseků (má být 1)." % outs)
			UZEL:
				if ins != 1 or outs != 1:
					errs.append("uzel %d má %d vstupů a %d výstupů (má být 1 a 1)." % [n, ins, outs])
			_:
				errs.append("uzel %d má neznámý druh %s." % [n, kn])

	# --- kazdy usek: souvisla cesta po mrizce, z uzlu do uzlu
	var used: Dictionary = {}
	for i in range(lanes.size()):
		var cs: Array = lane_cells(i)
		if cs.size() < 2:
			errs.append("úsek %d je kratší než jedna buňka." % i)
			continue
		var sn: int = lane_start_node(i)
		var en: int = lane_end_node(i)
		if sn < 0:
			errs.append("úsek %d nezačíná v uzlu." % i)
		if en < 0:
			errs.append("úsek %d nekončí v uzlu." % i)
		# Mista na bonus jsou DATA, ne konstanta - proto se kontroluji tady
		# a ne pocitanim nekde v kresleni. Hodnota mimo rozsah znamena kod,
		# ktery si nekdo vymyslel rucne.
		var raw_slots: int = int(lanes[i].get("slots", SLOTS))
		if raw_slots < 0 or raw_slots > MAX_SLOTS:
			errs.append("úsek %d má %d míst na bonus (0 až %d)." % [i, raw_slots, MAX_SLOTS])
		if sn >= 0 and sn == en:
			errs.append("úsek %d se vrací do stejného uzlu." % i)
		for k in range(cs.size()):
			var cell: Vector2i = cs[k]
			if not in_bounds(cell.x, cell.y):
				errs.append("úsek %d vede mimo mřížku." % i)
				break
			# sousedni bunky se lisi presne v jedne ose o 1 - jinak by
			# se cesta lámala šikmo nebo skákala
			if k > 0:
				var prev: Vector2i = cs[k - 1]
				var dx: int = absi(cell.x - prev.x)
				var dy: int = absi(cell.y - prev.y)
				if dx + dy != 1:
					errs.append("úsek %d se v buňce %d láme šikmo nebo skáče." % [i, k])
					break
			# bunka uzlu smi byt sdilena (je to uzel) - ostatni ne
			if node_at_cell(cell) >= 0:
				continue
			if used.has(cell):
				errs.append("úsek %d se kříží s úsekem %d v buňce %d,%d." % [
					i, int(used[cell]), cell.x, cell.y])
				break
			used[cell] = i
		if sn >= 0 and sn == en:
			continue
		# bunky uzlu nesmi lezet UPROSTRED useku - usek by se musel rozdelit
		for k in range(1, maxi(cs.size() - 1, 1)):
			var mid: Vector2i = cs[k]
			var mn: int = node_at_cell(mid)
			if mn >= 0 and k != cs.size() - 1:
				errs.append("úsek %d prochází uzlem %d, aniž by tam končil." % [i, mn])
				break

	# --- dosazitelnost: ze startu se musi dat dojit na kazdy usek i cil
	var st: int = first_start()
	if st >= 0:
		var seen_nodes: Dictionary = {}
		var seen_lanes: Dictionary = {}
		var queue: Array = [st]
		seen_nodes[st] = true
		while not queue.is_empty():
			var n: int = int(queue.pop_front())
			for ln in lanes_from(n):
				var l: int = int(ln)
				if seen_lanes.has(l):
					continue
				seen_lanes[l] = true
				var en: int = lane_end_node(l)
				if en >= 0 and not seen_nodes.has(en):
					seen_nodes[en] = true
					queue.append(en)
		for i in range(lanes.size()):
			if not seen_lanes.has(i):
				errs.append("úsek %d se nedá ze startu vůbec dojít." % i)
		for n in range(nodes.size()):
			if node_kind(n) == CIL and not seen_nodes.has(n):
				errs.append("do cíle %d se nedá dojít." % n)
				break
		# ze zadneho useku nesmi vest slepa ulicka - kazdy musi mit
		# cestu do nejakeho cile
		var reaches: Dictionary = {}
		for i in range(lanes.size()):
			if not _reaches_exit(i):
				errs.append("úsek %d nevede do žádného cíle." % i)
				break
	return errs


# Dá se z tohohle useku vubec dojit k cili?
func _reaches_exit(lane: int) -> bool:
	var seen: Dictionary = {}
	var stack: Array = [lane]
	while not stack.is_empty():
		var l: int = int(stack.pop_back())
		if seen.has(l):
			continue
		seen[l] = true
		var en: int = lane_end_node(l)
		if en < 0:
			continue
		if node_kind(en) == CIL:
			return true
		for ln in lanes_from(en):
			stack.append(int(ln))
	return false


# =========================================================================
# SERIALIZACE
#
# Kod je to, jak level cestuje z telefonu - Jan ho vlozi do zpravy a
# vlozi zpatky. Jedna minifikovana radka, zadne odsazovani.
# =========================================================================

func to_dict() -> Dictionary:
	var ns: Array = []
	for n in nodes:
		ns.append([int(n["c"]), int(n["r"]), int(n["kind"])])
	var ls: Array = []
	for ln in lanes:
		var cells: Array = []
		var cs: Array = ln["cells"]
		for cell in cs:
			var v: Vector2i = cell
			cells.append([v.x, v.y])
		# CTVRTY PRVEK JE POCET MIST NA BONUS a pise se JEN KDYBY SE LISI
		# od vychoziho. Zakladni deska i vsechny drive ulozene levely tak
		# maji kod PRESNE stejny jako predtim - a stara ulozena mapa se
		# nacte (ctvrty prvek chybi -> vychozi hodnota).
		var row: Array = [int(ln["elem"]), 1 if bool(ln["entry"]) else 0, cells]
		var sl: int = clampi(int(ln.get("slots", SLOTS)), 0, MAX_SLOTS)
		if sl != SLOTS:
			row.append(sl)
		ls.append(row)
	return {
		"v": 2,
		"n": name,
		"w": cols,
		"h": rows,
		"z": zone_dmg,
		"s": speed,
		"p": spawn,
		"l": lives,
		"g": gold,
		"u": ns,
		"e": ls,
	}


static func from_dict(d: Dictionary) -> Level:
	var lv := Level.new()
	lv.name = str(d.get("n", ""))
	lv.cols = int(d.get("w", COLS))
	lv.rows = int(d.get("h", ROWS))
	lv.zone_dmg = float(d.get("z", BASE_ZONE_DMG))
	lv.speed = float(d.get("s", BASE_SPEED))
	lv.spawn = float(d.get("p", BASE_SPAWN))
	lv.lives = int(d.get("l", BASE_LIVES))
	lv.gold = int(d.get("g", BASE_GOLD))
	for raw in d.get("u", []):
		var a: Array = raw
		if a.size() < 3:
			continue
		lv.nodes.append({"c": int(a[0]), "r": int(a[1]), "kind": int(a[2])})
	for raw in d.get("e", []):
		var a: Array = raw
		if a.size() < 3:
			continue
		var cells: Array = []
		for rc in a[2]:
			var b: Array = rc
			if b.size() < 2:
				continue
			cells.append(Vector2i(int(b[0]), int(b[1])))
		var slots: int = SLOTS
		if a.size() >= 4:
			slots = clampi(int(a[3]), 0, MAX_SLOTS)
		lv.lanes.append({"cells": cells, "elem": int(a[0]), "entry": int(a[1]) == 1,
			"slots": slots})
	return lv


func to_json() -> String:
	return JSON.stringify(to_dict())


static func from_json(text: String) -> Level:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var lv := from_dict(d)
	return lv


func to_code() -> String:
	return "ZILY2;" + to_json()


static func from_code(code: String) -> Level:
	var t: String = code.strip_edges()
	if not t.begins_with("ZILY2;"):
		return null
	var lv := from_json(t.substr(6))
	if lv == null:
		return null
	if not lv.validate().is_empty():
		return null
	return lv


# =========================================================================
# UKLADANI - lokalne, na server se neposila nic
# =========================================================================

# Staticka proto, ze ji pouziva i staticka saved_keys().
static func storage_dir() -> String:
	return "user://levels/"


func storage_key() -> String:
	var s: String = name if name != "" else "vlastni"
	var out := ""
	for ch in s:
		if ch == "/" or ch == "\\" or ch == ":":
			out += "_"
		else:
			out += ch
	if out == "":
		out = "vlastni"
	return out


func save() -> bool:
	if name == "": 
		name = "vlastni"
	DirAccess.make_dir_recursive_absolute(storage_dir())
	var f := FileAccess.open(storage_dir() + storage_key() + ".zily", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_code())
	f.close()
	return true


func load_from_disk(key: String) -> bool:
	var path: String = storage_dir() + key + ".zily"
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var lv := Level.from_code(text)
	if lv == null:
		return false
	name = lv.name
	cols = lv.cols
	rows = lv.rows
	zone_dmg = lv.zone_dmg
	speed = lv.speed
	spawn = lv.spawn
	lives = lv.lives
	gold = lv.gold
	nodes = lv.nodes
	lanes = lv.lanes
	return true


static func saved_keys() -> Array:
	var out: Array = []
	var d := DirAccess.open(storage_dir())
	if d == null:
		return out
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".zily"):
			out.append(f.substr(0, f.length() - 5))
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


# =========================================================================
# POMOCNIK PRO STAVBU - pouziva ho zakladni deska i testy
# =========================================================================

func add_node(c: int, r: int, kind: int) -> int:
	nodes.append({"c": c, "r": r, "kind": kind})
	return nodes.size() - 1


# Nakresli usek z uzlu `a` do uzlu `b` po zadanych smerech.
# `dirs` je retezec "U R D L" - kde se cesta ohne. Zapisuje se bez pocatecni
# bunky (ta je bunka uzlu `a`) a bez koncove (ta je bunka uzlu `b`).
func add_lane(a: int, b: int, dirs: String, elem: int) -> int:
	var cells: Array = []
	var cur: Vector2i = node_cell(a)
	cells.append(cur)
	for ch in dirs:
		match ch:
			"U":
				cur = Vector2i(cur.x, cur.y - 1)
			"D":
				cur = Vector2i(cur.x, cur.y + 1)
			"L":
				cur = Vector2i(cur.x - 1, cur.y)
			"R":
				cur = Vector2i(cur.x + 1, cur.y)
			_:
				continue
		cells.append(cur)
	lanes.append({"cells": cells, "elem": elem, "entry": false, "slots": SLOTS})
	return lanes.size() - 1


# =========================================================================
# ZAKLADNI DESKA - na ni se kalibruje obtiznost
# =========================================================================

static func base() -> Level:
	var lv := Level.new()
	lv.name = "zakladni"
	# START vlevo, dve vyhybky v sérii, pet cílu vpravo.
	#
	#   rada 1  ohen     (6,1) --------------------> (21,1)
	#   rada 4                 zeme (11,4) --------> (21,4)
	#   rada 7  start (1,7) -> j1 (6,7) -> j2 (11,7) - neutr ---> (21,7)
	#   rada 10                vzduch (11,10) ------> (21,10)
	#   rada 13 voda     (6,13) -------------------> (21,13)
	#
	# DESKA JE PREPOCTENA NA HUSTSI MRIZKU 28x14 (puvodne 20x10, krok 0.4).
	# Drzi se stejnych POMERU, takze i vsechna vyladena cisla zustavaji:
	# cesta je v pixelech stejne dlouha (11 R bunek z 20 je 0.55 sirky,
	# 15 R bunek z 28 je 0.536) a poskozeni je "za CELE PROJETI useku", takze
	# na delce v pixelech vubec nezalezi. Rozestupy radku jsou 3/14 = 0.214
	# misto 2/10 = 0.20 - o chlup vic mista mezi pruhy.
	#
	# Poradi je dane tim, aby se cesty NEKRIZILY: kdo odbocuje vys, musi
	# odbocit drive (nalevo), a sestup zpet dolu ma vlastni sloupec.
	# Vsechny ctyri zivly + neutralni usek - na te same desce se da
	# kalibrovat cela matice poskozeni.
	var start := lv.add_node(1, 7, START)
	var j1 := lv.add_node(6, 7, VYHYBKA)
	# Druha vyhybka je na 12, ne na 11 (presne 11.2): usek mezi vyhybkami je
	# pak 6 bunek, tedy stejne siroky jako predtim (4 z 20 = 0.20). Pri 5
	# bunkach vysel uzsi nez driv a mista na nem se prerusovala (odhalil to
	# test rozlozeni) - zaokrouhleni na bunku se musi drzet POMERU.
	var j2 := lv.add_node(12, 7, VYHYBKA)
	var e_fire := lv.add_node(21, 1, CIL)
	var e_earth := lv.add_node(21, 4, CIL)
	var e_neutral := lv.add_node(21, 7, CIL)
	var e_air := lv.add_node(21, 10, CIL)
	var e_water := lv.add_node(21, 13, CIL)

	# VSTUPNI USEK JE KMEN. Je to jediny usek, ktery neposkozuje "od
	# prirody" - hrac po nem teprve prichazi, takze by kazda rana byla
	# zdarma. Barva i poskozeni si ted odpovidaji: sedy pruh, zadna rana.
	#
	# Smery se skladaji z opakovani, ne rucne: u hustsi mrizky se do
	# retezce "U U U" snadno napise o pismeno min a cesta pak minne
	# skonci o bunku vedle (tichy posun celeho levelu).
	lv.add_lane(start, j1, "R".repeat(5), KMEN)
	lv.add_lane(j1, e_fire, "U".repeat(6) + "R".repeat(15), Element.FIRE)
	lv.add_lane(j1, j2, "R".repeat(6), NEUTRAL)
	lv.add_lane(j1, e_water, "D".repeat(6) + "R".repeat(15), Element.WATER)
	lv.add_lane(j2, e_earth, "U".repeat(3) + "R".repeat(9), Element.EARTH)
	lv.add_lane(j2, e_air, "D".repeat(3) + "R".repeat(9), Element.AIR)
	lv.add_lane(j2, e_neutral, "R".repeat(9), NEUTRAL)

	for i in range(lv.lanes.size()):
		var ln: Dictionary = lv.lanes[i]
		ln["entry"] = lv.lane_start_node(i) == start
	return lv
