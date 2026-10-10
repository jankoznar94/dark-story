extends SceneTree

# Test ROZLOZENI: hra musi byt hratelna na kazdem telefone, ne jen vypadat
# dobre. Vystup: LAYOUT_ALL_PASS=true / false
#
# Mrizka ma pevny pocet bunek, takze se do areny VZDY vejde - to je dana
# vec. Co se ale overit da a co se opravdu kazi, je:
#   * ze cesty zustanou v arene a nad hornim panelem,
#   * ze mista na bonusy se neprekryvaji,
#   * ze klepnuti na stred vyhybky opravdu prepne TU vyhybku a ne jinou,
#   * ze klepnuti na stred mista na bonus vybere to misto.
# Posledni dve jsou meritka HRATELNOSTI: klepnuti se hleda podle vzdalenosti
# k trase a ta zavisi na rozliseni, takze se to na malem displeji muze
# rozbit, i kdyz obrazek vypada stejne.

const RESOLUTIONS := [
	[640, 360],   # nejmensi podporovany
	[800, 360],
	[854, 384],
	[932, 430],   # typicky telefon na sirku
	[960, 540],
	[960, 600],
	[1024, 600],
	[1080, 480],
	[1280, 600],
	[1280, 720],
	[1366, 768],
	[1440, 600],
	[1600, 720],
	[1920, 1080],
]

var fails: Array = []
var checks: int = 0


