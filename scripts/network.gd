class_name Network
extends RefCounted

# Sit je cista GEOMETRIE postavena z LEVELU. Uz to nejsou "koleje do svatyni",
# ale USEKY a VYHYBKY:
#
#   [kmenný úsek] -> [VÝHYBKA 0] -> [ÚSEK] -> [VÝSTUP]
#                                  \-------> [VÝHYBKA 1] -> [ÚSEK] -> [VÝSTUP]
#                                                          \----> [ÚSEK] -> [VÝSTUP]
#
# POSKOZENI SE DEJE NA USEKU, ne ve vezi. Usek je dmg zona: cim dele poutnik
# po useku jde, tim vic ran dostane. Kdo stoji na kterem useku, rozhoduje
# HRAC - klepnutim na usek se prepne vyhybka, ze ktere ten usek vede. Kdyz
# vyhybek vic, kazda si drzi svou volbu: klepnuti na usek prepne tu svou.
#
# ZADNA KOLEJ NEMUSI POSKOZOVAT VUBEC. Usek muze byt neutralni - bere vsem
# presne 100 %, takze je to spolehlivy zaklad, i kdyz nikoho nezabije.
#
# KONEC: usek vede bud do NEUTRALNIHO VYSTUPU (dira v mape, nikdo ji
# "nevlastni", kdo tam dojde stoji zivot), nebo do dalsi VYHYBKY.
#
# ROZVRZENI JE RESPONZIVNI ve dvou rovinach:
#   * POZICE jsou zlomky plochy -> sit vyplni displej, zadny letterbox.
#   * VELIKOSTI jdou z jednoho meritka `scale` -> kruh zustane kruhem
#     a mista na bonusy se na zadnem displeji nezacnou prekryvat.
#
# ROVNY USEK (kde stoji bonusy a kresli se dmg zona) se pocita Z KAZDEHO USEKU
# ZVLAST: je to pas mezi jeho vyhybkou a jeho cilem. Zakladni deska z toho
# vyjde presne na svuj vyladeny pas 0.40..0.80, ale druha vyhybka si posune
# svuj pas dal od kraje - jinak by jeji useky nemely kam kreslit bonusy.
#
# Vsechna cisla levelu jsou v Level; tady je jen preklad do pixelu.

const BASE_BONUS_R := 26.0
const BASE_EXIT_R := 30.0
const BASE_SWITCH_R := 46.0
const SLOT_FRACTIONS := [0.20, 0.52, 0.85]
# Nejmensi delka rovneho useku v pixelech. Z levelu se da vyrobit i usek tak
# kratky, ze by se na nem bonusy slepily pres sebe; tady se to zastavi na
# kreslitelne mezi.
const MIN_RUN_PX := 60.0

var level: Level = null
var area: Rect2 = Rect2()
var scale: float = 1.0
# Horni hrana, za kterou se nesmi kreslit. Do site vstupuje jako OMEZENI:
# zadny bod trasy ani vystup se nesmi kreslit za ni. Predava se jako parametr
# do build() - kdyby se nastavoval na hotove siti, prvni build by pocital se
# starym okrajem.
var bar_top: float = 1.0e9
var bonus_r: float = BASE_BONUS_R
var exit_r: float = BASE_EXIT_R
var switch_r: float = BASE_SWITCH_R
var trunk_start: Vector2 = Vector2.ZERO
# Vstup do prvni vyhybky a jeji stred. `merge` je bod, kde konci privodni
# usek; z nej vede kratky kmen do stredu ventilatoru (`hub`). Kazda vyhybka
# ma svou dvojici - vyhybka cislo j je na junction_pos[j] / junction_merge[j].
var merge: Vector2 = Vector2.ZERO
var hub: Vector2 = Vector2.ZERO
var trunk_len: float = 0.0
var band_x0: float = 0.0
var band_x1: float = 0.0
var rows: Array = []
var lane_path: Array = []
var lane_len: Array = []
# Vystup, do ktereho usek usti. -1, kdyz usek vede do dalsi vyhybky.
var lane_exit: Array = []
# Kam usek vede (stejne kodovani jako v Levelu) a ze ktere vyhybky vede.
var lane_to: Array = []
var lane_from: Array = []
# Ktere vetve sve vyhybky ten usek je - potrebuje hra, aby vedela, co prepnout.
var lane_sel_index: Array = []
# Rovny usek kazdeho useku: [x0, x1]. Tady stoji bonusy a kresli se dmg zona.
var lane_run: Array = []
var slot_pos: Array = []
var exit_pos: Array = []
# Vyhybky. junction_lanes[j] jsou indexy useku, ktere z ni vedou.
var junction_pos: Array = []
var junction_merge: Array = []
var junction_lanes: Array = []


