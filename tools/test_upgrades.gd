extends SceneTree

# TABULKA UPGRADU A PROFIL (jen permanentni - Jan: "Dočasné upgrady by úplně
# zmizely."). Vystup: UPGRADES_ALL_PASS=true

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Profile.allow_save = false
	_run("hodnoty jsou start + stupne a oriznou se stropem", _test_values)
	_run("rychlost hazeni se s upgradem ZKRACUJE", _test_rate)
	_run("cena roste po trech urovnich", _test_cost)
	_run("profil: koupe za body, bez bodu ne, strop drzi", _test_profile)
	_run("texty jsou cesky a nejsou prazdne", _test_texts)
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("UPGRADES_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
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


func _test_values() -> void:
	_check(absf(Upgrades.value_of("dmg", 0) - 6.0) < 0.0001, "zakladni poskozeni neni 6")
	_check(absf(Upgrades.value_of("dmg", 7) - 27.0) < 0.0001, "poskozeni na maximu neni 27")
	_check(absf(Upgrades.value_of("dmg", 99) - 27.0) < 0.0001, "poskozeni preleze strop")
	_check(Upgrades.value_of("shots", 0) == 1.0, "zaklad neni jeden ostep")
	_check(Upgrades.value_of("shots", 3) == 4.0, "maximum neni ctyri ostepy")
	_check(absf(Upgrades.value_of("hp", 0) - 100.0) < 0.0001, "zaklad zivota neni 100")
	_check(absf(Upgrades.value_of("hp", 6) - 220.0) < 0.0001, "maximum zivota neni 220")
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		_check(Upgrades.perm_max(id) > 0, "%s: nema stupne" % id)


func _test_rate() -> void:
	var a: float = Upgrades.value_of("rate", 0)
	var b: float = Upgrades.value_of("rate", 10)
	_check(absf(a - 0.88) < 0.0001, "zakladni interval neni 0,88 s (%.2f)" % a)
	_check(absf(b - 0.28) < 0.0001, "nejkratsi interval neni 0,28 s (%.2f)" % b)
	_check(a < 1.11, "zaklad neni o 25 %% rychlejsi nez puvodnich 1,10 s (%.2f)" % a)
	_check(b < a, "upgrade hazeni nezrychlil")
	_check(absf(Upgrades.value_of("spd", 0) - 1.6) < 0.0001, "zakladni rychlost ostepu neni 1,6")


func _test_cost() -> void:
	_check(Upgrades.perm_cost("dmg", 0) == 1, "prvni stupen nestoji 1 bod")
	_check(Upgrades.perm_cost("dmg", 2) == 1, "treti stupen nestoji 1 bod")
	_check(Upgrades.perm_cost("dmg", 3) == 2, "ctvrty stupen nestoji 2 body")


func _test_profile() -> void:
	var p := Profile.new()
	p.body = 10
	_check(p.buy_perm("dmg"), "koupe za dost bodu se nepovedla")
	_check(p.perm_level("dmg") == 1 and p.body == 9, "stupen se nezapsal nebo se neodecetl")
	var q := Profile.new()
	_check(not q.buy_perm("dmg"), "koupe bez bodu prosla")
	q.body = 1000
	for i in range(Upgrades.perm_max("hp")):
		q.buy_perm("hp")
	_check(q.perm_level("hp") == Upgrades.perm_max("hp"), "profil nema plny pocet stupnu")
	_check(not q.buy_perm("hp"), "nad strop se da koupit dalsi stupen")
	q.clear_level(3)
	_check(q.best == 3 and q.level == 4, "vyhrany level neodemkl dalsi")


func _test_texts() -> void:
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		var t: String = Upgrades.value_text(id, 0)
		_check(t != "", "%s: text je prazdny" % id)
		_check(not t.contains("."), "%s: tecka misto ceske carky (%s)" % [id, t])
	_check(Upgrades.value_text("rate", 0) == "0,88 s",
		"interval se netiskne jako 0,88 s (%s)" % Upgrades.value_text("rate", 0))
	_check(Upgrades.value_text("dmg", 0) == "6", "poskozeni se netiskne jako 6")
