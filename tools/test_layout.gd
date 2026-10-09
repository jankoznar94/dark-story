extends SceneTree

# ROZVRZENI NA RŮZNÝCH DISPLEJÍCH. Tohle je jadro zadani "nativne na sirku":
# hra se musi sama slozit na kazdem telefonu, ne jen na tom vyvojovem.
# Prochazi se realna rozliseni vcetne landscape telefonu, kde je POMER
# STRAN jiny nez u 960x600 - prave tam se rozvrzeni lame nejdriv.
#
# U kazdeho rozliseni se kontroluje:
#   * vsechny dotykove cile jsou CELE na obrazovce a neprekryvaji se
#   * tlacitko ma dotykovou velikost pro prst (>= 44 px)
#   * mista na bonusy jsou v herni plose, neprekryvaji se mezi pruhy
#     a nelezi v ovladacim pruhu
#   * popisek vystupu zustava nad pruhem
#   * NAVOD SE VEJDE DO PRUHU - meri se skutecna sirka textu, ne odhad
#   * hra na tom rozliseni PORAD FUNGUJE: klepnuti na usek vybere prave
#     ten usek a nepritel na protikladnem useku tam opravdu umre
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
# Texty navodu a cislo u dmg zony - test meri, ze se opravdu vejdou.
const LEGEND_ROW1 := "Oheň → Voda"
const LEGEND_ROW2 := "neutrální úsek: všichni 100 %  ·  vlastní 0 %  ·  jiný 50 %  ·  protiklad 200 %"
const ZONE_LABEL := "dmg × 2.0"

var fails: Array = []
var checks: int = 0


func _init() -> void:
	print("--- rozvrzeni na %d rozlisenich ---" % REAL_SCREENS.size())
	var font: Font = ThemeDB.fallback_font
	for spec in REAL_SCREENS:
		var w: float = float(spec[0])
		var h: float = float(spec[1])
		var name: String = str(spec[2])
		var info: String = _check_screen(w, h, name, font)
		print(info)
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


