class_name Network
extends RefCounted

# Sit je PREKLAD MRIZKY DO PIXELU. Nic vic - zadne radky, zadne pasy,
# zadne automaticke rozvrhovani. Level rekne "bunky (2,5), (3,5), (4,5)"
# a tady se z toho stane cara.
#
# Dve veci, ktere z toho plynou:
#
#   * Mrizka VYPLNUJE CELOU ARENU: bunka je siroka arena.w/cols a vysoka
#     arena.h/rows, okraj nezustava zadny. Jan: "Pole by melo byt pres celou
#     sirku displeje." Cesty se tim sice natahnou do stran, ale protoze
#     vsechny vedou PO OSE, zustane kazdy ohyb pravym uhlem - natazeni po
#     ose pravy uhel nemeni.
#
#   * Usek zacina a konci ve STREDU bunky sveho uzlu. Diky tomu staci
#     poutnikovi pri prechodu z useku na usek "dosel jsem na konec ->
#     v uzlu vyber dalsi", bez vstupniho bodu a bez lane_entry_s.
#
#   * Usek ze startu se prodlouzi na okraj displeje a usek koncici v cili
#     take - poutnici maji PRICHÁZET JAKO ZPOZA DISPLEJE a v cili koncit
#     mimo nej (Jan). Delka trasy se tim zmeni, ale poskozeni je "za cele
#     projeti useku" (ZONE_DMG / traverse), takze se mechanika nemeni.
#
# Vsechna cisla levelu jsou v Level; tady je jen preklad do pixelu.

const BASE_EXIT_R := 30.0
const BASE_SWITCH_R := 46.0
# BUNKA PASU, KTERA JE U VYHYBKY NEBO SPOJKY, SE NESTAVA. Jan: "U vyhybek
# a spojek nemuze byt zadna v rozsahu 1 policka." Duvod je hratelnostni:
# uzel je to, co hrac macka (prepnout vyhybku), a vez postavena na nem by
# mu klepnuti kradla. Pas se tam proto ani nekresli - kreslit misto, kde se
# neda stavet, je lez (stejne pravidlo jako driv u kmene).
const STRIP_JUNCTION_CLEAR := 1

var level: Level = null
var area: Rect2 = Rect2()
var scale: float = 1.0
# Horni hrana, za kterou se nesmi kreslit. Do site vstupuje jako OMEZENI:
# mrizka se zmensi tak, aby se cela vesla nad ni.
var bar_top: float = 1.0e9
var exit_r: float = BASE_EXIT_R
var switch_r: float = BASE_SWITCH_R

# Preklad mrizky: velikost bunky v pixelech a levy horni roh mrizky.
# Bunka NENI ctvercova - mrizka vyplnuje arenu celou, takze sirka a vyska
# bunky jsou dve cisla. Kresleni i prepocet na bunku je pouzivaji obe.
var cell_w: float = 1.0
var cell_h: float = 1.0
var origin: Vector2 = Vector2.ZERO

# --- uzly
var node_pos: Array = []        # uzel -> Vector2 (stred bunky)
var node_kind: Array = []       # uzel -> Level.START / CIL / ...
var junction_nodes: Array = []  # poradi vyhybky -> index uzlu
var junction_of_node: Array = []  # uzel -> poradi vyhybky nebo -1

# --- useky
var lane_path: Array = []       # usek -> PackedVector2Array stredu bunek
var lane_len: Array = []        # usek -> delka v pixelech
var lane_from_node: Array = []
var lane_to_node: Array = []
var lanes_out: Array = []       # uzel -> seznam useku, ktere z nej vedou

# --- vyhybky z pohledu hrace
var junction_lanes: Array = []   # poradi vyhybky -> seznam useku, ktere z ni vedou
var lane_junction_idx: Array = []  # usek -> poradi vyhybky, ze ktere vede (-1 = zadna)
var lane_sel_index: Array = []     # usek -> poradi vystupu v ramci sve vyhybky