func _init() -> void:
	for r in RESOLUTIONS:
		_one(r[0], r[1])
	if fails.is_empty():
		print("LAYOUT_ALL_PASS=true (%d kontrol)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("LAYOUT_ALL_PASS=false (%d kontrol)" % checks)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)


# Lezi bod na okraji displeje (areny)? Pouziva se na vstup a cile: poutnici
# maji prichazet z okraje a v cili z nej zase zmizet.
func _on_border(p: Vector2, a: Rect2) -> bool:
	return absf(p.x - a.position.x) < 1.0 or absf(p.x - a.end.x) < 1.0 \
		or absf(p.y - a.position.y) < 1.0 or absf(p.y - a.end.y) < 1.0


func _one(w: int, h: int) -> void:
	var tag: String = "%dx%d" % [w, h]
	var layout := ScreenLayout.new()
	layout.compute(Vector2(float(w), float(h)))
	_check(layout.arena.size.x > 0.0 and layout.arena.size.y > 0.0,
		"%s: arena je prazdna" % tag)
	var g := Game.new()
	g.auto_wave = false
	g.setup(layout.arena, layout.s, layout.board_bottom, Level.base())

	# --- mrizka a cesty zustanou v arene. POLE VYPLNUJE ARENU CELOU:
	# zadny okraj po stranach, jinak by hrac prisel o kus displeje a
	# poutnici by se objevovali uprostred, ne na okraji.
	var o: Vector2 = g.net.origin
	var gw: float = g.net.cell_w * float(g.net.level.cols)
	var gh: float = g.net.cell_h * float(g.net.level.rows)
	_check(absf(o.x - layout.arena.position.x) < 1.0,
		"%s: pole nezacina na levem okraji (%.1f vs %.1f)" % [tag, o.x, layout.arena.position.x])
	_check(absf(gw - layout.arena.size.x) < 1.5,
		"%s: pole nevyplnuje sirku displeje (%.1f z %.1f)" % [tag, gw, layout.arena.size.x])
	_check(o.y >= layout.arena.position.y - 1.0, "%s: mrizka zacina nad areny" % tag)
	_check(o.y + gh <= layout.arena.end.y + 1.5, "%s: mrizka pretekla dolu" % tag)
	_check(minf(g.net.cell_w, g.net.cell_h) > 8.0,
		"%s: bunka je jen %.1f x %.1f px" % [tag, g.net.cell_w, g.net.cell_h])
	for lane in range(g.net.lane_count()):
		var path: PackedVector2Array = g.net.lane_path[lane]
		for p in path:
			var v: Vector2 = p
			_check(v.x >= layout.arena.position.x - 1.0 and v.x <= layout.arena.end.x + 1.0,
				"%s: usek %d utíká z areny vodorovne" % [tag, lane])
			_check(v.y >= layout.arena.position.y - 1.0 and v.y <= layout.arena.end.y + 1.0,
				"%s: usek %d utíká z areny svisle" % [tag, lane])

	# --- poutnici PRICHAZEJI Z OKRAJE DISPLEJE a v cili z nej zmizi.
	# Je to videt: prvni bod vstupniho useku lezi na okraji a posledni bod
	# useku, ktery konci v cili, take.
	if g.net.entry_lane >= 0:
		var ep: PackedVector2Array = g.net.lane_path[g.net.entry_lane]
		_check(_on_border(ep[0], layout.arena),
			"%s: poutnici nevstupuji z okraje displeje (%s)" % [tag, str(ep[0])])
	var border_exits: int = 0
	for lane in range(g.net.lane_count()):
		var end_node: int = g.net.lane_end_node(lane)
		if end_node < 0 or g.net.node_kind[end_node] != Level.CIL:
			continue
		var pth: PackedVector2Array = g.net.lane_path[lane]
		_check(_on_border(pth[pth.size() - 1], layout.arena),
			"%s: usek %d do cile nekonci na okraji displeje" % [tag, lane])
		border_exits += 1
	_check(border_exits > 0, "%s: v mape neni zadny cil" % tag)

	# --- mista na bonusy se nesmi prekryvat
	var min_d: float = g.net.min_cross_lane_slot_distance()
	_check(min_d > g.net.bonus_r * 1.8,
		"%s: mista na bonusy jsou u sebe (%.1f px, treba %.1f)" % [
			tag, min_d, g.net.bonus_r * 1.8])
	# a ani dve mista NA TOM SAME useku - pocet mist je libovolny, takze
	# prave tohle je to, co drzi klepnuti od klepnuti na sousedni misto
	var same_d: float = g.net.min_same_lane_slot_distance()
	_check(same_d > g.net.bonus_r * 1.5,
		"%s: dve mista na jednom useku jsou u sebe (%.1f px, treba %.1f)" % [
			tag, same_d, g.net.bonus_r * 1.5])
	_check(g.net.max_slot_count() > 0, "%s: zadny usek nema misto na bonus" % tag)

	# --- hratelnost: klepnuti na uzel vyhybky prepne TU vyhybku
	for j in range(g.net.junction_count()):
		var node: int = int(g.net.junction_nodes[j])
		var p: Vector2 = g.net.node_world(node)
		var hit: int = g.net.junction_tap_at(p, maxf(16.0, 34.0 * layout.s))
		_check(hit == j, "%s: klepnuti na vyhybku %d vybralo vyhybku %d" % [tag, j, hit])
		if hit == j:
			# a posun na dalsi vetev opravdu zmeni, kam vyhybka posila
			var before: int = g.selected_lane(j)
			g.cycle_switch(j)
			var after: int = g.selected_lane(j)
			_check(before != after, "%s: posun vyhybkou %d nezmenil vetev" % [tag, j])

	# --- hratelnost: klepnuti na misto na bonus vybere to misto
	for lane in range(g.net.lane_count()):
		for slot in range(g.net.slot_count(lane)):
			var p: Vector2 = g.net.slot_world(lane, slot)
			var hit: Vector2i = g.net.nearest_slot(p)
			_check(hit.x == lane and hit.y == slot,
				"%s: klepnuti na misto %d/%d vybralo %d/%d" % [
					tag, lane, slot, hit.x, hit.y])

	# --- kazda volba vyhybky se musi dat vybrat i prstem: stred useku po
	#     prvnim ohybu je to, na co hrac sahá
	for j in range(g.net.junction_count()):
		for k in range(g.net.junction_lanes[j].size()):
			var lane: int = g.net.junction_lane(j, k)
			var mid: Vector2 = g.net.point_at(lane, float(g.net.lane_len[lane]) * 0.5)
			var hit2: int = g.net.lane_tap_at(mid, maxf(12.0, 20.0 * layout.s))
			_check(hit2 == lane, "%s: stred useku %d se neda trefit (trefil %d)" % [
				tag, lane, hit2])
