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
	_run("docasna cena je N^2 a uroven ceny je vlastnost statu", _test_temp_cost)
	_run("zlaty obeh je petkrat mensi a pomer zustal", _test_economy_scale)
	_run("sila paprsku je nasobici osa (1,0x - 1,5x a v bitve dal)", _test_beam_power)
	_run("permanentni cena roste a specialy jsou drazsi", _test_perm_cost)
	_run("kategorie: special nema docasne kroky", _test_special_is_perm_only)
	_run("soucty: kazdy stat ma start, krok, strop a stropy dava smysl", _test_table_sane)
	_run("zrychleni hry: 1,0x / 1,5x / 2,0x / 2,5x za body", _test_game_speed)
	_run("strazce: special, ktery strili na vsechno (30/45/60 % poskozeni veze)",
		_test_turret)
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
	# KADENCE ("as") UZ NEEXISTUJE (Jan, Oct 2026: "Vrátíme se k laseru místo
	# projektilů. Tím pádem zrušíme úplně Attack speed upgrady."). Kdyby radek
	# v tabulce zustal, hrac by v panelu videl upgrade, ktery nic nedela.
	_check(Upgrades.stat("as")["label"] == "as",
		"tabulka porad zna zruseny upgrade Attack speed")
	# POSKOZENI RANY je parametr hrace ("Ještě musíme přidat upgrade pro Attack
	# damage") a plati pro nej to same: permanentni strop, docasne bez stropu.
	# Od Oct 2026 je to poskozeni ZA SEKUNDU (vez sviti laserem).
	_check(absf(Upgrades.value_of("ad", 0, 0) - 14.0) < 0.0001, "zakladni poskozeni neni 14")
	_check(absf(Upgrades.value_of("ad", 0, 1) - 16.0) < 0.0001, "krok poskozeni neni +2")
	_check(absf(Upgrades.value_of("ad", 7, 0) - 28.0) < 0.0001, "poskozeni na 7. permanentním neni 28")
	_check(Upgrades.value_of("ad", 7, 20) > Upgrades.value_of("ad", 7, 0),
		"docasne kroky poskozeni nic nepridaly")
	# ODRAZ: jedna polozka, dve cisla - pocet odrazu a jejich sila. S kazdym
	# stupnem musi rict vic odrazu a vetsi silu, jinak by hrac platil za nic.
	var c0: Vector2 = Upgrades.chain_of("rc", 0, 0)
	_check(c0.x == 0.0, "zakladni vez uz ma odraz (%d)" % int(c0.x))
	var prev_n: int = 0
	var prev_s: float = -1.0
	for i in range(1, Upgrades.perm_max("rc") + 1):
		var c: Vector2 = Upgrades.chain_of("rc", i, 0)
		_check(c.x > prev_n, "stupen %d nepridal odraz (%d)" % [i, int(c.x)])
		_check(c.y > prev_s, "stupen %d neprisel s lepsi silou odrazu (%.2f)" % [i, c.y])
		_check(c.y > 0.0 and c.y <= 1.0, "sila odrazu na stupni %d neni podil (%.2f)" % [i, c.y])
		prev_n = int(c.x)
		prev_s = c.y
	_check(absf(Upgrades.value_of("rc", 2, 0) - 2.0) < 0.0001,
		"value_of u odrazu nevraci pocet odrazu (%.1f)" % Upgrades.value_of("rc", 2, 0))
	_check(Upgrades.value_text("rc", 0, 0) == "—",
		"odraz bez upgradu se netiskne jako prazdny (%s)" % Upgrades.value_text("rc", 0, 0))
	_check(Upgrades.value_text("rc", 2, 0) == "2 odrazy · 60 % zásahu",
		"text odrazu neni cesky (%s)" % Upgrades.value_text("rc", 2, 0))
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