# Usek, kterym poutnici do mapy vstupuji. Nahrazuje stary "kmen".
var entry_lane: int = -1
# A VSEchny takove useky. Hra z nich strida (spawn_index % pocet), aby se
# druhy vstup nepromarnil - dnes je tu jeden (validace pripousti jediny
# START), ale kod se na to nesmi spolehat.
var entry_lanes: Array = []
var exit_pos: Array = []
# PAS KOLEM CESTY. Kazda cesta ma po obou stranach jednu bunku podbarvenou
# svym elementem (svetlejsim odstinem) a v tom pasu se stavi veze. Neni to
# kosmetika - je to CELA STAVEBNI PLOCHA hry.
#
# `strip_lane` je JEDNO misto, kde se rozhoduje, ktera cesta tu bunku
# podbarvuje: bunka muze lezet u dvou cest zaroven (dve paralelni trasy)
# a pak patri te, ktera ma vic sousednich bunek; pri rovnosti rozhoduje
# nizsi index useku. Hra, kresleni i klepnuti se musi ptat TOHOHLE slovniku -
# kdyby si to kazdy pocital sam, kreslil by pas jinde, nez kam se stavi.
var strip_lane: Dictionary = {}
var strip_cells: Array = []


func build(r: Rect2, scale_hint: float = 1.0, bar_top_hint: float = 1.0e9,
		level_data: Level = null) -> void:
	level = level_data if level_data != null else Level.base()
	area = r
	scale = scale_hint
	bar_top = bar_top_hint
	exit_r = BASE_EXIT_R * scale
	switch_r = BASE_SWITCH_R * scale

	var cols: int = maxi(level.cols, 1)
	var rows: int = maxi(level.rows, 1)
	var avail_w: float = maxf(r.size.x, 1.0)
	var avail_h: float = maxf(minf(r.size.y, bar_top - r.position.y), 1.0)
	# MRIZKA VYPLNUJE ARENU. Zadne okraje po stranach: pole je pres celou
	# sirku displeje a poutnici vstupuji z jeho okraje.
	cell_w = avail_w / float(cols)
	cell_h = avail_h / float(rows)
	if cell_w <= 0.0:
		cell_w = 1.0
	if cell_h <= 0.0:
		cell_h = 1.0
	origin = r.position

	# --- uzly
	node_pos = []
	node_kind = []
	for n in range(level.node_count()):
		var c: Vector2i = level.node_cell(n)
		node_pos.append(_cell_center(c.x, c.y))
		node_kind.append(level.node_kind(n))

	# --- useky
	lane_path = []
	lane_len = []
	lane_from_node = []
	lane_to_node = []
	for i in range(level.lane_count()):
		var pts := PackedVector2Array()
		var cs: Array = level.lane_cells(i)
		for cellv in cs:
			var v: Vector2i = cellv
			pts.append(_cell_center(v.x, v.y))
		lane_path.append(pts)
		lane_len.append(_poly_len(pts))
		lane_from_node.append(level.lane_start_node(i))
		lane_to_node.append(level.lane_end_node(i))

	lanes_out = []
	for n in range(level.node_count()):
		lanes_out.append(level.lanes_from(n))

	# --- vyhybky
	# Vyhybka je uzel druhu VYHYBKA. Hra si pro kazdou drzi svou volbu,
	# takze poradi vyhybek musi byt stabilni - proto se prochazi uzly
	# poporade.
	junction_nodes = []
	junction_of_node = []
	for n in range(level.node_count()):
		junction_of_node.append(-1)
	for n in range(level.node_count()):
		if level.node_kind(n) == Level.VYHYBKA:
			junction_of_node[n] = junction_nodes.size()
			junction_nodes.append(n)
	junction_lanes = []
	for j in range(junction_nodes.size()):
		junction_lanes.append(level.lanes_from(int(junction_nodes[j])))

	lane_junction_idx = []
	lane_sel_index = []
	for i in range(level.lane_count()):
		lane_junction_idx.append(-1)
		lane_sel_index.append(0)
	for j in range(junction_nodes.size()):
		var jl: Array = junction_lanes[j]
		for k in range(jl.size()):
			var idx: int = int(jl[k])
			if idx < 0 or idx >= lane_junction_idx.size():
				continue
			lane_junction_idx[idx] = j
			lane_sel_index[idx] = k

	# --- vstup do mapy
	# VSECHNY vstupni useky. Startu muze byt LIBOVOLNE MNOZSTVI (Jan: "Muze mit
	# libovolny pocet startu/vstupu"), takze se bere kazdy usek z kazdeho STARTu
	# a hra z nich losuje. `entry_lane` je prvni z nich a pouziva se jen tam, kde
	# je potreba jedno cislo (odhad delky kola).
	entry_lanes = []
	for n in range(level.node_count()):
		if level.node_kind(n) != Level.START:
			continue
		for ln in level.lanes_from(n):
			entry_lanes.append(int(ln))
	entry_lane = int(entry_lanes[0]) if not entry_lanes.is_empty() else -1

	# --- cile
	exit_pos = []
	for n in range(level.node_count()):
		if level.node_kind(n) == Level.CIL:
			exit_pos.append(node_pos[n])

	# --- poutnici vstupuji z okraje displeje a v cili z nej zase zmizi
	_extend_ends()

	# --- pas kolem cest: jedina stavebni plocha hry
	_build_strip()


