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
	# 1) KRUH CELY NA DISPLEJI a pod hornim pruhem.
	_check(l.field_r > 40.0, "%s: plocha nema polomer" % tag)
	_check(l.center.x - l.field_r >= -0.5, "%s: kruh preteka vlevo" % tag)
	_check(l.center.x + l.field_r <= v.x + 0.5, "%s: kruh preteka vpravo" % tag)
	_check(l.center.y - l.field_r >= l.bar_h - 0.5, "%s: kruh leze pod horni pruh" % tag)
	_check(l.center.y + l.field_r <= v.y + 0.5, "%s: kruh preteka dole" % tag)
	# 2) MENU: dve velka tlacitka, v displeji, dotyková.
	_check(l.menu_rects.size() == 2, "%s: menu nema dve tlacitka" % tag)
	for r in l.menu_rects:
		var rr: Rect2 = r
		_check(rr.size.y >= 44.0, "%s: tlacitko menu je nizsi nez 44 px" % tag)
		_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5
			and rr.position.y >= -0.5 and rr.end.y <= v.y + 0.5, "%s: tlacitko menu je mimo displej" % tag)
	# 3) UPGRADY: kazdy radek je dotykovy a v displeji.
	_check(l.upg_rows.size() == Upgrades.STATS.size(), "%s: chybi radky upgradu" % tag)
	for r in l.upg_rows:
		var rr: Rect2 = r
		_check(rr.size.y >= 44.0, "%s: radek upgradu je nizsi nez 44 px (%.0f)" % [tag, rr.size.y])
		_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5
			and rr.position.y >= -0.5 and rr.end.y <= v.y + 0.5, "%s: radek upgradu je mimo displej" % tag)
	_check(l.upg_back.size.y >= 44.0, "%s: ZPET je nizsi nez 44 px" % tag)
	_check(l.upg_back.end.y <= v.y + 0.5, "%s: ZPET je mimo displej" % tag)
	# 4) HORNI PRUH: tlacitka se vejdou a neprekryvaji se.
	_check(l.hud_menu.size.y >= 30.0, "%s: tlacitko MENU je moc male" % tag)
	_check(l.hud_pause.end.x <= l.hud_menu.position.x, "%s: tlacitka v pruhu se prekryvaji" % tag)
	_check(l.hud_menu.end.x <= v.x + 0.5, "%s: MENU je mimo displej" % tag)
	# 5) HRATELNOST: neprítel stihne dojit od okraje k bojovnikovi za TRAVEL_S.
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(l.field_r, l.center)
	# TEST MODE: zadne vlny, jen ten jeden neprítel, ktery ma dojit.
	g.phase = "test"
	var e := {"pos": l.center + Vector2(l.field_r, 0.0), "hp": 10.0, "max_hp": 10.0,
		"speed": l.field_r / Game.TRAVEL_S, "dmg": 1.0, "alive": true}
	g.enemies.append(e)
	var t: float = 0.0
	while t < Game.TRAVEL_S + 1.0 and not g.enemies.is_empty():
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
	_check(g.enemies.is_empty(), "%s: neprítel nedojde k bojovnikovi (%.1f s)" % [tag, t])
	_check(t <= Game.TRAVEL_S + 0.5, "%s: cesta k bojovnikovi je delsi nez TRAVEL_S (%.1f s)" % [tag, t])