func build(r: Rect2, scale_hint: float = 1.0, bar_top_hint: float = 1.0e9,
		level_data: Level = null) -> void:
	level = level_data if level_data != null else Level.base()
	area = r
	scale = scale_hint
	bar_top = bar_top_hint
	bonus_r = BASE_BONUS_R * scale
	exit_r = BASE_EXIT_R * scale
	switch_r = BASE_SWITCH_R * scale

	var w: float = r.size.x
	var h: float = r.size.y

	# --- vyhybky ---
	# X z hloubky (kazda dalsi stoji dal od kraje, aby jeji useky mely pred
	# vystupy misto), Y ze mrizky radku. Stred ventilatoru je to, co hrac
	# vidi; privodni usek konci o kus driv (MERGE_GAP).
	junction_pos = []
	junction_merge = []
	for j in range(level.junction_count()):
		var jx: float = r.position.x + w * level.junction_x(j)
		var jy: float = r.position.y + h * level.junction_row(j)
		junction_pos.append(Vector2(jx, jy))
		junction_merge.append(Vector2(jx - w * Level.MERGE_GAP, jy))
	merge = junction_merge[0]
	hub = junction_pos[0]
	trunk_start = Vector2(r.position.x - 24.0 * scale, hub.y)
	trunk_len = _poly_len(PackedVector2Array([trunk_start, merge]))

	# --- radky useku ---
	# Radky jsou uz hotove v levelu (Level.relayout je vystredi ve sve mrizce).
	# Tady se jen prelozi do pixelu a pripadne pritlaci nad spodni okraj, aby
	# rucka nekreslila mimo plochu.
	var label_room: float = 12.0 * scale
	var y_last_max: float = bar_top - label_room
	rows = []
	var shift: float = 0.0
	for i in range(level.lane_count()):
		var y: float = r.position.y + h * level.row_of(i)
		rows.append(y)
		shift = maxf(shift, y - y_last_max)
	if shift > 0.0:
		for i in range(rows.size()):
			rows[i] = float(rows[i]) - shift
		for j in range(junction_pos.size()):
			var p: Vector2 = junction_pos[j]
			var m: Vector2 = junction_merge[j]
			junction_pos[j] = p - Vector2(0.0, shift)
			junction_merge[j] = m - Vector2(0.0, shift)
		merge = junction_merge[0]
		hub = junction_pos[0]
		trunk_start = Vector2(trunk_start.x, hub.y)

	# --- vystupy ---
	# Vystupy jsou DIRY V MAPE, ne vlastnictvi nejakeho useku. Kdo tam dojde,
	# stoji zivot - a nikdo se na ne neda poslat "bezpecne".
	exit_pos = []
	for i in range(level.exits.size()):
		var p: Array = level.exits[i]
		var v := Vector2(r.position.x + w * float(p[0]), r.position.y + h * float(p[1]))
		if shift > 0.0:
			v = v - Vector2(0.0, shift)
		exit_pos.append(v)

	# --- useky ---
	lane_path = []
	lane_len = []
	lane_exit = []
	lane_to = []
	lane_from = []
	lane_sel_index = []
	lane_run = []
	slot_pos = []
	junction_lanes = []
	for j in range(level.junction_count()):
		var jl: Array = level.lanes_of(j)
		junction_lanes.append(jl)
		for k in range(jl.size()):
			var idx: int = int(jl[k])
			while lane_sel_index.size() <= idx:
				lane_sel_index.append(0)
			lane_sel_index[idx] = k

	var run0: Array = []
	for i in range(level.lane_count()):
		var src_j: int = level.from_of(i)
		src_j = clampi(src_j, 0, maxi(junction_pos.size() - 1, 0))
		var hubp: Vector2 = junction_pos[src_j]
		var mergep: Vector2 = junction_merge[src_j]
		var to: int = level.to_of(i)
		# Cil: vystup, nebo privodni bod dalsi vyhybky. Kdyz usek konci
		# u vyhybky, konci PRESNE tam, kde zacina jeji privodni usek - poutnik
		# tak plynule prejde z jednoho useku na druhy.
		var target: Vector2
		if to >= 0:
			target = exit_pos[clampi(to, 0, maxi(exit_pos.size() - 1, 0))]
		else:
			target = junction_merge[clampi(-1 - to, 0, maxi(junction_merge.size() - 1, 0))]
		# Rovny usek: podil cesty pred ohybem a za nim.
		var span_px: float = target.x - hubp.x
		var frac: float = Level.RUN_FRAC if to >= 0 else Level.RUN_FRAC_CONNECTOR
		var x0: float = hubp.x + span_px * frac
		var x1: float = target.x - span_px * frac
		if x1 < x0 + MIN_RUN_PX * scale:
			x1 = x0 + MIN_RUN_PX * scale
		var y: float = float(rows[i])
		var dx: float = lerp(x0, x1, level.divert_of(i))
		var path := PackedVector2Array([
			mergep, hubp,
			Vector2(x0, y),
			Vector2(dx, y),
			target,
		])
		lane_path.append(path)
		lane_len.append(_poly_len(path))
		lane_exit.append(to if to >= 0 else -1)
		lane_to.append(to)
		lane_from.append(src_j)
		lane_run.append([x0, x1])
		if i == 0:
			run0 = [x0, x1]
		var slots: Array = []
		for f in SLOT_FRACTIONS:
			slots.append(Vector2(x0 + float(f) * (x1 - x0), y))
		slot_pos.append(slots)
	# Pas prvniho useku. Je tu pro testy a pro kresleni zakladni desky.
	band_x0 = float(run0[0]) if run0.size() == 2 else 0.0
	band_x1 = float(run0[1]) if run0.size() == 2 else 0.0