# PAS KOLEM CESTY. Pro kazdou cestu se vezme osm okoli kazde jeji bunky
# (tedy 1 bunka na kazdou stranu vcetne rohu, aby se cesta v ohybu obalila)
# a z toho se stane stavebni plocha. Co do pasu NEPATRI:
#
#   * bunky samotnych cest (po ceste se chodi, nestavi),
#   * bunky uzlu (start, cil, vyhybka, spojka, uzel),
#   * bunky do 1 bunky od VYHYBKY a SPOJKY (Jan: "U vyhybek a spojek nemuze
#     byt zadna v rozsahu 1 policka") - uzel je tlacitko hrace,
#   * cely KMEN a VSECHNY VSTUPNI USEKY (Jan: "U kmene, vstupu, vyhybky
#     a spojky se nestavi.") - sedivy pruh kolem nich se proto ani nekresli,
#   * vsechno mimo mrizku.
#
# Kdyz bunku podbarvuji dve cesty, vyhrava ta s VIC SOUSEDNIMI bunkami; pri
# rovnosti nizsi index. Je to jedine misto, kde se to rozhoduje.
func _build_strip() -> void:
	strip_lane = {}
	strip_cells = []
	var blocked: Dictionary = {}
	for i in range(level.lane_count()):
		var cs: Array = level.lane_cells(i)
		for cellv in cs:
			blocked[cellv] = true
	for n in range(level.node_count()):
		blocked[level.node_cell(n)] = true
	var near_junction: Dictionary = {}
	var clear: int = STRIP_JUNCTION_CLEAR
	for n in range(level.node_count()):
		var k: int = level.node_kind(n)
		if k != Level.VYHYBKA and k != Level.SPOJKA:
			continue
		var nc: Vector2i = level.node_cell(n)
		for dx in range(-clear, clear + 1):
			for dy in range(-clear, clear + 1):
				near_junction[Vector2i(nc.x + dx, nc.y + dy)] = true

	# Kolik sousedu teto bunky patri konkretni ceste. Tim se rozhoduje
	# o spornych bunkach mezi dvema cestami.
	var best_count: Dictionary = {}
	for i in range(level.lane_count()):
		# KMEN NEMA PAS. Je to cesta bez elementu, po ktere poutnik teprve
		# prichazi - vez by tam nemela co delat (a barva by nemela vzjit).
		if level.lane_is_kmen(i):
			continue
		var lane_cells: Dictionary = {}
		var cs: Array = level.lane_cells(i)
		for cellv in cs:
			lane_cells[cellv] = true
		for cellv in cs:
			var c: Vector2i = cellv
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var t := Vector2i(c.x + dx, c.y + dy)
					if not level.in_bounds(t.x, t.y):
						continue
					if blocked.has(t) or near_junction.has(t):
						continue
					var n: int = int(best_count.get(t, -1))
					var cnt: int = 0
					for ddx in range(-1, 2):
						for ddy in range(-1, 2):
							if lane_cells.has(Vector2i(t.x + ddx, t.y + ddy)):
								cnt += 1
					if cnt > n:
						# Vetsi sousedstvi vyhrava; pri rovnosti zustava
						# ta prvni (tedy nizsi index useku).
						best_count[t] = cnt
						strip_lane[t] = i
	strip_cells = strip_lane.keys()
	strip_cells.sort()


