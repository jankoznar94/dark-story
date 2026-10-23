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
	# 5) HRATELNOST: neprítel z horniho okraje stihne dojit k bojovnikovi za
	#    svuj cestovni cas (na 1. levelu je nejpomalejsi).
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(l.field_r, l.center, l.arena)
	# 6) ZONY: dve kulaté zony vedle bojovnika, v displeji, nesmi se prekryvat
	#    s bojovnikem ani s sebou a musi mit dotykovou toleranci.
	var pr: float = l.pad_r
	_check(pr > 0.0, "%s: zony nemaji polomer" % tag)
	_check(pr * 2.0 >= v.x * 0.055 and pr * 2.0 <= v.x * 0.105,
		"%s: prumer zony neni ~30 px na telefonu (%.0f z %.0f)" % [tag, pr * 2.0, v.x])
	for p in [l.pad_l_pos, l.pad_r_pos]:
		var pp: Vector2 = p
		_check(pp.x - pr >= -0.5 and pp.x + pr <= v.x + 0.5
			and pp.y - pr >= l.bar_h - 0.5 and pp.y + pr <= v.y + 0.5,
			"%s: zona je mimo displej (%.0f, %.0f)" % [tag, pp.x, pp.y])
	_check(l.pad_l_pos.distance_to(l.pad_r_pos) > pr * 4.0, "%s: zony se prekryvaji" % tag)
	_check(l.pad_l_pos.distance_to(l.center) > g.warrior_r() + pr * 2.6,
		"%s: leva zona lezi na bojovnikovi" % tag)
	_check(l.pad_r_pos.distance_to(l.center) > g.warrior_r() + pr * 2.6,
		"%s: prava zona lezi na bojovnikovi" % tag)
	_check(l.pad_l_pos.y <= l.center.y + 0.5 and l.pad_r_pos.y <= l.center.y + 0.5,
		"%s: zony jsou niz nez bojovnik" % tag)
	# DOTYK: chytat se musi vyrazne vetsi okoli, nez je videt.
	_check(l.pad_touch_r() >= 30.0 * l.ui_scale, "%s: zona se neda chytit prstem" % tag)
	_check(l.pad_travel() > 0.0, "%s: zona nema drahu vychylky" % tag)
	# TEST MODE: zadne vlny, jen ten jeden neprítel, ktery ma dojit.
	g.phase = "test"
	var tt: float = g.travel_time()
	var start := Vector2(l.center.x, l.arena.position.y + l.field_r * 0.06)
	var e := {"pos": start, "hp": 10.0, "max_hp": 10.0,
		"speed": start.distance_to(l.center) / tt, "dmg": 1.0, "alive": true}
	g.enemies.append(e)
	var t: float = 0.0
	while t < tt + 1.0 and not g.enemies.is_empty():
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
	_check(g.enemies.is_empty(), "%s: neprítel nedojde k bojovnikovi (%.1f s)" % [tag, t])
	_check(t <= tt + 0.5, "%s: cesta k bojovnikovi je delsi nez cestovni cas (%.1f s)" % [tag, t])
