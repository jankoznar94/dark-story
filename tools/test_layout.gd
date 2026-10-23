extends SceneTree

# ROZVRZENI NA REALNYCH DISPLEJICH. Vystup: LAYOUT_ALL_PASS=true
#
# Herni kruh se musi vejit CELY (hrac nesmi mit nepritele za okrajem), tlacitka
# musi mit dotykovou vysku a radky upgradu se nesmi prekryvat.

const SIZES := [
	Vector2(390.0, 844.0),   # telefon na vysku
	Vector2(360.0, 640.0),   # maly telefon
	Vector2(844.0, 390.0),   # telefon na sirku
	Vector2(640.0, 360.0),   # nejmensi rozumne okno
	Vector2(1024.0, 600.0),  # tablet
	Vector2(1280.0, 800.0),
]

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Upgrades.STATS.size()
	Profile.allow_save = false
	for v in SIZES:
		_test_size(v as Vector2)
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("LAYOUT_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	quit()


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)
		print("       FAIL: %s" % msg)


func _test_size(v: Vector2) -> void:
	var tag: String = "%dx%d" % [int(v.x), int(v.y)]
	var l := ScreenLayout.new()
	l.update(v)
	# 1) BOJOVNIK NA SPODKU, hra na vysku. Plocha nad nim je cela herni prostor.
	_check(l.field_r > 40.0, "%s: plocha nema meritko" % tag)
	_check(l.center.x > v.x * 0.3 and l.center.x < v.x * 0.7,
		"%s: bojovnik neni uprostred vodorovne (%.0f)" % [tag, l.center.x])
	_check(l.center.y > v.y * 0.70, "%s: bojovnik nestoji na spodku (%.0f z %.0f)"
		% [tag, l.center.y, v.y])
	_check(l.center.y < v.y - 8.0, "%s: bojovnik je prilis u okraje" % tag)
	_check(l.arena.position.y >= l.bar_h - 0.5, "%s: plocha zacina pod pruhem" % tag)
	_check(l.arena.end.y <= l.center.y + 0.5, "%s: plocha presahuje bojovnika" % tag)
	_check(l.arena.size.y > v.y * 0.3, "%s: plocha je moc nizka" % tag)
	# 2) MENU: tlacitka HRAT / VYLEPSENI / UPDATE, v displeji, dotyková.
	_check(l.menu_rects.size() == Menu.ITEMS.size(), "%s: menu nema vsechna tlacitka (%d)"
		% [tag, l.menu_rects.size()])
	_check(Menu.ITEMS.size() == Menu.ACTIONS.size() and Menu.ITEMS.size() == Menu.SUBS.size(),
		"%s: jmena, podtitulky a akce menu nemaji stejnou delku" % tag)
	_check(Menu.ACTIONS.has("update"), "%s: v menu chybi tlacitko UPDATE" % tag)
	_check(l.menu_note_y + float(l.font_px) * 1.6 <= v.y, "%s: hlaska pod menu je mimo displej" % tag)
	for r in l.menu_rects:
		var rr: Rect2 = r
		_check(rr.size.y >= 44.0 * l.ui_scale - 0.5, "%s: tlacitko menu je nizsi nez 44 px" % tag)
		_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5
			and rr.position.y >= -0.5 and rr.end.y <= v.y + 0.5, "%s: tlacitko menu je mimo displej" % tag)
	# 3) UPGRADY: kazdy radek je dotykovy a v displeji.
	_check(l.upg_rows.size() == Upgrades.STATS.size(), "%s: chybi radky upgradu" % tag)
	for r in l.upg_rows:
		var rr: Rect2 = r
		_check(rr.size.y >= 44.0 * l.ui_scale - 0.5, "%s: radek upgradu je nizsi nez 44 px (%.0f)" % [tag, rr.size.y])
		_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5
			and rr.position.y >= -0.5 and rr.end.y <= v.y + 0.5, "%s: radek upgradu je mimo displej" % tag)
	_check(l.upg_back.size.y >= 44.0 * l.ui_scale - 0.5, "%s: ZPET je nizsi nez 44 px" % tag)
	_check(l.upg_back.end.y <= v.y + 0.5, "%s: ZPET je mimo displej" % tag)
	_check(l.upg_title_y >= 0.0, "%s: nadpis upgradu je nad displejem" % tag)
	_check(l.upg_note_y + float(l.font_px) * 1.2 <= l.upg_panel.position.y + 0.5,
		"%s: pocet bodu se prekryva s radky" % tag)
	# 4) HORNI PRUH: tlacitka se vejdou a neprekryvaji se.
	_check(l.hud_menu.size.y >= 30.0 * l.ui_scale - 0.5, "%s: tlacitko MENU je moc male" % tag)
	_check(l.hud_pause.end.x <= l.hud_menu.position.x, "%s: tlacitka v pruhu se prekryvaji" % tag)
	_check(l.hud_menu.end.x <= v.x + 0.5, "%s: MENU je mimo displej" % tag)
	# 5) HRADBA: neprítel z horniho okraje stihne dojit k hradbe za svuj
	#    cestovni cas a zastavi se o ni. Hradba stoji mezi nim a Barbarem.
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(l.field_r, l.center, l.arena)
	# TEST MODE: zadne vlny, jen ten jeden neprítel, ktery ma dojit.
	g.phase = "test"
	var tt: float = g.travel_time()
	var start := Vector2(l.center.x, l.arena.position.y + l.field_r * 0.06)
	var er: float = maxf(Game.MIN_ENEMY_R, l.field_r * 0.065)
	var line: float = g.wall_top() - er
	var e := {"pos": start, "hp": 1000.0, "max_hp": 1000.0, "r": er,
		"speed": (line - start.y) / tt, "dmg": 1.0, "alive": true}
	g.enemies.append(e)
	var t: float = 0.0
	while t < tt + 1.0 and (e["pos"] as Vector2).y < line - 0.5:
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
	var ey: float = (e["pos"] as Vector2).y
	_check(ey >= line - 0.5, "%s: neprítel nedojde k hradbe (%.1f s)" % [tag, t])
	_check(t <= tt + 0.5, "%s: cesta k hradbe je delsi nez cestovni cas (%.1f s)" % [tag, t])
	_check(g.wall_top() < l.center.y and g.wall_top() > l.arena.position.y + l.field_r * 0.10,
		"%s: hradba nestoji mezi neprateli a Barbarem (%.0f)" % [tag, g.wall_top()])
