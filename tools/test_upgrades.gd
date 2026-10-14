extends SceneTree

# TEST TABULKY UPGRADU A PROFILU. Vystup: UPGRADES_ALL_PASS=true / false
#
# Tohle je jedina ochrana toho, ze "co hrac vidi" a "co hra opravdu pouziva"
# je jedno cislo. Kdyby si obrazovka pocitala hodnotu sama, hrac by videl
# neco jineho, nez s cim hra pocita - a nikdo by si toho nevsiml.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Upgrades.STATS.size()  # nacti tridu
	Profile.allow_save = false   # testy NESMI prepsat hracuv postup
	_run("hodnota je start + (permanentni + docasne) kroky, orezana stropem", _test_value)
	_run("permanentni stupen posouva start, cena docasneho kroku se NEMENI", _test_perm_shifts_start)
	_run("docasna cena je 5x N a je stejna pro kazdou kategorii", _test_temp_cost)
	_run("permanentni cena roste a specialy jsou drazsi", _test_perm_cost)
	_run("kategorie: special nema docasne kroky", _test_special_is_perm_only)
	_run("soucty: kazdy stat ma start, krok, strop a stropy dava smysl", _test_table_sane)
	_run("texty hodnot jsou cesky a nejsou prazdne", _test_texts)
	_run("profil: koupe permanentu za body, strop, nedostatek bodu", _test_profile_buy)
	_run("profil: vyhrany level odemkne dalsi", _test_profile_clear)
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


func _test_value() -> void:
	# Attack speed: start 1,00 s, krok -0,05 s, strop 0,30 s.
	_check(absf(Upgrades.value_of("as", 0, 0) - 1.0) < 0.0001, "as bez upgradu neni 1,00 s")
	_check(absf(Upgrades.value_of("as", 0, 2) - 0.90) < 0.0001, "as po 2 krocích neni 0,90 s")
	_check(absf(Upgrades.value_of("as", 2, 0) - 0.90) < 0.0001, "as po 2 permanentních neni 0,90 s")
	_check(absf(Upgrades.value_of("as", 6, 8) - 0.30) < 0.0001, "as na maximu neni 0,30 s")
	# Strop se NESMI prelezt, ani kdyz si obrazovka rekne o vic kroku.
	_check(absf(Upgrades.value_of("as", 99, 99) - 0.30) < 0.0001, "as prelezl strop")
	# Rostouci parametr: dostrel 34 % -> 40 % po sesti krocich.
	_check(absf(Upgrades.value_of("ar", 0, 6) - 0.40) < 0.0001, "dostrel po 6 krocích neni 40 %")
	_check(absf(Upgrades.value_of("ar", 99, 99) - 0.60) < 0.0001, "dostrel neni na stropu 60 %")
	# Jed/led jdou po urovnich, ne po primce.
	_check(absf(Upgrades.value_of("ps", 0, 0)) < 0.0001, "jed bez upgradu neni nula")
	_check(absf(Upgrades.value_of("ps", 1, 0) - 0.20) < 0.0001, "jed na 1. stupni neni 20 %")
	_check(absf(Upgrades.value_of("ps", 3, 0) - 0.50) < 0.0001, "jed na maximu neni 50 %")


func _test_perm_shifts_start() -> void:
	# TOHLE JE CELY SMYSL PERMANENTNICH UPGRADU (Jan: "Když bude permanentní
	# upgrade lvl 2, tak budu začínat na střela/0.9s. Cena dočasných upgradů ale
	# zůstává."). Kdyby se cena posunula s permanentem, hrac by byl potrestany
	# za to, ze si v menu neco koupil.
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		if Upgrades.temp_max(id) <= 0:
			continue
		var c0: int = Upgrades.temp_cost(id, 0)
		var c1: int = Upgrades.temp_cost(id, 0)
		_check(c0 == c1 and c0 > 0, "%s: cena prvniho kroku neni konstantni" % id)
		# Hodnota po N krocich je stejna, at je permanent 0 nebo 3 (posun je
		# jen jiny start).
		var a: float = Upgrades.value_of(id, 0, 3) - Upgrades.value_of(id, 0, 0)
		var b: float = Upgrades.value_of(id, 3, 3) - Upgrades.value_of(id, 3, 0)
		_check(absf(a - b) < 0.0001, "%s: krok se posunul s permanentnim stupnem" % id)
	var d: float = Upgrades.value_of("as", 0, 0) - Upgrades.value_of("as", 2, 0)
	_check(absf(d - 0.10) < 0.0001, "dva permanentni stupne neposunuly start o 0,10 s (%.3f)" % d)


