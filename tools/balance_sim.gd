extends SceneTree

# ZMERENI OBTIZNOSTI. Hraje partii za skriptovaneho hrace - level po levelu,
# v bitve nakupuje docasne kroky za zlato, v menu permanentni za body - a
# vypisuje, jak si vodi.
#
# PROČ: "nemá to to správné napětí" se neda vyresit dojmem. Tohle je jedine
# misto, kde se pozna, jestli se hra da dohrat a jestli je dost tezka.
#
# Hrac je zamerne HLUPY a cte jen to, co je videt: prepne na barvu, ktera ma
# v dostrelu nejvic poutniku, a kdyz ma zlato (nebo body), koupi nejblizsi
# upgrade v poradi priority. Co tenhle hrac nezvladne, je pro cloveka
# zajimave; co zvladne, je nuda.
#
# Pouziti:
#   godot4 --headless --path . --script res://tools/balance_sim.gd
#   ... -- --levels=8      (kolik levelu nejdal)

# V BITVE: co koupit prvni. Poskozeni hrac vidi na prvni pohled.
# DOSTREL TU NENI - je jen permanentni (v bitve se ani nenabizi).
# KADENCE TU NENI TAKY: od Oct 2026 vez sviti laserem a zadny Attack speed
# upgrade neexistuje (Jan: "Tim padem zrusime uplne Attack speed upgrady").
const TEMP_ORDER := ["ad", "ap", "ad", "ap", "hp", "am", "cc", "hp", "rg", "cd", "gk", "gw", "gl"]
# HRAC, KTERY SYPE VSECHNO DO POSKOZENI (Jan, Oct 2026: "...a hráč nestíhá věž
# vylepšovat tak, aby stíhala zabíjet všechny nepřátele, i když investuje
# všechny peníze do poškození."). Tohle je merko teho, jestli se hra da dohrat
# silou: kdyz i tenhle hrac padne, neni to o hracovi, ale o tabulce.
# `--order=damage`
const ALLIN_ORDER := ["ad", "ap", "ad", "ap", "ad", "ap", "ad", "ap", "hp", "hp"]
# V MENU: co koupit permanentne. Dostrel je tu vzdy - v bitve jinak neni.
const PERM_ORDER := ["ad", "ar", "ap", "ad", "hp", "am", "ar", "cc", "rg", "cd", "hp", "gk", "ps", "ic", "ms", "gw", "gl", "rc"]

var levels_limit: int = 8
# KTERY HRAC SE HRAJE (viz `ALLIN_ORDER`).
var temp_order: Array = TEMP_ORDER
# CASOVY STROP PARTIE. Level ma od Oct 2026 TRICET vln (~22 min na level
# zmereno) - strop musi byt vysoky, jinak sim skonci "DOHRANO" a nic to nerekne
# o tom, kde se hra opravdu láme. Pro srovnani s minulosti je lepsi merit
# `--levels=2` a CAS NA LEVEL, ne kolik levelu se stihne za hodinu.
var time_limit: float = 20000.0
var _switches: int = 0


func _init() -> void:
	Upgrades.STATS.size()
	Profile.allow_save = false     # simulátor NESMI prepsat hracuv postup
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--levels="):
			levels_limit = int(a.split("=")[1])
		if a.begins_with("--time="):
			time_limit = float(a.split("=")[1])
		if a.begins_with("--order="):
			temp_order = ALLIN_ORDER if a.split("=")[1] == "damage" else TEMP_ORDER
	_run()
	quit()