# Je ta bunka stavebni plocha? Ptá se klepnuti, kresleni i pravidla stavby.
func strip_has(cell: Vector2i) -> bool:
	return strip_lane.has(cell)


# Ktera cesta tuhle bunku podbarvuje. -1 = bunka neni v pasu.
func strip_lane_of(cell: Vector2i) -> int:
	if not strip_lane.has(cell):
		return -1
	return int(strip_lane[cell])


# ELEMENT VEZE, KTERA NA TÉ BUNCE MUZE STAT. Neni to volba hrace: vez ma
# vzdycky element cesty, kolem ktere stoji (neutralni/sedy pas = neutralni
# vez, ktera dava fyzicke poskozeni vsem stejne).
func strip_element(cell: Vector2i) -> int:
	var lane: int = strip_lane_of(cell)
	if lane < 0:
		return Level.NEUTRAL
	return level.lane_element(lane)


# Kolik stavebnich bunek ma ta cesta. HUD z toho cte, kolik obrany u ni stoji.
func strip_cells_of_lane(lane: int) -> int:
	var c: int = 0
	for cellv in strip_cells:
		if int(strip_lane[cellv]) == lane:
			c += 1
	return c


# POUTNICI MAJI PRICHÁZET JAKO ZPOZA DISPLEJE a v cili koncit mimo nej.
# Usek ze startu se proto prodlouzi na okraj areny a kazdy usek, ktery konci
# v cili, se prodlouzi take. Delka trasy se tim zmeni, ale poskozeni je "za
# CELE PROJETI USEKU" (ZONE_DMG / traverse), takze se mechanika nemeni -
# jen cesta vede tam, kam hrac kouka.
func _extend_ends() -> void:
	for item in entry_lanes:
		var el: int = int(item)
		if el < 0 or el >= lane_path.size():
			continue
		var p: PackedVector2Array = lane_path[el]
		if p.size() < 2:
			continue
		var d: Vector2 = (p[1] - p[0]).normalized()
		var q: Vector2 = _border_point(p[0], -d)
		if q.distance_to(p[0]) > 0.5:
			var np := PackedVector2Array([q])
			np.append_array(p)
			lane_path[el] = np
	for i in range(lane_path.size()):
		if level.node_kind(lane_end_node(i)) != Level.CIL:
			continue
		var pl: PackedVector2Array = lane_path[i]
		if pl.size() < 2:
			continue
		var dr: Vector2 = (pl[pl.size() - 1] - pl[pl.size() - 2]).normalized()
		var qr: Vector2 = _border_point(pl[pl.size() - 1], dr)
		if qr.distance_to(pl[pl.size() - 1]) > 0.5:
			pl.append(qr)
			lane_path[i] = pl
	for i in range(lane_path.size()):
		lane_len[i] = _poly_len(lane_path[i])


