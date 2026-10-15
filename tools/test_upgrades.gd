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
	_run("zrychleni hry: 1,0x / 1,5x / 2,0x / 2,5x za body", _test_game_speed)
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
	# Attack speed: start 1,00 s, krok -0,05 s.
	_check(absf(Upgrades.value_of("as", 0, 0) - 1.0) < 0.0001, "as bez upgradu neni 1,00 s")
	_check(absf(Upgrades.value_of("as", 0, 2) - 0.90) < 0.0001, "as po 2 krocích neni 0,90 s")
	_check(absf(Upgrades.value_of("as", 2, 0) - 0.90) < 0.0001, "as po 2 permanentních neni 0,90 s")
	# PERMANENTNI ZEBRICEK STROP MA (Jan, Oct 2026: "permanentní ať mají strop
	# dál"): 1,00 s - 8 * 0,05 s = 0,60 s, a pres to ani 99 kroku neprojde.
	_check(absf(Upgrades.value_of("as", 8, 0) - 0.60) < 0.0001, "as na 8. permanentním neni 0,60 s")
	_check(absf(Upgrades.value_of("as", 99, 0) - 0.60) < 0.0001, "permanentni kadence prelezla strop")
	# DOCASNE KROKY SHORA OMEZENE NEJSOU (Jan, Oct 2026: "já prozatím nechci
	# žádné stropy. Žádné max."). Driv docasny zebricek koncil na 0,60 s a panel
	# ukazal "MAX", i kdyz hrac mel jeste zlato i kde kupovat.
	_check(Upgrades.value_of("as", 0, 14) < 0.60,
		"docasny zebricek kadence konci na 0,60 s - hrac za tim vidi zed")
	_check(Upgrades.value_of("as", 0, 19) < Upgrades.value_of("as", 0, 18),
		"dalsi docasny krok uz kadenci nezrychli")
	# POJISTKA, NE STROP HRACE: kadence je cas a nula by delila nulou.
	_check(Upgrades.value_of("as", 8, 99) >= Upgrades.MIN_INTERVAL - 0.0001,
		"kadence spadla pod pojistku %.2f s" % Upgrades.MIN_INTERVAL)
	# POSKOZENI RANY je parametr hrace ("Ještě musíme přidat upgrade pro Attack
	# damage") a plati pro nej to same: permanentni strop, docasne bez stropu.
	_check(absf(Upgrades.value_of("ad", 0, 0) - 10.0) < 0.0001, "zakladni poskozeni neni 10")
	_check(absf(Upgrades.value_of("ad", 0, 1) - 12.0) < 0.0001, "krok poskozeni neni +2")
	_check(absf(Upgrades.value_of("ad", 7, 0) - 24.0) < 0.0001, "poskozeni na 7. permanentním neni 24")
	_check(Upgrades.value_of("ad", 7, 20) > Upgrades.value_of("ad", 7, 0),
		"docasne kroky poskozeni nic nepridaly")
	# Rostouci parametr: dostrel 34 % -> 40 % po sesti krocich.
	_check(absf(Upgrades.value_of("ar", 6, 0) - 0.40) < 0.0001, "dostrel po 6 krocích neni 40 %")
	_check(absf(Upgrades.value_of("ar", 99, 99) - 0.60) < 0.0001, "dostrel neni na stropu 60 %")
	# DOSTREL JE JEN PERMANENTNI (Jan, Oct 2026: "Rádius vyndáme z dočasných
	# upgradů a bude jen v permanentních").
	_check(Upgrades.temp_max("ar") == 0, "dostrel jde koupit i za zlato v bitve")
	# Jed/led jdou po urovnich, ne po primce.
	_check(absf(Upgrades.value_of("ps", 0, 0)) < 0.0001, "jed bez upgradu neni nula")
	_check(absf(Upgrades.value_of("ps", 1, 0) - 0.20) < 0.0001, "jed na 1. stupni neni 20 %")
	_check(absf(Upgrades.value_of("ps", 3, 0) - 0.50) < 0.0001, "jed na maximu neni 50 %")


# ZRYCHLENI HRY (Jan, Oct 2026: "Přidáme do speciálních permanentních upgradů
# novou mechaniku. Zrychlení hry. 1.5x, 2x, 2.5x."). Je to SPECIAL: v bitve se
# nekupuje, plati se body a posouva tempo CELE hry (`Game.time_scale`).
func _test_game_speed() -> void:
	_check(Upgrades.perm_max("gs") == 3, "zrychleni hry nema tri stupne")
	_check(Upgrades.temp_max("gs") == 0, "zrychleni hry jde koupit za zlato v bitve")
	_check(absf(Upgrades.value_of("gs", 0, 0) - 1.0) < 0.0001, "zakladni tempo neni 1,0x")
	_check(absf(Upgrades.value_of("gs", 1, 0) - 1.5) < 0.0001, "1. stupen tempa neni 1,5x")
	_check(absf(Upgrades.value_of("gs", 2, 0) - 2.0) < 0.0001, "2. stupen tempa neni 2,0x")
	_check(absf(Upgrades.value_of("gs", 3, 0) - 2.5) < 0.0001, "3. stupen tempa neni 2,5x")
	_check(Upgrades.value_text("gs", 2, 0) == "2,0x",
		"tempo se hracovi netiskne jako 2,0x (%s)" % Upgrades.value_text("gs", 2, 0))
	_check(Upgrades.perm_cost("gs", 0) > 0, "zrychleni hry je zadarmo")


