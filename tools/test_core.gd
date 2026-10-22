extends SceneTree

# HERNI PRAVIDLA THROWERU. Vystup: CORE_ALL_PASS=true
#
# Meri se presně to, co Jan zadal: "Hráč položí prst na displej a bojovník
# střílí přesně opačným směrem." + haze se jen kdyz prst drzi + zasah ubira
# zivoty + odraz preskakuje na dalsi cil.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Profile.allow_save = false
	_run("smer strelby je presne opacny nez prst", _test_aim_opposite)
	_run("bez prstu se nehazi, s prstem ano (v odstupech)", _test_fire_only_while_aiming)
	_run("ostep leti smerem mireni a ubira zivoty", _test_spear_hits)
	_run("odraz preskoci na dalsi cil se slabsi ranou", _test_ricochet)
	_run("nepritel u bojovnika ubere zivoty a zmizi", _test_enemy_hits_warrior)
	_run("vlny: build -> wave -> body za odrazeno", _test_waves)
	_run("vic ostepu v jednom hodu", _test_multishot)
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("CORE_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
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


func _fresh() -> Game:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, Vector2(500.0, 500.0))
	g.start_level(1)
	# TEST MODE: zadna vlna se nespusti, ale strelba i pohyb bezi.
	g.phase = "test"
	return g


func _place(g: Game, frac: float, angle: float, hp: float = 100.0) -> Dictionary:
	var e := {
		"pos": g.center + Vector2(cos(angle), sin(angle)) * g.field_r * frac,
		"hp": hp, "max_hp": hp, "speed": 0.0, "dmg": 10.0, "alive": true,
	}
	g.enemies.append(e)
	return e


func _tick(g: Game, sec: float, dt: float = 1.0 / 120.0) -> void:
	var t: float = 0.0
	while t < sec:
		g.step(dt)
		t += dt


# 1) PRST = LUK. Bojovnik stoji na spodku a haze JEN DOPREDU (nahoru):
#    uhel je oriznuty na 180°, nikdy se neotoci zpet k sobe.
func _test_aim_opposite() -> void:
	var g: Game = _fresh()
	# KRAJ VLEVO/VLEVO: celych 180° je rozlozeno na cely `aim_span`.
	g.aim_at(Vector2(g.center.x + g.aim_span, g.center.y))
	_check(g.aim.x < -0.99 and absf(g.aim.y) < 0.01,
		"kraj vpravo neznamena strelbu vlevo (%.2f, %.2f)" % [g.aim.x, g.aim.y])
	g.aim_at(Vector2(g.center.x - g.aim_span, g.center.y))
	_check(g.aim.x > 0.99 and absf(g.aim.y) < 0.01,
		"kraj vlevo neznamena strelbu vpravo (%.2f, %.2f)" % [g.aim.x, g.aim.y])
	# PRST UPROSTRED = STRELBA VZHURU, i kdyz je vysoko nad bojovnikem. To je
	# cely point opravy: mirit se da z velke plochy, ne z pruhu pod barbarem.
	g.aim_at(Vector2(g.center.x, g.center.y - 400.0))
	_check(absf(g.aim.x) < 0.01 and g.aim.y < -0.99,
		"prst uprostred nahore neznamena strelbu vzhuru (%.2f, %.2f)" % [g.aim.x, g.aim.y])
	# VYSKA PRSTU NIC NEDELA - stejne X = stejny smer.
	var a1: Vector2 = g.aim
	g.aim_at(Vector2(g.center.x + 40.0, g.center.y + 60.0))
	g.aim_at(Vector2(g.center.x + 40.0, g.center.y - 400.0))
	_check(g.aim.distance_to(Vector2.from_angle(-PI * 0.5 - (40.0 / g.aim_span) * PI * 0.5)) < 0.001
		and a1.distance_to(g.aim) > 0.001, "vyska prstu meni smer strelby")
	# JEMNOST: 1 % sirky luku = necele 2° - na velke plose se miri detailne.
	g.aim_at(Vector2(g.center.x, g.center.y - 300.0))
	var up: Vector2 = g.aim
	g.aim_at(Vector2(g.center.x + g.aim_span * 0.01, g.center.y - 300.0))
	var moved: float = rad_to_deg(absf(up.angle_to(g.aim)))
	_check(moved < 1.2, "1 %% sirky pohne smerem o %.2f° - moc hrube" % moved)
	# ...a cely rozsah je opravdu 180°.
	g.aim_at(Vector2(g.center.x - g.aim_span, g.center.y))
	var left_aim: Vector2 = g.aim
	g.aim_at(Vector2(g.center.x + g.aim_span, g.center.y))
	_check(absf(rad_to_deg(left_aim.angle_to(g.aim)) - 180.0) < 1.5,
		"cely rozsah neni 180° (%.1f°)" % rad_to_deg(left_aim.angle_to(g.aim)))


