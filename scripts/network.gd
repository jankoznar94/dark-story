class_name Network
extends RefCounted

# Sit je PREKLAD MRIZKY DO PIXELU. Nic vic - zadne radky, zadne pasy,
# zadne automaticke rozvrhovani. Level rekne "bunky (2,5), (3,5), (4,5)"
# a tady se z toho stane cara.
#
# Dve veci, ktere z toho plynou:
#
#   * Bunka je VZDY ctvercova: `cell = min(arena.w/cols, arena.h/rows)` a
#     mrizka se centruje. Kdyby se natahovala po ose, z ohybu, ktery hrac
#     nakreslil, by se stalo neco jineho - a na sirokem displeji by se
#     cesty roztahly do stran.
#
#   * Usek zacina a konci ve STREDU bunky sveho uzlu. Diky tomu staci
#     poutnikovi pri prechodu z useku na usek "dosel jsem na konec ->
#     v uzlu vyber dalsi", bez vstupniho bodu a bez lane_entry_s.
#
# Vsechna cisla levelu jsou v Level; tady je jen preklad do pixelu.

const BASE_BONUS_R := 26.0
const BASE_EXIT_R := 30.0
const BASE_SWITCH_R := 46.0
# Kde na useku stoji bonusy. Podil DELKY useku - na rozdil od stareho
# modelu se nehleda "rovny usek", protoze v mrizce rovny usek neni:
# cesta se ohne, kde hrac chce.
const SLOT_FRACTIONS := [0.20, 0.52, 0.85]

var level: Level = null
var area: Rect2 = Rect2()
var scale: float = 1.0
# Horni hrana, za kterou se nesmi kreslit. Do site vstupuje jako OMEZENI:
# mrizka se zmensi tak, aby se cela vesla nad ni.
var bar_top: float = 1.0e9
var bonus_r: float = BASE_BONUS_R
var exit_r: float = BASE_EXIT_R
var switch_r: float = BASE_SWITCH_R

# Preklad mrizky: velikost bunky v pixelech a levy horni roh mrizky.
var cell: float = 1.0
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
var exit_pos: Array = []
var slot_pos: Array = []


func build(r: Rect2, scale_hint: float = 1.0, bar_top_hint: float = 1.0e9,
		level_data: Level = null) -> void:
	level = level_data if level_data != null else Level.base()
	area = r
	scale = scale_hint
	bar_top = bar_top_hint
	bonus_r = BASE_BONUS_R * scale
	exit_r = BASE_EXIT_R * scale
	switch_r = BASE_SWITCH_R * scale

	var cols: int = maxi(level.cols, 1)
	var rows: int = maxi(level.rows, 1)
	var avail_w: float = maxf(r.size.x, 1.0)
	var avail_h: float = maxf(minf(r.size.y, bar_top - r.position.y), 1.0)
	cell = minf(avail_w / float(cols), avail_h / float(rows))
	if cell <= 0.0:
		cell = 1.0
	var gw: float = cell * float(cols)
	var gh: float = cell * float(rows)
	origin = r.position + Vector2((avail_w - gw) * 0.5, (avail_h - gh) * 0.5)

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
	entry_lane = -1
	var st: int = level.first_start()
	if st >= 0:
		var outs: Array = level.lanes_from(st)
		if not outs.is_empty():
			entry_lane = int(outs[0])

	# --- cile
	exit_pos = []
	for n in range(level.node_count()):
		if level.node_kind(n) == Level.CIL:
			exit_pos.append(node_pos[n])

	# --- mista na bonusy
	slot_pos = []
	for i in range(level.lane_count()):
		var slots: Array = []
		var total: float = maxf(float(lane_len[i]), 0.001)
		for f in SLOT_FRACTIONS:
			slots.append(point_at(i, float(f) * total))
		slot_pos.append(slots)


func _cell_center(c: int, r: int) -> Vector2:
	return origin + Vector2((float(c) + 0.5) * cell, (float(r) + 0.5) * cell)


# Ktera bunka mrizky je pod timhle bodem. Editor z toho kresli - hrac
# klepne nebo taha prstem a hra potrebuje vedet, na kterou bunku to padlo.
func cell_at(world: Vector2) -> Vector2i:
	var cs: float = maxf(cell, 0.001)
	return Vector2i(int(floor((world.x - origin.x) / cs)),
		int(floor((world.y - origin.y) / cs)))


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


func lane_element(lane: int) -> int:
	return level.lane_element(lane)


func lane_accepts(lane: int, element: int) -> bool:
	return level.lane_accepts(lane, element)


# Usek, ze ktereho poutnici vstupuji do mapy. Neposkzuje - poutnik teprve
# prichazi, hrac jeste nemel jakkoli sanci neco udelat.
func lane_is_entry(lane: int) -> bool:
	return lane == entry_lane


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


func slot_count() -> int:
	return SLOT_FRACTIONS.size()


func slot_world(lane: int, slot: int) -> Vector2:
	if lane < 0 or lane >= slot_pos.size():
		return Vector2.ZERO
	var slots: Array = slot_pos[lane]
	if slot < 0 or slot >= slots.size():
		return Vector2.ZERO
	var p: Vector2 = slots[slot]
	return p


func nearest_slot(world: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = bonus_r * 1.5
	for lane in range(slot_pos.size()):
		for slot in range(slot_count()):
			var d: float = slot_world(lane, slot).distance_to(world)
			if d < best_d:
				best_d = d
				best = Vector2i(lane, slot)
	return best


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


# Nejmensi vzdalenost mezi misty na bonusech RUZNYCH useku. V mrizce se
# useky nekrizi, takze by to melo vyjit vzdy aspon na jednu bunkovou mezeru;
# testy tuhle hodnotu kontroluji.
func min_cross_lane_slot_distance() -> float:
	var n: int = lane_path.size()
	var best: float = 99999.0
	for a in range(n):
		for b in range(a + 1, n):
			for sa in range(slot_count()):
				for sb in range(slot_count()):
					var d: float = slot_world(a, sa).distance_to(slot_world(b, sb))
					if d < best:
						best = d
	return best


func _poly_len(path: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(path.size() - 1):
		total += path[k].distance_to(path[k + 1])
	return total
