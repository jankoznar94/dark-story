extends SceneTree

# ROZVRZENI NA RŮZNÝCH DISPLEJÍCH. Tohle je jadro zadani "nativne na sirku":
# hra se musi sama slozit na kazdem telefonu, ne jen na tom vyvojovem.
# Prochazi se realna rozliseni vcetne landscape telefonu, kde je POMER
# STRAN jiny nez u 960x600 - prave tam se rozvrzeni lame nejdriv.
#
# U kazdeho rozliseni se kontroluje:
#   * vsechna tlacitka jsou CELA na obrazovce a neprekryvaji se
#   * tlacitko ma dotykovou velikost pro prst (>= 44 px)
#   * mista na veze jsou v herni plose, neprekryvaji se mezi kolejemi
#     a nelezi v ovladacim pruhu
#   * popisek svatyne zustava nad pruhem
#   * hra na tom rozliseni PORAD FUNGUJE: nepritel postaveny na
#     protikladnou kolej tam opravdu umre (geometrie nesmi prestat
#     davat smysl jen proto, ze se zmenil pomer stran)
#
# Vystup: LAYOUT_ALL_PASS=true / false

const REAL_SCREENS := [
	[2560, 1080, "21:9 velky"],
	[2160, 1080, "velky siroky telefon"],
	[1920, 1080, "FullHD"],
	[1366, 768, "notebook"],
	[1280, 720, "tablet 16:9"],
	[1024, 768, "iPad 4:3"],
	[960, 600, "zakladni navrh"],
	[932, 430, "iPhone 15 Pro Max na sirku"],
	[854, 480, "starsi telefon 16:9"],
	[844, 390, "iPhone 12/13/14 na sirku"],
	[800, 480, "maly tablet 5:3"],
	[780, 360, "maly telefon 19.5:9"],
	[740, 360, "velmi siroky telefon"],
	[640, 360, "nejmensi podporovany"],
]

const MIN_TOUCH := 44.0

var fails: Array = []
var checks: int = 0


func _init() -> void:
	print("--- rozvrzeni na %d rozlisenich ---" % REAL_SCREENS.size())
	var lines: Array = []
	for spec in REAL_SCREENS:
		var w: float = float(spec[0])
		var h: float = float(spec[1])
		var name: String = str(spec[2])
		var info: String = _check_screen(w, h, name)
		lines.append(info)
		print(info)
	for l in lines:
		pass
	print("checks=%d fails=%d" % [checks, fails.size()])
	for f in fails:
		print("FAIL: " + str(f))
	if fails.is_empty():
		print("LAYOUT_ALL_PASS=true")
	else:
		print("LAYOUT_ALL_PASS=false")
	quit()


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)


