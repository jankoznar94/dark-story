class_name Network
extends RefCounted

# Sit je cista GEOMETRIE postavena z LEVELU. Uz to nejsou "koleje do svatyni",
# ale USEKY:
#
#   [neutralni kmen] -> [vyhybka] -> [ELEMENTARNI USEK] -> [neutralni vystup]
#
# POŠKOZENI SE DEJE NA USEKU, ne ve vezi. Usek je dmg zona: cim dele
# poutnik po elementarnim useku jde, tim vic ran dostane. Kdo stoji na
# kterem useku, rozhoduje HRAC vyhybkou.
#
# ZADNA KOLEJ NEMUSI POSKOZOVAT VUBEC. Usek muze byt "harmless" - cesta bez
# ran. Je to zakladni level, ktery ma takto nastavenou prvni kolej.
#
# POSLEDNI PRUH JE NEUTRALNI: nepatri zadnemu zivlu, elementarni bonus
# na nem stat nemuze, ale poskozuje vsechny stejne (100 %). Je to
# spolehlivy zaklad - nikdy neublizi, nikdy nezvýhodni.
#
# KONEC: kazda kolej se za svym rovnym usekem ohne a slije se do jednoho
# z NEUTRALNICH VYSTUPU. Vystup nema element a nikdo ho "nevlastni" -
# poutnik, ktery tam dojde, stoji jeden zivot.
#
# ROZVRZENI JE RESPONZIVNI ve dvou rovinach:
#   * POZICE jsou zlomky plochy -> sit vyplni displej, zadny letterbox.
#   * VELIKOSTI jdou z jednoho meritka `scale` -> kruh zustane kruhem
#     a mista na bonusy se na zadnem displeji nezacnou prekryvat.
#
# KDE se ohne (divert) je cas levelu, ne konstanty: dve koleje se tak sbihaji
# na stejnem miste, treti se ohne hned za svym usekem. Kdyby to bylo pro vsechny
# stejne, kazda zmena poctu kolejí by posunula i ty ostatni.
#
# Vsechna cisla levelu jsou v Level; tady je jen preklad do pixelu.

const BASE_BONUS_R := 26.0
const BASE_EXIT_R := 30.0
const BASE_SWITCH_R := 46.0
const SLOT_FRACTIONS := [0.20, 0.52, 0.85]

var level: Level = null
var area: Rect2 = Rect2()
var scale: float = 1.0
# Horni hrana ovladaciho pruhu. Do site vstupuje jako OMEZENI: zadny bod
# trasy ani vystup se nesmi kreslit do pruhu. Predava se jako parametr do
# build() - kdyby se nastavoval na hotove siti, prvni build by pocital se
# starym pruhem.
var bar_top: float = 1.0e9
var bonus_r: float = BASE_BONUS_R
var exit_r: float = BASE_EXIT_R
var switch_r: float = BASE_SWITCH_R
var trunk_start: Vector2 = Vector2.ZERO
var merge: Vector2 = Vector2.ZERO
var hub: Vector2 = Vector2.ZERO
var trunk_len: float = 0.0
# Rovny usek kazde koleje - tady se kresli dmg zona i mista na bonusy.
var band_x0: float = 0.0
var band_x1: float = 0.0
var rows: Array = []
var lane_path: Array = []
var lane_len: Array = []
var lane_exit: Array = []
var slot_pos: Array = []
var exit_pos: Array = []
var switch_lane: int = 0


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

	trunk_start = Vector2(r.position.x - 24.0 * scale, r.position.y + h * 0.5)
	merge = Vector2(r.position.x + w * 0.22, r.position.y + h * 0.5)
	hub = Vector2(r.position.x + w * 0.25, r.position.y + h * 0.5)
	trunk_len = _poly_len(PackedVector2Array([trunk_start, merge]))

	# Rovny usek vsech kolejí je SPOLECNY - dmg zony tak stoji pres sebe a
	# hrac je vidi jako jednu mrizku. Kazda kolej se ohne az za nim.
	band_x0 = r.position.x + w * level.band0
	band_x1 = r.position.x + w * level.band1
	var exit_x: float = r.position.x + w * level.exit_x

	# Radky jsou uz hotove v levelu (Level.relayout je vystredi ve sve mrizce).
	# Tady se jen prelozi do pixelu a pripadne pritlaci nad pruh, aby rucka
	# nekreslila do ovladani.
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

	# Vystupy jsou DIRY V MAPE, ne vlastnictvi nejake koleje. Kdo tam dojde,
	# stoji zivot - a nikdo se na ne neda poslat "bezpecne".
	exit_pos = []
	for i in range(level.exits.size()):
		var p: Array = level.exits[i]
		exit_pos.append(Vector2(r.position.x + w * float(p[0]),
			r.position.y + h * float(p[1])))

	lane_path = []
	lane_len = []
	lane_exit = []
	slot_pos = []

	var run: float = band_x1 - band_x0
	for i in range(level.lane_count()):
		var ex: int = level.exit_of(i)
		# Existence vystupu je invariant site, ne něco, co se smi jen tak
		# rozbit: kdyby index prestrelil, hra by spadla az za behu.
		ex = clampi(ex, 0, exit_pos.size() - 1)
		lane_exit.append(ex)
		var y: float = float(rows[i])
		var dx: float = level.divert_x(i)
		var ey: float = r.position.y + h * level.exit_row(ex)
		var path := PackedVector2Array([
			merge, hub,
			Vector2(band_x0, y),
			Vector2(r.position.x + w * dx, y),
			Vector2(exit_x, ey),
		])
		lane_path.append(path)
		lane_len.append(_poly_len(path))
		var slots: Array = []
		for f in SLOT_FRACTIONS:
			slots.append(Vector2(band_x0 + float(f) * run, y))
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


func slot_world(lane: int, slot: int) -> Vector2:
	var slots: Array = slot_pos[lane]
	var p: Vector2 = slots[slot]
	return p


func lane_count() -> int:
	return lane_path.size()


# Je ta kolej neutralni? Nema element, elementarni bonus na ni
# stat nemuze, poskozuje vsechny stejne.
func lane_is_neutral(lane: int) -> bool:
	return level.is_neutral(lane)


# Ktery zivel patri na tuhle kolej. U neutralni vraci NEUTRAL (-1).
func lane_element(lane: int) -> int:
	return level.el_of(lane)


# Muze na tuhle kolej tento bonus? Jedno misto, kde se pravidlo vyhodnocuje.
# Na neutralni kolej nesmi NIC - ani neutralni bonus neexistuje, protoze
# neutralni usek uz poskozuje vsechny stejne a nema co posilovat. A na usek,
# ktery vubec neposkozuje, nema co posilovat tuplem.
func lane_accepts(lane: int, element: int) -> bool:
	return level.accepts(lane, element)


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


# Nejmensi vzdalenost mezi misty na bonusech RŮZNÝCH kolejích. Testy tuhle
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


func switch_hit(world: Vector2) -> bool:
	return merge.distance_to(world) <= switch_r


func _poly_len(path: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(path.size() - 1):
		total += path[k].distance_to(path[k + 1])
	return total