func _test_perm_shifts_start() -> void:
	# TOHLE JE CELY SMYSL PERMANENTNICH UPGRADU (Jan: "Když bude permanentní
	# upgrade lvl 2, tak budu začínat na střela/0.9s. Cena dočasných upgradů ale
	# zůstává."). Kdyby se cena posunula s permanentem, hrac by byl potrestany
	# za to, ze si v menu neco koupil.
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		if not Upgrades.temp_buyable(id):
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
	for id in ["as", "ad", "hp", "am", "gk"]:
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
	# NAOPAK: zadna kategorie, ktera se v bitve nabizi, nesmi zustat bez
	# docasneho kroku - svitil by v ni prazdny tab.
	for cat in [Upgrades.CAT_OFF, Upgrades.CAT_DEF, Upgrades.CAT_ECO]:
		var buyable: int = 0
		for s in Upgrades.stats_in(cat):
			if Upgrades.temp_buyable(String(s["id"])):
				buyable += 1
		_check(buyable > 0, "%s: celou kategorii nelze v bitve koupit" % cat)
	# DOSTREL JE PERM-ONLY, ale NENI special: ma vlastni permanentni zebricek a
	# v bitve se vubec nenabizi (`game_view._shop_stats`, hlida `test_layout`).
	_check(Upgrades.temp_max("ar") == 0, "dostrel jde koupit za zlato v bitve")
	_check(Upgrades.temp_cost("ar", 0) == 0, "dostrel ma cenu v zlate")
	_check(Upgrades.perm_max("ar") > 0, "dostrel nema permanentni stupne")


func _test_table_sane() -> void:
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		_check(Upgrades.perm_max(id) > 0, "%s: nema permanentni stupne" % id)
		var start: float = float(s["start"])
		var step: float = float(s["step"])
		var cap: float = float(s["cap"])
		_check(absf(step) > 0.00001, "%s: krok je nula (upgrade nic nedela)" % id)
		# STROP PLATI NA PERMANENTNI ZEBRICEK (`perm_max`), ne na soucet
		# s docasnymi kroky: ty jsou od Oct 2026 neomezene.
		var n: int = Upgrades.perm_max(id)
		# U "levels" je strop POCET STUPNU (0,20/0,35/0,50 neni primka), takze
		# se porovnava pocet, ne hodnota.
		if String(s["kind"]) == "levels":
			_check(n == int(cap), "%s: stupnu je %d, ale strop tabulky je %d" % [id, n, int(cap)])
			continue
		# Strop permanentniho zebricku musi byt dosazitelny presne na hranici,
		# jinak by cast tabulky byla nedosazitelna a hrac by platil za nic.
		var v: float = Upgrades.value_of(id, Upgrades.perm_max(id), 0)
		if start < cap:
			_check(v >= cap - 0.0001, "%s: permanentni zebricek nedosahne stropu (%.3f z %.3f)" % [id, v, cap])
			_check(absf(start + step * float(n) - cap) < 0.0001,
				"%s: maximum permanentniho zebricku (perm %d) neni presne strop (%.3f vs %.3f)"
				% [id, n, start + step * float(n), cap])
		else:
			_check(v <= cap + 0.0001, "%s: permanentni zebricek preleze strop (%.3f z %.3f)" % [id, v, cap])
			_check(absf(start + step * float(n) - cap) < 0.0001,
				"%s: maximum permanentniho zebricku neni presne strop (%.3f vs %.3f)" % [id, start + step * float(n), cap])
		# NEOMEZENY DOCASNY ZEBRICEK: musi mit cenu (jinak se neda koupit)
		# a NIKDY nesmi hlasit strop - prave to dělalo "MAX" uprostred bitvy.
		if Upgrades.temp_unlimited(id):
			_check(Upgrades.temp_cost(id, 0) > 0, "%s: neomezeny docasny zebricek je zadarmo" % id)
			_check(not Upgrades.temp_is_maxed(id, 9999), "%s: neomezeny zebricek hlasi strop" % id)
			_check(Upgrades.temp_buyable(id), "%s: neomezeny zebricek se v bitve nenabizi" % id)
		else:
			_check(int(Upgrades.temp_max(id)) == 0, "%s: docasny zebricek neni ani neomezeny, ani perm-only" % id)
	_check(Upgrades.stats_in(Upgrades.CAT_OFF).size() == 5, "kategorie utok nema 5 parametru")
	_check(Upgrades.stats_in(Upgrades.CAT_DEF).size() == 3, "kategorie obrana nema 3 parametry")
	_check(Upgrades.stats_in(Upgrades.CAT_ECO).size() == 3, "kategorie ekonomika nema 3 parametry")
	_check(Upgrades.stats_in(Upgrades.CAT_SPEC).size() == 5, "kategorie special nema 5 parametru")
	_check(Upgrades.CATEGORIES.size() == 4, "kategorii neni ctvero")


func _test_texts() -> void:
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		var t: String = Upgrades.value_text(id, 0, 0)
		_check(t != "", "%s: hodnota se vytiskne prazdna" % id)
		_check(not t.contains("."), "%s: hodnota ma tecku misto ceske carky (%s)" % [id, t])
		_check(String(s["label"]) != "", "%s: popisek je prazdny" % id)
	_check(Upgrades.value_text("as", 0, 2) == "0,90 s", "text kadence neni 0,90 s")
	_check(Upgrades.value_text("ar", 6, 0) == "40 %", "text dostrelu neni 40 %")


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