# STRAZCE (turret). Jan (Oct 2026): "malý turret, který by způsoboval třeba jen
# 30% poškození, ale útočil by automaticky vždy na nejbližšího nepřítele,
# nehledě na barvu ... pojistka když hráč nestíhá." a později "místo navyšování
# poškození ... další dva strážci ... rozmístěný do trojúhelníku".
#
# V TABULCE se hlida jen to, co hrac vidi v menu: je to SPECIAL (v bitve se
# nekupuje) a hodnota je POCET STRAZCU 0-3. Ze opravdu strili na jinou barvu,
# maji kazdy svuj cil a stoji v trojuhelniku, hlida
# `test_core._test_turret_ignores_hue` (tabulka o tom nic nevi - je to pravidlo
# hry, ne cislo).
func _test_turret() -> void:
	_check(Upgrades.perm_max("tw") == 3, "strazce nema tri stupne")
	_check(Upgrades.temp_max("tw") == 0, "strazce jde koupit za zlato v bitve")
	_check(Upgrades.temp_buyable("tw") == false, "strazce se nabizi v bitve")
	_check(String(Upgrades.stat("tw")["cat"]) == Upgrades.CAT_SPEC,
		"strazce neni special")
	_check(Upgrades.label_of("tw") == "Strážce",
		"popisek neni \"Strážce\" (%s)" % Upgrades.label_of("tw"))
	_check(absf(Upgrades.value_of("tw", 0, 0)) < 0.0001, "strazce bez upgradu uz stoji")
	_check(absf(Upgrades.value_of("tw", 1, 0) - 1.0) < 0.0001,
		"1. stupen neni jeden strazce (%.2f)" % Upgrades.value_of("tw", 1, 0))
	_check(absf(Upgrades.value_of("tw", 3, 0) - 3.0) < 0.0001,
		"3. stupen nejsou tri strazci (%.2f)" % Upgrades.value_of("tw", 3, 0))
	_check(Upgrades.value_text("tw", 1, 0) == "1",
		"text strazce neni 1 (%s)" % Upgrades.value_text("tw", 1, 0))
	_check(Upgrades.value_text("tw", 3, 0) == "3",
		"text strazce neni 3 (%s)" % Upgrades.value_text("tw", 3, 0))
	_check(Upgrades.value_text("tw", 0, 0) == "0",
		"strazce bez upgradu se netiskne jako nula (%s)" % Upgrades.value_text("tw", 0, 0))
	_check(Upgrades.perm_cost("tw", 0) > 0, "strazce je zadarmo")
	_check(Upgrades.perm_cost("tw", 1) > Upgrades.perm_cost("tw", 0),
		"druhy strazce nestoji vic nez prvni")


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
	var d: float = Upgrades.value_of("ad", 2, 0) - Upgrades.value_of("ad", 0, 0)
	_check(absf(d - 4.0) < 0.0001, "dva permanentni stupne neposunuly start o 4/s (%.3f)" % d)


# SILA PAPRSKU ("ap") JE NASOBICI OSA - jediny parametr, ktery nasobi paprsek
# jako celek. Vznikl proto, ze s projektily skoncila i kadence a hrac nemel
# cim drzet krok s rustem zivotu (Jan, Oct 2026: "...vlastně chybí jeden
# modifikátor a hráč nestíhá věž vylepšovat...").
func _test_beam_power() -> void:
	# V MENU JE MALY ZEBRICEK: 1,0x az 1,5x za body.
	_check(absf(Upgrades.value_of("ap", 0, 0) - 1.0) < 0.0001, "zakladni sila paprsku neni 1,0x")
	_check(absf(Upgrades.value_of("ap", 5, 0) - 1.5) < 0.0001,
		"sila paprsku na poslednim permanentním neni 1,5x (%.2f)" % Upgrades.value_of("ap", 5, 0))
	_check(Upgrades.perm_max("ap") == 5, "sila paprsku nema pet permanentnich stupnu")
	# A V BITVE POKRACUJE DAL: kazdy dalsi krok za zlato prida 0,10 na nasobek.
	_check(absf(Upgrades.value_of("ap", 5, 4) - 1.9) < 0.0001,
		"docasne kroky nepokracuji v nasobeni (%.2f)" % Upgrades.value_of("ap", 5, 4))
	_check(Upgrades.temp_buyable("ap"), "sila paprsku se v bitve neda koupit")
	_check(Upgrades.temp_cost("ap", 0) == 1, "prvni krok sily paprsku nestoji 1 zlato")
	_check(Upgrades.value_text("ap", 5, 0) == "1,5x",
		"text sily paprsku neni 1,5x (%s)" % Upgrades.value_text("ap", 5, 0))


