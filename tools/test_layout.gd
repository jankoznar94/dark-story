extends SceneTree

# Test ROZVRZENI: kruh plochy se musi vejit mezi horni pruh a paletu dole,
# tlacitka palety musi jit zmacknout prstem a hra musi zustat hratelna.
# Vystup: LAYOUT_ALL_PASS=true / false
#
# Neresi se jen "nic se neprekryva": u kazdeho rozliseni se overuje, ze se
# plocha vejde CELA, ze paleta neprekryva plochu a ze poutnik kazde barvy
# z palety stihne umrit v kruhu dostrelu (jinak je hra nehratelna, i kdyz
# vypada dobre).

const RESOLUTIONS := [
	Vector2(390, 844),   # iPhone 14 na vysku (cilova obrazovka)
	Vector2(360, 800),   # nejmensi bezny Android na vysku
	Vector2(430, 932),   # iPhone 15 Pro Max na vysku
	Vector2(800, 1280),  # tablet na vysku
	Vector2(932, 430),   # telefon na sirku (jen se nesmi rozbit)
	Vector2(1280, 720),  # desktop
]

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_run("neznama velikost okna nic nerozbije", _test_zero_size)
	for r in RESOLUTIONS:
		_run("rozliseni %dx%d" % [int(r.x), int(r.y)], _test_resolution.bind(r))
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("LAYOUT_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	quit()


func _run(name: String, fn: Callable) -> void:
	var before: int = fails.size()
	fn.call()
	if fails.size() == before:
		print("  ok   %s" % name)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)
		print("       FAIL: %s" % msg)


func _test_zero_size() -> void:
	var l := ScreenLayout.new()
	l.update(Vector2.ZERO)
	_check(l.arena.size.x >= 0.0 and l.arena.size.y >= 0.0,
		"nulova velikost okna dela zaporny obdelnik")
	_check(l.up_rect.size.x >= 0.0 and l.up_rect.size.y >= 0.0,
		"nulova velikost okna dela zaporne tlacitko")
	_check(l.field_r == 0.0, "nulova velikost okna dela plochu")
	_check(l.layout_palette(5).is_empty(), "nulova velikost okna dela tlacitka palety")


func _test_resolution(v: Vector2) -> void:
	var l := ScreenLayout.new()
	l.update(v)
	var tag: String = "%dx%d" % [int(v.x), int(v.y)]

	# 1) KRUH PLOCHY SE VEJDE CELE MEZI PRUHY
	_check(l.center.y - l.field_r >= l.arena.position.y - 0.5,
		"%s: plocha preleza do horniho pruhu" % tag)
	_check(l.center.y + l.field_r <= l.arena.position.y + l.arena.size.y + 0.5,
		"%s: plocha preleza do palety" % tag)
	_check(l.center.x - l.field_r >= -0.5 and l.center.x + l.field_r <= v.x + 0.5,
		"%s: plocha preleza do stran" % tag)

	# 2) POUTNIK JE CITELNY (runa je TVAR tela, takze 6 px je spodni mez)
	_check(l.pilgrim_r >= 6.0,
		"%s: poutnik ma polomer %.1f px, barva a tvar nejdou precist" % [tag, l.pilgrim_r])
	_check(l.tower_r >= 12.0, "%s: vez je prilis mala (%.1f px)" % [tag, l.tower_r])

	# 3) TLACITKO VYLEPSENI SE VEJDE DO PRUHU
	_check(l.up_rect.position.x >= 0.0 and l.up_rect.end.x <= v.x + 0.5,
		"%s: tlacitko vylepseni preleza displej" % tag)
	_check(l.up_rect.end.y <= l.bar_h + 0.5, "%s: tlacitko preleza pruh" % tag)
	_check(l.up_rect.size.y >= 30.0,
		"%s: tlacitko je nizke %.1f px" % [tag, l.up_rect.size.y])

	# 4) PALETA: kazdy pocet barev, ktery muze nastat (2..5), musi mit tlacitka
	# vysoka i siroka pres dotykovou mez a cela uvnitr displeje.
	for count in range(2, 6):
		var rects: Array = l.layout_palette(count)
		_check(rects.size() == count, "%s: paleta pro %d barev nema %d tlacitek" % [tag, count, count])
		for r in rects:
			var rr: Rect2 = r
			_check(rr.position.y >= v.y - l.pal_h - 0.5 and rr.end.y <= v.y + 0.5,
				"%s: tlacitko barvy (%d) preleza mimo spodni pruh" % [tag, count])
			_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5,
				"%s: tlacitko barvy (%d) preleza displej" % [tag, count])
			_check(rr.size.x >= 44.0 and rr.size.y >= 44.0,
				"%s: tlacitko barvy (%d) je male %.0fx%.0f px"
				% [tag, count, rr.size.x, rr.size.y])
		# tlacitka se nesmi prekryvat, jinak hrac zmackne jinou barvu
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				_check(not (rects[i] as Rect2).intersects(rects[j] as Rect2),
					"%s: tlacitka barvy (%d) se prekryvaji" % [tag, count])

	# 5) HRA ZUSTAVA HRATELNA: poutnik kazde barvy z palety (krome fialove
	# a stribrne, ktere maji vlastni pravidla) musi stihnout umrit v kruhu
	# dostrelu zakladni veze.
	var g := Game.new()
	g.set_field(l.field_r, l.tower_r, l.center)
	var palette: Array = Hue.palette_at(10)
	for h in [Hue.RED, Hue.YELLOW, Hue.BLUE, Hue.GREEN]:
		_check(palette.has(h), "%s: barva %s neni v palete" % [tag, Hue.name_of(h)])
		var ttk: float = g.hp_for(1, h) / g.tower.dps()
		var window: float = g.tower.range_frac() * Game.TRAVEL_S / Hue.speed_mult(h)
		_check(ttk < window,
			"%s: %s nema v dostrelu cas na zabiti (%.2f s v ohne, potreba %.2f s)"
			% [tag, Hue.name_of(h), window, ttk])