func _test_temp_cost() -> void:
	_check(Upgrades.temp_cost("as", 0) == 5, "prvni docasny krok nestoji 5 zlata")
	_check(Upgrades.temp_cost("as", 1) == 10, "druhy docasny krok nestoji 10 zlata")
	_check(Upgrades.temp_cost("as", 7) == 40, "osmy docasny krok nestoji 40 zlata")
	# Cena musi byt stejna napric kategoriemi - hrac jinak nepochopi, podle
	# ceho se cena pocita.
	for id in ["as", "ar", "hp", "am", "gk"]:
		_check(Upgrades.temp_cost(id, 2) == 15, "%s: treti krok nestoji 15 zlata" % id)


func _test_perm_cost() -> void:
	_check(Upgrades.perm_cost("as", 0) == 1, "prvni permanentni stupen nestoji 1 bod")
	_check(Upgrades.perm_cost("as", 2) == 1, "treti permanentni stupen nestoji 1 bod")
	_check(Upgrades.perm_cost("as", 3) == 2, "ctvrty permanentni stupen nestoji 2 body")
	# Specialy jsou nove mechaniky, ne cisla - musi byt drazsi.
	_check(Upgrades.perm_cost("ms", 0) == 3, "multishot nestoji 3 body")
	_check(Upgrades.perm_cost("rc", 0) == 4, "ricochet nestoji 4 body")
	_check(Upgrades.perm_cost("ps", 1) == 8, "druhy stupen jedu nestoji 8 bodu")
	_check(Upgrades.perm_cost("ms", 3) == 12, "ctvrty stupen multishotu nestoji 12 bodu")


func _test_special_is_perm_only() -> void:
	for s in Upgrades.stats_in(Upgrades.CAT_SPEC):
		var id: String = String(s["id"])
		_check(Upgrades.temp_max(id) == 0, "%s (special) jde koupit za zlato v bitve" % id)
		_check(Upgrades.temp_cost(id, 0) == 0, "%s: special ma cenu v zlate" % id)
		_check(Upgrades.perm_max(id) > 0, "%s: special nema permanentni stupne" % id)
	# Naopak: vsechno ostatni MUSI jit koupit i v bitve.
	for cat in [Upgrades.CAT_OFF, Upgrades.CAT_DEF, Upgrades.CAT_ECO]:
		for s in Upgrades.stats_in(cat):
			var id: String = String(s["id"])
			_check(Upgrades.temp_max(id) > 0, "%s: nema docasne kroky (v bitve se neda koupit)" % id)