func _check_screen(w: float, h: float, name: String, font: Font) -> String:
	var lay := ScreenLayout.new()
	lay.compute(Vector2(w, h))

	var min_touch: float = 9999.0
	var min_cross: float = 9999.0

	# --- dotykove cile ---
	var btns: Array = lay.all_buttons()
	for i in range(btns.size()):
		var r: Rect2 = btns[i]
		_ok(r.position.x >= -0.5 and r.position.y >= -0.5,
			"%s: prvek %d nezacina mimo obrazovku (%s)" % [name, i, r])
		_ok(r.end.x <= w + 0.5 and r.end.y <= h + 0.5,
			"%s: prvek %d nekonci mimo obrazovku (%s)" % [name, i, r])
		min_touch = minf(min_touch, minf(r.size.x, r.size.y))
		for j in range(i + 1, btns.size()):
			var r2: Rect2 = btns[j]
			_ok(not r.intersects(r2), "%s: prvky %d a %d se prekryvaji" % [name, i, j])
	_ok(min_touch >= MIN_TOUCH - 0.01,
		"%s: nejmensi dotykovy cil ma %.1f px (min %d)" % [name, min_touch, int(MIN_TOUCH)])
	# a SKIP musi byt nad pruhem, ne v nem utopeny
	_ok(lay.skip_rect.position.y >= lay.bar_y,
		"%s: SKIP zacina v pruhu (%.0f vs %.0f)" % [name, lay.skip_rect.position.y, lay.bar_y])

	# --- NAVOD SE MUSI VEJIT ---
	# Pruh je jedina informace o pravidlech hry, takze nesmi pretect
	# ani na nejmensim displeji. Meri se skutecna sirka textu.
	var col_w: float = lay.legend.size.x / float(Element.COUNT)
	var row1_w: float = font.get_string_size(LEGEND_ROW1, HORIZONTAL_ALIGNMENT_LEFT, -1,
		lay.font(12.0)).x
	_ok(row1_w <= col_w + 0.5,
		"%s: popisek dvojice se vejde do sloupce (%.0f > %.0f)" % [name, row1_w, col_w])
	var row2_w: float = font.get_string_size(LEGEND_ROW2, HORIZONTAL_ALIGNMENT_LEFT, -1,
		lay.font(13.0)).x
	_ok(row2_w <= lay.legend.size.x + 0.5,
		"%s: radek s cisly se vejde do pruhu (%.0f > %.0f)" % [name, row2_w, lay.legend.size.x])
	_ok(lay.legend.end.y <= lay.bar_y + lay.bar_h + 0.5,
		"%s: navod nepreteka pod pruh" % name)

	# --- MENU A NASTAVENI ---
	# Menu je prvni obrazovka, takze jeho tlacitka musi byt stisknutelna
	# prstem na kazdem displeji - jinak se hrac ke hre vubec nedostane.
	# Menu a nastaveni se nikdy nezobrazuji soucasne, proto se testuji
	# kazde zvlast.
	for k in range(2):
		var mb: Array = lay.all_menu_buttons() if k == 0 else lay.all_settings_buttons()
		var tag: String = "menu" if k == 0 else "nastaveni"
		for i in range(mb.size()):
			var r: Rect2 = mb[i]
			_ok(r.position.x >= -0.5 and r.position.y >= -0.5,
				"%s: %s prvek %d nezacina mimo obrazovku (%s)" % [name, tag, i, r])
			_ok(r.end.x <= w + 0.5 and r.end.y <= h + 0.5,
				"%s: %s prvek %d nekonci mimo obrazovku (%s)" % [name, tag, i, r])
			_ok(minf(r.size.x, r.size.y) >= MIN_TOUCH - 0.01,
				"%s: %s prvek %d je moc maly (%.1f)" % [name, tag, i, minf(r.size.x, r.size.y)])
			for j in range(i + 1, mb.size()):
				var r2: Rect2 = mb[j]
				_ok(not r.intersects(r2),
					"%s: %s prvky %d a %d se prekryvaji" % [name, tag, i, j])

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
			_ok(lay.arena.grow(g.net.bonus_r).has_point(p),
				"%s: misto %d/%d lezi v plose (%s)" % [name, lane, slot, p])
			var slot_rect := Rect2(p - Vector2(g.net.bonus_r, g.net.bonus_r),
				Vector2(g.net.bonus_r * 2.0, g.net.bonus_r * 2.0))
			_ok(not lay.overlaps_with(slot_rect),
				"%s: misto %d/%d se dotyka tlacitka" % [name, lane, slot])
		var label_y: float = g.net.exit_pos[g.net.lane_exit[lane]].y + 54.0 * lay.s
		_ok(label_y < lay.bar_y - 2.0,
			"%s: popisek vystupu %d leze do pruhu (y=%.0f, pruh=%.0f)" % [name, lane, label_y, lay.bar_y])
		var path: PackedVector2Array = g.net.lane_path[lane]
		for k in range(path.size()):
			_ok(path[k].y < lay.bar_y, "%s: bod useku %d je v ovladacim pruhu" % [name, lane])
		var last: Vector2 = g.net.point_at(lane, g.net.lane_len[lane])
		_ok(last.distance_to(g.net.exit_pos[g.net.lane_exit[lane]]) < 1.0,
			"%s: usek %d nekonci ve svem vystupu" % [name, lane])
		# DMG ZONA musi zustat nad pruhem - jinak by kreslila do ovladani
		_ok(g.net.rows[lane] < lay.bar_y - 20.0 * lay.s,
			"%s: dmg zona %d leze k pruhu (y=%.0f)" % [name, lane, g.net.rows[lane]])

	min_cross = g.net.min_cross_lane_slot_distance()
	_ok(min_cross > g.net.bonus_r * 2.0,
		"%s: bonusy na sousednich pruzich se prekryvaji (mezera %.1f, potreba %.1f)" % [
			name, min_cross, g.net.bonus_r * 2.0])

	# --- a hra na tom rozliseni musi porad fungovat ---
	# Klepnuti na usek je jedina interakce, kterou hrac prepina vyhybku.
	for lane in range(Network.LANES):
		var tap: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.7)
		var hit: int = g.net.lane_tap_at(tap, maxf(10.0, 16.0 * lay.s))
		_ok(hit == lane, "%s: klepnuti na usek %d ho vybere (hit=%d)" % [name, lane, hit])
	# Kazdy zivel umre na sve protikladne useku, kdyz je usek vystrojen -
	# a to i na tomhle rozliseni. Geometrie nesmi prestat davat smysl jen
	# proto, ze se zmenil pomer stran. (Samotna cesta poutnika jen ZRANI;
	# zabiti je odmena za investici, proto se jeden bonus staví.)
	var target_el: int = Element.opposite_of(Element.FIRE)
	var kill_lane: int = -1
	for lane in range(Network.LANES):
		if Network.lane_element(lane) == target_el:
			kill_lane = lane
	_ok(kill_lane >= 0, "%s: usek pro %s existuje" % [name, Element.name_of(target_el)])
	g.auto_wave = false
	g.gold = 999
	g.try_build(kill_lane, 0, Network.lane_element(kill_lane))
	g.set_switch(kill_lane)
	var e: Enemy = g.debug_spawn(Element.FIRE)
	var lives0: int = g.lives
	g.run_for(60.0)
	_ok(e.hp <= 0.0, "%s: nepritel na protikladnem useku nezahynul (hp=%.1f)" % [name, e.hp])
	_ok(g.lives == lives0, "%s: zivy se dostal na vystup (zivoty %d)" % [name, g.lives])

	return "%-30s %4.0fx%-4.0f  meritko %.2f  ovladani %.2f%s  dotyk %.0f  navod %.0f/%.0f  krizeni %.0f" % [
		name, w, h, lay.s, lay.ui, " (TESNE)" if lay.narrow else "", min_touch,
		row2_w, lay.legend.size.x, min_cross]