func _test_temp_cost() -> void:
	# CENA ROSTE KVADRATICKY (Oct 2026, viz `Upgrades.temp_cost`): kazdy krok je
	# n^2, takze druhy stoji 4 a osmy 64. Linearni cena driv nechala hrace
	# koupit pres 80 kroku poskozeni za level (Jan: "kazdy je mrtvy behem
	# chvilky"). Cisla jsou PETKRAT mensi nez driv (5 * n^2) - Oct 2026 (Jan:
	# "cena tak rychle neroste do stovek a tisíců. Jde spíš o optický rozdíl.")
	_check(Upgrades.temp_cost("ad", 0) == 1, "prvni docasny krok nestoji 1 zlato")
	_check(Upgrades.temp_cost("ad", 1) == 4, "druhy docasny krok nestoji 4 zlata")
	_check(Upgrades.temp_cost("ad", 7) == 64, "osmy docasny krok nestoji 64 zlata")
	# Cena musi byt stejna napric kategoriemi - hrac jinak nepochopi, podle
	# ceho se cena pocita. ("gk" tu ZAMERNE neni, viz nize.)
	for id in ["ad", "hp", "am", "cc", "gw", "gl"]:
		_check(Upgrades.temp_cost(id, 2) == 9, "%s: treti krok nestoji 9 zlata" % id)
	# ZLATO ZA ZABITI MA PETKRAT DRAZSI KROK. Neni to nekonzistence: jeho krok
	# je cele +1 zlato za zabiti a cely zlaty obeh je petkrat mensi, takze by
	# z neho byl jednoznacne nejlepsi nakup ve hre. Pomer "kolik zabiti na
	# krok" tim zustava PRESNE jako pred zmensenim obehu - proto se hlida on,
	# ne cena sama.
	_check(Upgrades.temp_cost("gk", 0) == 5, "krok zlata za zabiti nestoji 5 zlata")
	_check(Upgrades.temp_cost("gk", 2) == 45, "treti krok zlata za zabiti nestoji 45 zlata")
	for n in [1, 2, 5, 10, 20]:
		var pay: float = float(Upgrades.temp_cost("gk", n - 1)) / float(n)
		_check(absf(pay - 5.0 * float(n)) < 0.0001,
			"%d. krok zlata za zabiti se nezaplati za %d zabiti (%.1f)" % [n, 5 * n, pay])


# ZLATY OBEH JE PETKRAT MENSI (Oct 2026). Jan: "výdělky za zabití poutníků
# budou úměrně taky nižší. Ať je pocitově upgrade stejně drahý v poměru počet
# zabitých/nový upgrade ... Jde spíš o optický rozdíl."
#
# Kdyby se zmensila JEN cena upgradů a ne vydelek (nebo naopak), zmenil by se
# pomer "kolik zabiti na upgrade" a hra by se rozjela - presne to se stalo
# s linearni cenou, po ktere si hrac koupil pres 80 kroku poskozeni. Test proto
# hlida OBE STRANY a jeste vztah mezi nimi.
func _test_economy_scale() -> void:
	_check(Upgrades.temp_cost("ad", 0) == 1, "prvni krok nestoji 1 zlato")
	_check(Game.START_GOLD == 12, "start zlata neni 12 (%d)" % Game.START_GOLD)
	# START = 12x CENA PRVNIHO KROKU (driv 60 : 5) - hrac si na zacatku koupi
	# dva kroky, ne deset.
	_check(absf(float(Game.START_GOLD) / float(Upgrades.temp_cost("ad", 0)) - 12.0) < 0.001,
		"start zlata neni 12x cena prvniho kroku")
	# ZLATO ZA ZABITI (driv 18/10/14/16/14/26, dnes petkrat mene) a POMER MEZI
	# BARVAMI: zluta zustava nejlevnejsi, stribrna nejdrazsi. Kdyby se barvy
	# prehodily, zmenilo by se, ktera barva se hracovi vyplati nechat projit.
	_check(Hue.gold_of(Hue.YELLOW) == 2, "zluta nedava 2 zlata (%d)" % Hue.gold_of(Hue.YELLOW))
	_check(Hue.gold_of(Hue.RED) == 4, "cervena nedava 4 zlata (%d)" % Hue.gold_of(Hue.RED))
	_check(Hue.gold_of(Hue.SILVER) == 5, "stribrna nedava 5 zlata (%d)" % Hue.gold_of(Hue.SILVER))
	_check(Hue.gold_of(Hue.YELLOW) < Hue.gold_of(Hue.RED), "zluta uz neni levnejsi nez cervena")
	_check(Hue.gold_of(Hue.RED) < Hue.gold_of(Hue.SILVER), "stribrna uz neni drazsi nez cervena")
	# A TOJE CELY SMYSL: POMER "KOLIK ZABITI NA UPGRADE" SE NESMI POHNUT.
	# Historicka hodnota je `5n^2 / 18` (cena kroku / zlato za cervenou) a
	# dnesni cisla musi dat to same - proto se obe strany deli stejnym cislem.
	# Tolerance 12 % je zaokrouhleni (18/5 = 3,6 -> 4).
	for n in [1, 2, 5, 8]:
		var today: float = float(Upgrades.temp_cost("ad", n - 1)) / float(Hue.gold_of(Hue.RED))
		var before: float = 5.0 * float(n) * float(n) / 18.0
		_check(absf(today - before) < before * 0.12,
			"%d. krok stoji %.1f zabiti cervene (driv %.1f) - pomer se pohnul"
			% [n, today, before])


