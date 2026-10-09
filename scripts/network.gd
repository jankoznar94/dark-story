class_name Network
extends RefCounted

# Sit je cista GEOMETRIE: kmen (trunk), na jehoz konci je vyhybka,
# a z vyhybky vybihaji ctyri cilove koleje - kazda do sve svatyne.
# Zadna fyzika, zadne uzdy ve scene - jen polyline a vzorkovani bodu.
#
# ROZVRZENI je zamerne takove, aby se veze na sousednich kolejich
# NEPREKRYVALY: mista na veze lezi az na rovnem useku u svatyne, kde
# jsou koleje od sebe 105 px, ne na rozvetveni u vyhybky, kde se
# paprsky teprve rozbihaji.

const LANES := 4
const TOWER_RADIUS := 26.0
const SWITCH_RADIUS := 46.0
# Vzdalenost mista na vez od svatyne, od nejblizsiho po nejvzdalenejsi.
const SLOT_FROM_SHRINE := [60.0, 165.0, 270.0]

var area: Rect2 = Rect2()
var trunk_start: Vector2 = Vector2.ZERO
var merge: Vector2 = Vector2.ZERO
var hub: Vector2 = Vector2.ZERO
var trunk_len: float = 0.0
var lane_path: Array = []
var lane_len: Array = []
var slot_pos: Array = []
var shrine_pos: Array = []
var switch_lane: int = 0


func build(r: Rect2) -> void:
	area = r
	var w: float = r.size.x
	var h: float = r.size.y

	trunk_start = Vector2(r.position.x - 24.0, r.position.y + h * 0.5)
	merge = Vector2(r.position.x + w * 0.295, r.position.y + h * 0.5)
	hub = merge + Vector2(w * 0.034, 0.0)
	trunk_len = _poly_len(PackedVector2Array([trunk_start, merge]))

	var approach_x: float = r.position.x + w * 0.636
	var shrine_x: float = r.position.x + w * 0.955

	lane_path = []
	lane_len = []
	slot_pos = []
	shrine_pos = []

	for i in range(LANES):
		var sy: float = r.position.y + h * (0.12 + 0.253 * float(i))
		var path := PackedVector2Array([merge, hub, Vector2(approach_x, sy), Vector2(shrine_x, sy)])
		lane_path.append(path)
		lane_len.append(_poly_len(path))
		shrine_pos.append(Vector2(shrine_x, sy))
		var slots: Array = []
		for d in SLOT_FROM_SHRINE:
			slots.append(Vector2(shrine_x - float(d), sy))
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
	return SLOT_FROM_SHRINE.size()


func slot_world(lane: int, slot: int) -> Vector2:
	var slots: Array = slot_pos[lane]
	var p: Vector2 = slots[slot]
	return p


func nearest_slot(world: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = TOWER_RADIUS * 1.5
	for lane in range(lane_path.size()):
		for slot in range(slot_count()):
			var d: float = slot_world(lane, slot).distance_to(world)
			if d < best_d:
				best_d = d
				best = Vector2i(lane, slot)
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
	return merge.distance_to(world) <= SWITCH_RADIUS


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
