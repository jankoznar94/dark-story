extends SceneTree

# TEST UKLADANI ROZEHRANE PARTIE. Vystup: SAVE_ALL_PASS=true / false
#
# Dve veci, ktere musi platit, aby se hrac mohl vratit do rozjete hry:
#   1. ULOZENA PARTIE POKRACUJE PRESNE. Hra se slozi ze stavu na disku a od
#      te chvile musi bezet stejne jako ta, ze ktere se ukladalo - stejna vlna,
#      stejne zlato, stejne zivoty a HLAVNE stejna nahoda. Kdyby se neukladal
#      stav generatoru, rozjela by se jina partie (jine poradi barev) a hrac by
#      se vratil do jine hry.
#   2. PRVNI A POSLEDNI SNIMEK. Prazdny nebo cizi stav se neobnovi (nikdy
#      "napul nactena" hra) a dohrana partie se z disku maze.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Profile.allow_save = false
	# ZAPIS DO SOUBORU SE PRESMERUJE DO TESTOVACIHO SOUBORU: test nesmi prepsat
	# hracovu rozehranou partii (stejna past jako u `Profile.allow_save`).
	BattleSave.path = "user://test_zily2_battle.cfg"
	BattleSave.clear()
	_run("ulozene partie pokracuje presne (stav, hodiny i nahoda)", _test_resume_is_exact)
	_run("ulozit -> nacist -> hrat: hra se vrati do rozjete vlny", _test_file_round_trip)
	_run("prazdny a cizi stav se neobnovi", _test_bad_state)
	_run("soubor partie: has/info/clear", _test_file_api)
	BattleSave.clear()
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("SAVE_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
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


# ROZEHRANA PARTIE: treti level (tam uz chodi dve urovne barev i prvni barvy
# navic), tricet vterin hrani - dost na to, aby ve vrstve neco bylo a aby
# proslo nekolik vln.
func _busy() -> Game:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	g.start_level(3)
	# VEZ STAVI HRAC - bez nakupu by se po chvili hra zastavila na prvni vlne
	# a nebylo by co srovnavat. Bere se tolik kroku poskozeni, kolik zlato da.
	for i in range(60 * 30):
		g.buy_temp("ad")
		g.step(1.0 / 60.0)
	return g


# PRST OTISK. Srovnava se to, co hrac pozna: vlna, zlato, zivoty veze, hodiny
# a VSICHNI poutnici na plose (barva, uroven, pozice, zivoty, efekt).
func _fp(g: Game) -> String:
	var ps: Array = []
	for p in g.pilgrims:
		if not p.alive:
			continue
		ps.append([
			p.hue, p.tier, p.is_boss, p.behaviour,
			snappedf(p.pos.x, 0.001), snappedf(p.pos.y, 0.001),
			snappedf(p.hp, 0.001), snappedf(p.max_hp, 0.001),
			snappedf(p.size, 0.001), snappedf(p.ghost_left, 0.001),
			snappedf(p.ice_left, 0.001), snappedf(p.shift_left, 0.001),
			snappedf(p.poison_left, 0.001), p.burning,
		])
	return JSON.stringify({
		"level": g.level, "wave": g.wave, "phase": g.phase,
		"gold": g.gold, "hp": snappedf(g.hp, 0.001),
		"clock": snappedf(g.clock, 0.001),
		"spawned": g.spawned, "boss_at": g.boss_at,
		"wave_clock": snappedf(g.wave_clock, 0.001),
		"build_left": snappedf(g.build_left, 0.001),
		"rng": str(g.rng.state),
		"temp": g.temp, "hues": g.tower.hues, "plan": g.plan,
		"tiers": g.plan_tier,
		"p": ps,
	})


func _test_resume_is_exact() -> void:
	var a: Game = _busy()
	_check(a.pilgrims.size() > 0, "rozjeta partie nema ani jednoho poutnika")
	_check(a.spawned > 0 or a.phase == "wave", "za tricet vterin nezacala ani jedna vlna")
	var st: Dictionary = a.to_state()
	# DRUHA HRA SE SLOZI ZE STAVU (jako po navratu z pozadi).
	var b: Game = Game.new()
	b.profile = Profile.new()
	b.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	_check(b.from_state(st), "stav se nepodarilo obnovit")
	_check(_fp(a) == _fp(b), "obnovena partie NENI ve stejnem stavu jako ulozena")
	_check(absf(a.gold - b.gold) < 0.001 and absf(a.hp - b.hp) < 0.001,
		"obnovena partie nema stejne zlato a zivoty (zlato %d/%d, zivoty %.1f/%.1f)"
		% [a.gold, b.gold, a.hp, b.hp])
	# ... A POKRACUJE PRESNE: dvacet vterin hrani obou her musi dat stejny stav.
	for i in range(60 * 20):
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
	_check(_fp(a) == _fp(b),
		"po dvaceti vterinach se obnovena partie rozejla s ulozenou")
	_check(a.clock == b.clock and a.rng.state == b.rng.state,
		"obnovena partie ma jiny herni cas nebo jinou nahodu")
	# PAUZA SE NEOBNOVUJE (hrac se vraci do hry, ktera bezi).
	var c: Game = _busy()
	c.toggle_pause()
	var sc: Dictionary = c.to_state()
	var d: Game = Game.new()
	d.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	d.from_state(sc)
	_check(not d.is_paused(), "obnovena partie je pozastavena")


func _test_file_round_trip() -> void:
	BattleSave.clear()
	_check(not BattleSave.has(), "prazdny soubor se hlasi jako ulozena partie")
	var a: Game = _busy()
	_check(BattleSave.save(a), "partii se nepodarilo ulozit")
	_check(BattleSave.has(), "ulozene partie se nehlasi")
	var b: Game = Game.new()
	b.profile = Profile.new()
	b.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	_check(BattleSave.load_into(b), "ulozene partii se nepodarilo nacist")
	_check(_fp(a) == _fp(b), "nactena partie ze souboru neni ve stejnem stavu")
	# HRA ZE SOUBORU POKRACUJE STEJNE jako ta puvodni (i pres cestu souborem).
	for i in range(60 * 10):
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
	_check(_fp(a) == _fp(b), "partie ze souboru se po deseti vterinach rozejla")


func _test_bad_state() -> void:
	var g: Game = Game.new()
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	g.start_level(2)
	_check(not g.from_state({}), "prazdny stav se obnovil")
	_check(not g.from_state({"v": 99, "level": 5}), "cizi stav se obnovil")
	_check(g.level == 2, "neplatny stav zmenil hru (level %d)" % g.level)


func _test_file_api() -> void:
	BattleSave.clear()
	var g: Game = _busy()
	BattleSave.save(g)
	var i: Dictionary = BattleSave.info()
	_check(not i.is_empty(), "info o ulozene partii je prazdne")
	_check(int(i["level"]) == g.level and int(i["wave"]) == g.wave,
		"info o ulozene partii lze (level %d/%d, vlna %d/%d)"
		% [int(i["level"]), g.level, int(i["wave"]), g.wave])
	_check(int(i["pilgrims"]) == g.pilgrims.size(),
		"info o ulozene partii nema pocet poutniku")
	BattleSave.clear()
	_check(not BattleSave.has(), "smazana partie se porad hlasi")
	_check(BattleSave.info().is_empty(), "smazana partie ma porad info")