# Bod na okraji areny ve smeru `dir` od bodu `from`. Usek se prodluzuje po
# ose, takze staci vzit tu osu, ve ktere je smer delsi.
func _border_point(from: Vector2, dir: Vector2) -> Vector2:
	if dir.length_squared() < 0.000001:
		return from
	if absf(dir.x) >= absf(dir.y):
		return Vector2(area.position.x if dir.x < 0.0 else area.end.x, from.y)
	return Vector2(from.x, area.position.y if dir.y < 0.0 else area.end.y)


# ROZDELENI MIST NA USEKU. Tri mista maji PRESNE sve stavebni hodnoty
# (zakladni deska se nesmi pohnout), jiny pocet se rozlozi rovnomerne mezi
# stejne okraje. Jedna funkce pro vsechno - kdyby si kazdy pocital sve,
# rozejdou se mista, na ktera hrac klepne, od tech, ktera vidi.
func _cell_center(c: int, r: int) -> Vector2:
	return origin + Vector2((float(c) + 0.5) * cell_w, (float(r) + 0.5) * cell_h)


# STRED BUNKY PRO KRESLENI. Verejne proto, ze si ho kresleni veze a testy
# nesmi pocitat samy - kdyby si kazdy pocital svuj, vez by stala jinde, nez
# kam se klepe.
func cell_center(cell: Vector2i) -> Vector2:
	return _cell_center(cell.x, cell.y)


# Ktera bunka mrizky je pod timhle bodem. Editor z toho kresli - hrac
# klepne nebo taha prstem a hra potrebuje vedet, na kterou bunku to padlo.
func cell_at(world: Vector2) -> Vector2i:
	var cw: float = maxf(cell_w, 0.001)
	var ch: float = maxf(cell_h, 0.001)
	return Vector2i(int(floor((world.x - origin.x) / cw)),
		int(floor((world.y - origin.y) / ch)))


# =========================================================================
# POHYB PO TRASE
# =========================================================================

func point_at(lane: int, s: float) -> Vector2:
	if lane < 0 or lane >= lane_path.size():
		return Vector2.ZERO
	var path: PackedVector2Array = lane_path[lane]
	if path.is_empty():
		return Vector2.ZERO
	var want: float = s
	for k in range(path.size() - 1):
		var a: Vector2 = path[k]
		var b: Vector2 = path[k + 1]
		var seg: float = a.distance_to(b)
		if want <= seg or k == path.size() - 2:
			if seg <= 0.0001:
				return b
			return a.lerp(b, clampf(want / seg, 0.0, 1.0))
		want -= seg
	return path[path.size() - 1]


func lane_count() -> int:
	return lane_path.size()


func junction_count() -> int:
	return junction_lanes.size()


# Uzel, ve kterem usek konci. Tam se poutnik rozhoduje.
func lane_end_node(lane: int) -> int:
	if lane < 0 or lane >= lane_to_node.size():
		return -1
	return int(lane_to_node[lane])


func node_world(n: int) -> Vector2:
	if n < 0 or n >= node_pos.size():
		return Vector2.ZERO
	return node_pos[n]


func node_is_junction(n: int) -> bool:
	return junction_index_of_node(n) >= 0


func junction_index_of_node(n: int) -> int:
	if n < 0 or n >= junction_of_node.size():
		return -1
	return int(junction_of_node[n])


# =========================================================================
# CO CTE HRA
# =========================================================================

func lane_is_neutral(lane: int) -> bool:
	return level.lane_is_neutral(lane)


# USEK BEZ POSKOZENI (kmen). Chybela tu a volala se z game_view i game.gd:
# kazde volani spadlo na "Nonexistent function" a GDScript po takove chybe
# UKONCI funkci, ktera ji zavolala - `_lane_color` pak vratila null, barva
# vysla cerna a cely pruh se kreslil cerny. Chyba se netykala jen kmene:
# volani bylo pro kazdy usek, ktery neni neutralni.
func lane_is_kmen(lane: int) -> bool:
	return level.lane_is_kmen(lane)