func _check_screen(w: float, h: float, name: String) -> String:
	var lay := ScreenLayout.new()
	lay.compute(Vector2(w, h))

	var min_touch: float = 9999.0
	var min_gap: float = 9999.0
	var min_cross: float = 9999.0

	# --- tlacitka ---
	var btns: Array = lay.all_buttons()
	for i in range(btns.size()):
		var r: Rect2 = btns[i]
		_ok(r.position.x >= -0.5 and r.position.y >= -0.5,
			"%s: tlacitko %d nezacina mimo obrazovku (%s)" % [name, i, r])
		_ok(r.end.x <= w + 0.5 and r.end.y <= h + 0.5,
			"%s: tlacitko %d nekonci mimo obrazovku (%s)" % [name, i, r])
		min_touch = minf(min_touch, minf(r.size.x, r.size.y))
		for j in range(i + 1, btns.size()):
			var r2: Rect2 = btns[j]
			_ok(not r.intersects(r2),
				"%s: tlacitka %d a %d se prekryvaji" % [name, i, j])
	_ok(min_touch >= MIN_TOUCH - 0.01,
		"%s: nejmensi tlacitko ma %.1f px (min %d)" % [name, min_touch, int(MIN_TOUCH)])

	# --- herni plocha a sit ---
	var g := Game.new()
	g.setup(lay.arena, lay.s, lay.bar_y)
	g.rebuild_network(lay.arena, lay.s, lay.bar_y)

	_ok(lay.arena.size.x > 200.0 and lay.arena.size.y > 80.0,
		"%s: herni plocha neni degenerovana (%s)" % [name, lay.arena])
	_ok(lay.arena.size.x > lay.arena.size.y,
		"%s: hra je na sirku, plocha je sirsi nez vyssi (%.0fx%.0f)" % [name,
			lay.arena.size.x, lay.arena.size.y])

	for lane in range(Network.LANES):
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(lay.arena.grow(g.net.tower_r).has_point(p),
				"%s: misto %d/%d lezi v plose (%s)" % [name, lane, slot, p])
			# misto na vez nesmi kolidovat s ovladacim pruhem
			var slot_rect := Rect2(p - Vector2(g.net.tower_r, g.net.tower_r),
				Vector2(g.net.tower_r * 2.0, g.net.tower_r * 2.0))
			_ok(not lay.overlaps_with(slot_rect),
				"%s: misto %d/%d se dotyka tlacitka" % [name, lane, slot])
		# popisek svatyne pod pruhem?
		var label_y: float = g.net.shrine_pos[lane].y + 54.0 * lay.s
		_ok(label_y < lay.bar_y - 2.0,
			"%s: popisek svatyne %d leze do pruhu (y=%.0f, pruh=%.0f)" % [name, lane, label_y, lay.bar_y])
		# zadny bod koleje v pruhu
		var path: PackedVector2Array = g.net.lane_path[lane]
		for k in range(path.size()):
			_ok(path[k].y < lay.bar_y,
				"%s: bod koleje %d je v ovladacim pruhu" % [name, lane])
		# kolej konci ve svatyni
		var last: Vector2 = g.net.point_at(lane, g.net.lane_len[lane])
		_ok(last.distance_to(g.net.shrine_pos[lane]) < 1.0,
			"%s: kolej %d nekonci ve svatyni" % [name, lane])

	min_cross = g.net.min_cross_lane_slot_distance()
	_ok(min_cross > g.net.tower_r * 2.0,
		"%s: veze na sousednich kolejich se prekryvaji (mezera %.1f, potreba %.1f)" % [
			name, min_cross, g.net.tower_r * 2.0])

	# --- a hra na tom rozliseni musi porad fungovat ---
	# Kazdy zivel umre na sve protikladne koleji - a vez na te koleji
	# musi byt prave ten protikladny zivel (pravidlo staveni).
	var target_el: int = Element.opposite_of(Element.FIRE)
	var kill_lane: int = -1
	for lane in range(Network.LANES):
		if Network.lane_element(lane) == target_el:
			kill_lane = lane
	_ok(kill_lane >= 0, "%s: kolej pro %s existuje" % [name, Element.name_of(target_el)])
	g.auto_wave = false
	g.gold = 5000
	for slot in range(g.net.slot_count()):
		g.try_build(kill_lane, slot, target_el)
	g.set_switch(kill_lane)
	var e: Enemy = g.debug_spawn(Element.FIRE)
	var lives0: int = g.lives
	g.run_for(60.0)
	_ok(e.hp <= 0.0, "%s: nepritel na protikladne koleji nezahynul (hp=%.1f)" % [name, e.hp])
	_ok(g.lives == lives0, "%s: zivy se dostal do svatyně (zivoty %d)" % [name, g.lives])

	return "%-30s %4.0fx%-4.0f  meritko %.2f  ovladani %.2f%s  dotyk %.0f  mezera kolej %.0f  krizeni %.0f" % [
		name, w, h, lay.s, lay.ui, " (TESNE)" if lay.narrow else "", min_touch, min_gap, min_cross]
