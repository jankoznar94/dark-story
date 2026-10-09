class_name Network
extends RefCounted

# Sit je cista GEOMETRIE: kmen (trunk), na jehoz konci je vyhybka,
# a z vyhybky vybihaji ctyri cilove koleje - kazda do sve svatyne.
# Zadna fyzika, zadne uzly ve scene - jen polyline a vzorkovani bodu.
#
# ROZVRZENI JE RESPONZIVNI, a to ve dvou rovinach:
#   * POZICE jsou zlomky plochy (x z sirky, y z vysky) -> sit vyplni displej
#     a na sirokem telefonu jsou koleje proste delsi. Zadny letterbox.
#   * VELIKOSTI (polomer veze, svatyne, tloustka linii) jdou z jednoho
#     meritka `scale` -> kruh zustane kruhem a veze se na zadnem displeji
#     nezacnou prekryvat.
#
# Mista na veze lezi az na ROVNEM useku u svatyne, kde jsou koleje od sebe
# daleko, ne na rozvetveni u vyhybky, kde se paprsky teprve rozbihaji.

const LANES := 4
# Kterym zivelem nese ktera kolej. Poradi je dane rozvrzenim (shora dolu).
# Ciselne hodnoty jsou zamerne literalni: GDScript neumi v `const` precist
# konstantu z jine tridy pres class_name. Test overuje, ze sedi s Element
# a ze je to permutace vsech zivlu.
const LANE_ELEMENTS := [0, 1, 2, 3]
const BASE_TOWER_R := 26.0
const BASE_SHRINE_R := 30.0
const BASE_SWITCH_R := 46.0
const SLOT_FRACTIONS := [0.20, 0.52, 0.85]

var area: Rect2 = Rect2()
var scale: float = 1.0
# Horni hrana ovladaciho pruhu. Do site vstupuje jako OMEZENI: zadny bod
# trasy ani popisek svatyně se nesmi kreslit do pruhu. Predava se jako
# parametr do build() - kdyby se nastavoval na hotove siti, prvni build
# by pocital se starym pruhem.
var bar_top: float = 1.0e9
var tower_r: float = BASE_TOWER_R
var shrine_r: float = BASE_SHRINE_R
var switch_r: float = BASE_SWITCH_R
var trunk_start: Vector2 = Vector2.ZERO
var merge: Vector2 = Vector2.ZERO
var hub: Vector2 = Vector2.ZERO
var trunk_len: float = 0.0
var lane_path: Array = []
var lane_len: Array = []
var slot_pos: Array = []
var shrine_pos: Array = []
var switch_lane: int = 0


func build(r: Rect2, scale_hint: float = 1.0, bar_top_hint: float = 1.0e9) -> void:
	area = r
	scale = scale_hint
	bar_top = bar_top_hint
	tower_r = BASE_TOWER_R * scale
	shrine_r = BASE_SHRINE_R * scale
	switch_r = BASE_SWITCH_R * scale

	var w: float = r.size.x
	var h: float = r.size.y

	trunk_start = Vector2(r.position.x - 24.0 * scale, r.position.y + h * 0.5)
	merge = Vector2(r.position.x + w * 0.295, r.position.y + h * 0.5)
	hub = Vector2(r.position.x + w * 0.332, r.position.y + h * 0.5)
	trunk_len = _poly_len(PackedVector2Array([trunk_start, merge]))

	var approach_x: float = r.position.x + w * 0.636
	var shrine_x: float = r.position.x + w * 0.955
	var run: float = shrine_x - approach_x

	lane_path = []
	lane_len = []
	slot_pos = []
	shrine_pos = []

	# Nejdřív řádky, pak teprve geometrie. Svatyně i s popiskem pod ní
	# musi zustat NAD ovladacim pruhem - kdyby ne, radky se stlaci k sobe.
	var label_room: float = 54.0 * scale + 10.0
	var y0: float = r.position.y + h * 0.10
	var y_last: float = r.position.y + h * (0.10 + 0.245 * float(LANES - 1))
	if y_last + label_room > bar_top:
		y_last = bar_top - label_room
	var y_step: float = (y_last - y0) / float(LANES - 1)

	for i in range(LANES):
		var sy: float = y0 + y_step * float(i)
		var path := PackedVector2Array([merge, hub, Vector2(approach_x, sy), Vector2(shrine_x, sy)])
		lane_path.append(path)
		lane_len.append(_poly_len(path))
		shrine_pos.append(Vector2(shrine_x, sy))
		var slots: Array = []
		for f in SLOT_FRACTIONS:
			slots.append(Vector2(approach_x + float(f) * run, sy))
		slot_pos.append(slots)


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


# Ktery zivel patri na tuhle kolej. VEZ LZE STAVET JEN NA KOLEJ TOHOTO
# ZIVLU - je to jedine pravidlo staveni a plati v obou smerech.
static func lane_element(lane: int) -> int:
	var e: int = LANE_ELEMENTS[lane]
	return e


# Muze na tuhle kolej tato vez? Jedno misto, kde se pravidlo vyhodnocuje.
static func lane_accepts(lane: int, element: int) -> bool:
	return element == lane_element(lane)


func slot_world(lane: int, slot: int) -> Vector2:
	var slots: Array = slot_pos[lane]
	var p: Vector2 = slots[slot]
	return p


func nearest_slot(world: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = tower_r * 1.5
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
	# Nejnizsi vzdalenost k TRASE (ne k pasu), protoze kandidatu je malo.
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


# Nejmensi vzdalenost mezi misty na vezech RŮZNÝCH kolejí. Testy tuhle
# hodnotu kontroluji, aby se veze po zmene rozvrzeni nezacaly prekryvat.
func min_cross_lane_slot_distance() -> float:
	var best: float = 99999.0
	for a in range(LANES):
		for b in range(a + 1, LANES):
			for sa in range(slot_count()):
				for sb in range(slot_count()):
					var d: float = slot_world(a, sa).distance_to(slot_world(b, sb))
					if d < best:
						best = d
	return best


func switch_hit(world: Vector2) -> bool:
	return merge.distance_to(world) <= switch_r


func lane_index_from_angle(world: Vector2) -> int:
	# Presnejsi volba: uhel od vyhybky ukazuje na cilovou kolej.
	var rel: Vector2 = world - merge
	if rel.length() < 4.0:
		return -1
	var best := -1
	var best_dot := -2.0
	for i in range(shrine_pos.size()):
		var dir: Vector2 = (shrine_pos[i] - merge).normalized()
		var dot: float = rel.normalized().dot(dir)
		if dot > best_dot:
			best_dot = dot
			best = i
	return best


func _poly_len(path: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(path.size() - 1):
		total += path[k].distance_to(path[k + 1])
	return total