func lane_element(lane: int) -> int:
	return level.lane_element(lane)


# Usek, ze ktereho poutnici vstupuji do mapy. Neposkrzuje sam o sobe -
# rozhoduje hodnota useku (vstupni usek je od vychoziho stavu KMEN).
# VSTUPU MUZE BYT VIC (startu je libovolne mnozstvi), takze se ptame na
# seznam - driv tu bylo "lane == entry_lane" a druhy vstup by se tváril
# jako normalni poskozujici usek.
func lane_is_entry(lane: int) -> bool:
	return entry_lanes.has(lane)


# Ktera vyhybka ten usek posila. Hrac na usek klepne a prepne tim SVOU vyhybku.
func lane_junction(lane: int) -> int:
	if lane < 0 or lane >= lane_junction_idx.size():
		return -1
	return int(lane_junction_idx[lane])


# Usek, ktery z vyhybky vede v poradi `k`.
func junction_lane(j: int, k: int) -> int:
	if j < 0 or j >= junction_lanes.size():
		return -1
	var jl: Array = junction_lanes[j]
	if k < 0 or k >= jl.size():
		return -1
	return int(jl[k])


# KTERY USEK JE POD PRSTEM. Klepnuti na usek je jediny zpusob, jak
# prepnout vyhybku - tlacitka nejsou, protoze casem bude vyhybek vic, nez
# se jich do pruhu vejde. Vraci -1, kdyz je klepnuto mimo vsechny useky.
func lane_tap_at(world: Vector2, tol: float = 14.0) -> int:
	# NEJDRIV MEZI USEKY, KTERE VEDOU Z VYHYBKY. Ve stredu uzlu se potkava
	# vstupni usek s vystupnimi a vsechny jsou od nej stejne daleko - bez
	# tohoto poradi klepnuti na vyhybku trefí usek, ktery do ni jen vstupuje,
	# a hrac prepne neco jineho, nez na co klepnul.
	var best := -1
	var best_d: float = tol
	for lane in range(lane_path.size()):
		if lane_junction(lane) < 0:
			continue
		var d: float = _dist_to_path(lane, world)
		if d < best_d:
			best_d = d
			best = lane
	if best >= 0:
		return best
	# Vstupy do mapy a podobne se hledaji az potom - neda se na nich nic
	# prepnout, ale hrac na ne muze klepnout a nesmi to spadnout.
	for lane in range(lane_path.size()):
		var d: float = _dist_to_path(lane, world)
		if d < best_d:
			best_d = d
			best = lane
	return best


# KLEPNUTI NA UZEL VYHYBKY. Kruh je to, co hrac vidi jako tlacitko, takze
# klepnuti na nej musi zabrat na prvni pokus. Hledat pritom nejblizsi usek
# by nestacilo: v uzlu se vstupni usek potkava s vystupnimi a vsechny jsou
# od stredu stejne daleko, takze by klepnuti mohlo trefit usek, ktery do
# vyhybky jen vstupuje.
func junction_tap_at(world: Vector2, tol: float = 30.0) -> int:
	var best := -1
	var best_d: float = tol
	for j in range(junction_nodes.size()):
		var p: Vector2 = node_pos[int(junction_nodes[j])]
		var d: float = p.distance_to(world)
		if d < best_d:
			best_d = d
			best = j
	return best


func _dist_to_path(lane: int, world: Vector2) -> float:
	var path: PackedVector2Array = lane_path[lane]
	var best: float = 1.0e9
	for k in range(path.size() - 1):
		var a: Vector2 = path[k]
		var b: Vector2 = path[k + 1]
		var ab: Vector2 = b - a
		var t: float = 0.0
		if ab.length_squared() > 0.000001:
			t = clampf((world - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, world.distance_to(a + ab * t))
	return best


func _poly_len(path: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(path.size() - 1):
		total += path[k].distance_to(path[k + 1])
	return total
