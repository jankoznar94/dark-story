extends SceneTree

# Test ROZVRZENI: plocha musi byt kruh, ktery se vejde do displeje, poutnik
# musi byt citelny a hra musi zustat hratelna na kazdem rozliseni.
# Vystup: LAYOUT_ALL_PASS=true / false
#
# Neresi se jen "nic se neprekryva": u kazdeho rozliseni se overuje, ze
# poutnik vstoupi na okraj, ze stihne umrit v kruhu dostrelu (jinak by hra
# byla nehratelna, i kdyby vypadala dobre) a ze klepnuti na venec barev
# skonci na spravnem vyseku.

const RESOLUTIONS := [
	Vector2(390, 844),   # iPhone 14 na vysku (cilova obrazovka)
	Vector2(360, 800),   # nejmensi bezny Android na vysku
	Vector2(430, 932),   # iPhone 15 Pro Max na vysku
	Vector2(800, 1280),  # tablet na vysku
	Vector2(932, 430),   # telefon na sirku (stary rezim, jen se nesmi rozbit)
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


func _test_resolution(v: Vector2) -> void:
	var l := ScreenLayout.new()
	l.update(v)
	var tag: String = "%dx%d" % [int(v.x), int(v.y)]

	# 1) KRUH PLOCHY SE VEJDE DO DISPLEJE
	_check(l.center.y - l.field_r >= l.arena.position.y - 0.5,
		"%s: plocha preleza nahoru" % tag)
	_check(l.center.y + l.field_r <= l.arena.position.y + l.arena.size.y + 0.5,
		"%s: plocha preleza dolu" % tag)
	_check(l.center.x - l.field_r >= -0.5 and l.center.x + l.field_r <= v.x + 0.5,
		"%s: plocha preleza do stran" % tag)

	# 2) POUTNIK JE CITELNY (runa je TVAR tela, takze 6 px je spodni mez)
	_check(l.pilgrim_r >= 6.0,
		"%s: poutnik ma polomer %.1f px, barva a runa nejdou precist" % [tag, l.pilgrim_r])
	_check(l.tower_r >= 12.0, "%s: vez je prilis mala (%.1f px)" % [tag, l.tower_r])

	# 3) VENEC BAREV JE VNE TELA VEZE A CELY V DISPLEJI
	_check(l.notch_in() > l.tower_r, "%s: venec barev leze do tela veze" % tag)
	_check(l.center.distance_to(l.center + Vector2(l.notch_out(), 0.0)) <= l.field_r,
		"%s: venec barev preleza okraj plochy" % tag)

	# 4) TLACITKO VYLEPSENI SE VEJDE DO PRUHU A DA SE ZMACKNOUT
	_check(l.up_rect.position.x >= 0.0 and l.up_rect.end.x <= v.x + 0.5,
		"%s: tlacitko vylepseni preleza displej" % tag)
	_check(l.up_rect.end.y <= l.bar_h + 0.5, "%s: tlacitko preleza pruh" % tag)
	_check(l.up_rect.size.y >= 30.0,
		"%s: tlacitko je nizke %.1f px" % [tag, l.up_rect.size.y])

	# 5) HRA ZUSTAVA HRATELNA: poutnik musi stihnout umrit v kruhu dostrelu.
	# Cas v ohne = dostrel jako podil cesty k vezi; cas na zabiti = zivoty / dps.
	var g := Game.new()
	g.set_field(l.field_r, l.tower_r, l.center)
	var wave1: float = g.hp_for(1) / g.tower.dps()
	var window1: float = g.tower.range_frac() * Game.TRAVEL_S
	_check(wave1 < window1,
		"%s: poutnik prvni vlny nema v dostrelu cas na zabiti (%.2f s v ohne, potreba %.2f s)"
		% [tag, window1, wave1])

	# 6) KLEPNUTI NA VYSKU VENCE SKONCI NA SPRAVNE BARVE
	var mid: float = l.notch_mid()
	for i in range(Element.COUNT):
		var a: float = -PI + TAU * (float(i) + 0.5) / float(Element.COUNT)
		var pos: Vector2 = l.center + Vector2(cos(a), sin(a)) * mid
		_check(g.notch_of(pos) == i, "%s: vysek %d se nenasel" % [tag, i])