func _test_table_sane() -> void:
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		_check(Upgrades.perm_max(id) > 0, "%s: nema permanentni stupne" % id)
		var start: float = float(s["start"])
		var step: float = float(s["step"])
		var cap: float = float(s["cap"])
		_check(absf(step) > 0.00001, "%s: krok je nula (upgrade nic nedela)" % id)
		var n: int = Upgrades.perm_max(id) + Upgrades.temp_max(id)
		# U "levels" je strop POCET STUPNU (0,20/0,35/0,50 neni primka), takze
		# se porovnava pocet, ne hodnota.
		if String(s["kind"]) == "levels":
			_check(n == int(cap), "%s: stupnu je %d, ale strop tabulky je %d" % [id, n, int(cap)])
			continue
		# Strop musi byt dosazitelny presne na hranici (permanent + docasne),
		# jinak by cast tabulky byla nedosazitelna a hrac by platil za nic.
		var v: float = Upgrades.value_of(id, Upgrades.perm_max(id), Upgrades.temp_max(id))
		if start < cap:
			_check(v >= cap - 0.0001, "%s: na maximu nedosahne stropu (%.3f z %.3f)" % [id, v, cap])
			_check(absf(start + step * float(n) - cap) < 0.0001,
				"%s: maximum (perm %d + temp %d) neni presne strop (%.3f vs %.3f)"
				% [id, Upgrades.perm_max(id), Upgrades.temp_max(id), start + step * float(n), cap])
		else:
			_check(v <= cap + 0.0001, "%s: na maximu preleze strop (%.3f z %.3f)" % [id, v, cap])
			_check(absf(start + step * float(n) - cap) < 0.0001,
				"%s: maximum neni presne strop (%.3f vs %.3f)" % [id, start + step * float(n), cap])
	_check(Upgrades.stats_in(Upgrades.CAT_OFF).size() == 4, "kategorie utok nema 4 parametry")
	_check(Upgrades.stats_in(Upgrades.CAT_DEF).size() == 3, "kategorie obrana nema 3 parametry")
	_check(Upgrades.stats_in(Upgrades.CAT_ECO).size() == 3, "kategorie ekonomika nema 3 parametry")
	_check(Upgrades.stats_in(Upgrades.CAT_SPEC).size() == 4, "kategorie special nema 4 parametry")
	_check(Upgrades.CATEGORIES.size() == 4, "kategorii neni ctvero")


func _test_texts() -> void:
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		var t: String = Upgrades.value_text(id, 0, 0)
		_check(t != "", "%s: hodnota se vytiskne prazdna" % id)
		_check(not t.contains("."), "%s: hodnota ma tecku misto ceske carky (%s)" % [id, t])
		_check(String(s["label"]) != "", "%s: popisek je prazdny" % id)
	_check(Upgrades.value_text("as", 0, 2) == "0,90 s", "text kadence neni 0,90 s")
	_check(Upgrades.value_text("ar", 0, 6) == "40 %", "text dostrelu neni 40 %")


func _test_profile_buy() -> void:
	var p := Profile.new()
	p.body = 10
	_check(p.perm_level("as") == 0, "novy profil uz ma upgrade")
	_check(p.buy_perm("as"), "koupe za dost bodu se nepovedla")
	_check(p.perm_level("as") == 1, "stupen se nezapisal")
	_check(p.body == 9, "body se neodecetly (zbyva %d)" % p.body)
	# PRVNI TRI STUPNE STOJI PO JEDNOM BODU (1 + (n-1)/3).
	_check(p.buy_perm("as") and p.buy_perm("as"), "druhy nebo treti stupen nejde")
	_check(p.body == 7, "tri stupne nestaly 3 body (zbyva %d)" % p.body)
	_check(Upgrades.perm_cost("as", 3) == 2, "ctvrty stupen nestoji 2 body")
	_check(p.buy_perm("as"), "ctvrty stupen za 2 body nejde")
	_check(p.body == 5, "ctvrty stupen nestal 2 body (zbyva %d)" % p.body)
	# BEZ BODU SE NEKUPUJE. Cerstvy profil, aby do toho nekecal stav vyse.
	var q := Profile.new()
	_check(not q.buy_perm("ar"), "koupe bez bodu prosla")
	# STROP: na maximu se dalsi stupen koupit neda, i kdyz ma hrac body.
	q.body = 1000
	for i in range(Upgrades.perm_max("ar")):
		q.buy_perm("ar")
	_check(q.perm_level("ar") == Upgrades.perm_max("ar"), "profil nema plny pocet stupnu")
	_check(not q.buy_perm("ar"), "nad strop se da koupit dalsi stupen")


func _test_profile_clear() -> void:
	var p := Profile.new()
	p.clear_level(3)
	_check(p.best == 3, "vyhrany level se nezapsal do nejlepsich")
	_check(p.level == 4, "vyhrany level neodemkl dalsi")
	# Nizsi level se neuklada zpet.
	p.clear_level(2)
	_check(p.best == 3 and p.level == 4, "opakovana vyhra nizsiho levelu poskodila postup")