# 2) BEZ PRSTU SE NEHAZI.
func _test_fire_only_while_aiming() -> void:
	var g: Game = _fresh()
	g.release()
	_tick(g, 1.0)
	_check(g.spears.is_empty(), "bez prstu se hazeji ostepy (%d)" % g.spears.size())
	g.aim_at(g.center + Vector2(0.3 * g.field_r, 0.0))
	g.step(1.0 / 120.0)
	_check(g.spears.size() >= 1, "s prstem se nehazi")
	# RYCHLOST HAZENI: za prvni interval nesmi padnout druhy hod.
	var per: float = g.fire_interval()
	var first: int = g.spears.size()
	_tick(g, per * 0.5)
	_check(g.spears.size() <= first + 1, "haze se rychleji nez dovoluje interval")


func _test_spear_hits() -> void:
	var g: Game = _fresh()
	g.aim_at(Vector2(g.center.x + g.aim_span, g.center.y))
	var e: Dictionary = _place(g, 0.30, PI, 50.0)
	g.step(1.0 / 120.0)
	_check(g.spears.size() > 0, "po mireni neleti zadny ostep")
	var dir_ok: bool = true
	for s in g.spears:
		var d: Vector2 = s["dir"]
		if d.x > -0.8:
			dir_ok = false
	_check(dir_ok, "ostep neleti opacnym smerem nez prst")
	# NEPRATELE JSOU VELCI, takze ostep do nich narazi driv, nez doleti dal -
	# protoze po zasahu zanika, kontroluje se zivot, ne pocet ostepu.
	_tick(g, 0.7)
	_check(float(e["hp"]) < 50.0, "ostep neubral nepríteli zivoty (%.1f)" % float(e["hp"]))


func _test_ricochet() -> void:
	var g: Game = _fresh()
	g.profile.perm["ric"] = 2
	g.aim_at(Vector2(g.center.x + g.aim_span, g.center.y))
	var a: Dictionary = _place(g, 0.30, PI, 30.0)
	var b: Dictionary = _place(g, 0.30, PI * 0.9, 30.0)
	_tick(g, 0.7)
	_check(float(a["hp"]) < 30.0, "prvni cil nedostal zasah")
	_check(float(b["hp"]) < 30.0, "odraz nepreskocil na druhy cil (%.1f)" % float(b["hp"]))


func _test_enemy_hits_warrior() -> void:
	var g: Game = _fresh()
	var e: Dictionary = _place(g, 0.02, 0.0, 100.0)
	e["speed"] = g.field_r / 9.0
	var hp0: float = g.hp
	var t: float = 0.0
	while t < 1.0 and g.hp >= hp0:
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
	_check(g.hp < hp0, "nepritel u bojovnika neubere zivoty")
	_check(g.hit_flash > 0.0, "zásah nerozsviti varovani bojovnika")
	_check(g.hit_amount > 0.0, "zásah nema cislo poskozeni")
	_check(g.enemies.is_empty(), "nepritel po dorazu nezmizi")


func _test_waves() -> void:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, Vector2(500.0, 500.0))
	g.start_level(1)
	_check(g.phase == "build", "level nezacina pripravou")
	g.step(Game.BUILD_S + 0.05)
	_check(g.phase == "wave", "po priprave nezacne vlna (%s)" % g.phase)
	_check(g.plan == g.wave_size(1), "plan vlny nesedi na velikost vlny")
	var body0: int = g.profile.body
	# ODRAZIT VLNU: nepratele se rovnou "zabiji" a vlna se dohraje.
	g.spawned = g.plan
	for e in g.enemies:
		e["alive"] = false
	g.step(1.0 / 60.0)
	_check(g.wave == 2, "po odrazene vlne se nezacne dalsi (%d)" % g.wave)
	_check(g.profile.body > body0, "odrazena vlna nedala body")


func _test_multishot() -> void:
	var g: Game = _fresh()
	# perm 2 = zaklad 1 + 2 = 3 ostepy v jednom hodu.
	g.profile.perm["shots"] = 2
	g.aim_at(Vector2(g.center.x + g.aim_span, g.center.y))
	g.step(1.0 / 120.0)
	_check(g.spears.size() == 3, "tri ostepy v hodu nejsou tri (%d)" % g.spears.size())