func _run() -> void:
	var g := Game.new()
	# ROZVRZENI SE BERE ZE `ScreenLayout`, ne opsane rucne - opsana cisla uz
	# jednou zustala stat, kdyz se zmenilo, co polomer plochy urcuje.
	var l := ScreenLayout.new()
	l.update(Vector2(390.0, 844.0))
	g.set_field(l.field_r, l.unit_r, l.center)
	g.start_level(1)
	var dt: float = 1.0 / 60.0
	var t: float = 0.0
	var last_key: String = ""
	print("  level  vlna  zivoty  zlato  body  perm+temp")
	var guard: int = 0
	# POJISTKA PROTI ZACYCLENI. Je to pocet SNIMKU (60 za sekundu herniho casu),
	# takze 2 000 000 je ~9 hodin partie - dost na to, aby se padesativlnove
	# levely (~54 min) vubec stihly zmerit. Nizsi strop uz jednou utnul beh
	# uprostred tretiho levelu a vypadal jako "dohrano".
	while g.level <= levels_limit and t < time_limit and guard < 2000000:
		guard += 1
		_play(g)
		g.step(dt)
		t += dt
		var key: String = "%d.%d" % [g.level, g.wave]
		if key != last_key:
			last_key = key
			print("  %5d  %4d  %6d  %5d  %4d  %s"
				% [g.level, g.wave, int(ceil(g.hp)), g.gold, g.profile.body,
					Upgrades.summary(g.profile.perm, g.temp)])
		if g.phase == "lost":
			break
		if g.phase == "won":
			_shop(g)
			g.next_level()
	if g.phase == "lost":
		print("  KONEC: vez padla na levelu %d (%d. vlna), cas %.0f s" % [g.level, g.wave, t])
	elif g.level > levels_limit:
		print("  DOHRANO: %d levelu za %.0f s" % [levels_limit, t])
	else:
		# STOP UPROSTRED HRY NENI "DOHRANO". Kdo si to splete, precte si ze hry,
		# ktera se ukoncila stropem, ze hrac dohral - a udela z toho spatny
		# zaver o obtiznosti (přesně to se stalo pri prvnim mereni padesati vln).
		print("  STOP: cas %.0f s (strop) - dohrano %d levelu, hra na %d. levelu, %d. vlne, zivoty veze %d"
			% [t, g.level - 1, g.level, g.wave, int(ceil(g.hp))])
	print("  hrac za partii: %d prepnuti barvy (%.1f za level)" % [_switches, float(_switches) / float(maxi(1, g.level))])
	print("SIM_END level=%d wave=%d hp=%d switches=%d" % [g.level, g.wave, int(ceil(g.hp)), _switches])


# NAKUPOVANI V BITVE: kazdy snimek zkusi koupit nejblizsi krok z priority.
func _play(g: Game) -> void:
	for id in temp_order:
		var have: int = g.temp_level(id)
		# DOCASNE ZEBRICKY JSOU NEOMEZENE - ptáme se na cenu, ne na strop.
		if Upgrades.temp_is_maxed(id, have):
			continue
		if g.gold >= Upgrades.temp_cost(id, have):
			g.buy_temp(id)
			break
	_switch(g)


# NAKUPOVANI V MENU: dokud jsou body, kupuj permanentni stupne.
func _shop(g: Game) -> void:
	var guard: int = 0
	while guard < 200:
		guard += 1
		var bought: bool = false
		for id in PERM_ORDER:
			if g.profile.perm_level(id) >= Upgrades.perm_max(id):
				continue
			var cost: int = Upgrades.perm_cost(id, g.profile.perm_level(id))
			if g.profile.body >= cost:
				if g.buy_perm(id):
					bought = true
					break
		if not bought:
			return


# SKRIPTOVANY HRAC: prepne na barvu, ktera ma v dostrelu nejvic poutniku.
func _switch(g: Game) -> void:
	var r: float = g.range_px()
	var counts: Dictionary = {}
	var best_h: int = -1
	var best_n: int = -1
	for p in g.pilgrims:
		if not p.alive or not p.targetable() or not g.in_range(p, r):
			continue
		if not g.tower.palette.has(p.hue):
			continue
		counts[p.hue] = int(counts.get(p.hue, 0)) + 1
	for h in counts:
		if int(counts[h]) > best_n:
			best_n = int(counts[h])
			best_h = int(h)
	if best_h >= 0 and best_h != g.tower.hue:
		g.select_hue(best_h)
		_switches += 1