func _test_perm_cost() -> void:
	_check(Upgrades.perm_cost("ad", 0) == 1, "prvni permanentni stupen nestoji 1 bod")
	_check(Upgrades.perm_cost("ad", 2) == 1, "treti permanentni stupen nestoji 1 bod")
	_check(Upgrades.perm_cost("ad", 3) == 2, "ctvrty permanentni stupen nestoji 2 body")
	# Specialy jsou nove mechaniky, ne cisla - musi byt drazsi.
	# MULTISHOT A ODRAZ JSOU NASOBICE POSKOZENI, PROTO JSOU VEDOME DRAHE
	# (Oct 2026, viz `Upgrades.STATS`): multishot strili na pet cilu zaraz
	# (5x poskozeni), odraz posle jeden paprsek pres 4 dalsi cile.
	# S cenou 3 a 4 body si je hrac koupil CELE JESTE V PRVNIM LEVELU.
	_check(Upgrades.perm_cost("ms", 0) == 50, "multishot nestoji 50 bodu")
	_check(Upgrades.perm_cost("rc", 0) == 60, "odraz nestoji 60 bodu")
	_check(Upgrades.perm_cost("ps", 1) == 8, "druhy stupen jedu nestoji 8 bodu")
	_check(Upgrades.perm_cost("ms", 3) == 200, "ctvrty stupen multishotu nestoji 200 bodu")
	# A POMER K OBYCEJNEMU UPGRADU: multiplikator poskozeni musi stat radove
	# vic nez jedna polozka v ciselne ose (ad stoji 1 bod), jinak se vyplati
	# koupit ho driv nez poskozeni - a presne to hru rozbiji.
	_check(Upgrades.perm_cost("ms", 0) >= 10 * Upgrades.perm_cost("ad", 0),
		"multishot je prilis levny proti poskozeni (%d vs %d)"
		% [Upgrades.perm_cost("ms", 0), Upgrades.perm_cost("ad", 0)])
	_check(Upgrades.perm_cost("rc", 0) >= 10 * Upgrades.perm_cost("ad", 0),
		"odraz je prilis levny proti poskozeni (%d vs %d)"
		% [Upgrades.perm_cost("rc", 0), Upgrades.perm_cost("ad", 0)])


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
		if String(s["kind"]) == "levels" or String(s["kind"]) == "chain":
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
	_check(Upgrades.stats_in(Upgrades.CAT_SPEC).size() == 6, "kategorie special nema 6 parametru")
	_check(Upgrades.CATEGORIES.size() == 4, "kategorii neni ctvero")


func _test_texts() -> void:
	for s in Upgrades.STATS:
		var id: String = String(s["id"])
		var t: String = Upgrades.value_text(id, 0, 0)
		_check(t != "", "%s: hodnota se vytiskne prazdna" % id)
		_check(not t.contains("."), "%s: hodnota ma tecku misto ceske carky (%s)" % [id, t])
		_check(String(s["label"]) != "", "%s: popisek je prazdny" % id)
	_check(Upgrades.value_text("ad", 0, 1) == "16", "text poskozeni neni 16")
	_check(Upgrades.value_text("ar", 6, 0) == "40 %", "text dostrelu neni 40 %")


func _test_profile_buy() -> void:
	var p := Profile.new()
	p.body = 10
	_check(p.perm_level("ad") == 0, "novy profil uz ma upgrade")
	_check(p.buy_perm("ad"), "koupe za dost bodu se nepovedla")
	_check(p.perm_level("ad") == 1, "stupen se nezapisal")
	_check(p.body == 9, "body se neodecetly (zbyva %d)" % p.body)
	# PRVNI TRI STUPNE STOJI PO JEDNOM BODU (1 + (n-1)/3).
	_check(p.buy_perm("ad") and p.buy_perm("ad"), "druhy nebo treti stupen nejde")
	_check(p.body == 7, "tri stupne nestaly 3 body (zbyva %d)" % p.body)
	_check(Upgrades.perm_cost("ad", 3) == 2, "ctvrty stupen nestoji 2 body")
	_check(p.buy_perm("ad"), "ctvrty stupen za 2 body nejde")
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