func point_at(lane: int, s: float) -> Vector2:
	var path: PackedVector2Array = lane_path[lane]
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


func trunk_point_at(s: float) -> Vector2:
	var t: float = clampf(s / maxf(trunk_len, 0.0001), 0.0, 1.0)
	return trunk_start.lerp(merge, t)


func slot_count() -> int:
	return SLOT_FRACTIONS.size()


func slot_world(lane: int, slot: int) -> Vector2:
	var slots: Array = slot_pos[lane]
	var p: Vector2 = slots[slot]
	return p


func lane_count() -> int:
	return lane_path.size()


func junction_count() -> int:
	return junction_lanes.size()


# Je ta kolej neutralni? Nema element, elementarni bonus na ni
# stat nemuze, poskozuje vsechny stejne.
func lane_is_neutral(lane: int) -> bool:
	return level.is_neutral(lane)


# Ktery zivel patri na tuhle kolej. U neutralni vraci NEUTRAL (-1).
func lane_element(lane: int) -> int:
	return level.el_of(lane)


# Muze na tuhle kolej tento bonus? Jedno misto, kde se pravidlo vyhodnocuje.
func lane_accepts(lane: int, element: int) -> bool:
	return level.accepts(lane, element)


# Ktera vyhybka ten usek posila. Hrac na usek klepne a prepne tim SVOU vyhybku.
func lane_junction(lane: int) -> int:
	if lane < 0 or lane >= lane_from.size():
		return -1
	return int(lane_from[lane])


# Usek, ktery z vyhybky vede v poradi `k`.
func junction_lane(j: int, k: int) -> int:
	if j < 0 or j >= junction_lanes.size():
		return -1
	var jl: Array = junction_lanes[j]
	if k < 0 or k >= jl.size():
		return -1
	return int(jl[k])


# Usek, ktery z vyhybky vede do jejiho stredu - to je ta "kmenova" vetev,
# ktera se kresli jako pokracovani privodniho useku.
func junction_hub_lane(j: int) -> int:
	if j < 0 or j >= junction_lanes.size():
		return -1
	var jl: Array = junction_lanes[j]
	if jl.is_empty():
		return -1
	var best: int = int(jl[0])
	var best_d: float = 1.0e9
	for item in jl:
		var idx: int = int(item)
		var d: float = absf(float(rows[idx]) - junction_pos[j].y)
		if d < best_d:
			best_d = d
			best = idx
	return best


func nearest_slot(world: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = bonus_r * 1.5
	for lane in range(lane_path.size()):
		for slot in range(slot_count()):
			var d: float = slot_world(lane, slot).distance_to(world)
			if d < best_d:
				best_d = d
				best = Vector2i(lane, slot)
	return best


# KTERA KOLEJ JE POD PRSTEM. Klepnuti na kolej je jediny zpusob, jak
# prepnout vyhybku - tlacitka nejsou, protoze casem bude vyhybek vic, nez
# se jich do pruhu vejde. Vraci -1, kdyz je klepnuto mimo vsechny koleje.
# `tol` je polovicni sirka pasu kolem linie: male prsty trefuji nepresne
# a kolej je jen par pixelu sila.
func lane_tap_at(world: Vector2, tol: float = 14.0) -> int:
	var best := -1
	var best_d: float = tol
	for lane in range(lane_path.size()):
		var d: float = _dist_to_path(lane, world)
		if d < best_d:
			best_d = d
			best = lane
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


# Nejmensi vzdalenost mezi misty na bonusech RŮZNÝCH usecích. Testy tuhle
# hodnotu kontroluji, aby se bonusy po zmene rozvrzeni nezacaly prekryvat.
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
