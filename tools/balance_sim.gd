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

# V BITVE: co koupit prvni. Kadenci a poskozeni hrac vidi na prvni pohled.
# DOSTREL TU NENI - je jen permanentni (v bitve se ani nenabizi).
const TEMP_ORDER := ["as", "as", "ad", "hp", "as", "am", "ad", "cc", "hp", "rg", "cd", "gk", "gw", "gl"]
# V MENU: co koupit permanentne. Dostrel je tu vzdy - v bitve jinak neni.
const PERM_ORDER := ["as", "ar", "ad", "hp", "am", "as", "ar", "cc", "rg", "cd", "as", "hp", "gk", "ps", "ic", "ms", "gw", "gl", "rc"]

var levels_limit: int = 8
# CASOVY STROP PARTIE. Deset vln na level znamena ~5 minut na level, takze
# strop musi byt vysoky - jinak sim skonci "DOHRANO" a nic to nerekne o tom,
# kde se hra opravdu láme.
var time_limit: float = 3600.0
var _switches: int = 0


func _init() -> void:
	Upgrades.STATS.size()
	Profile.allow_save = false     # simulátor NESMI prepsat hracuv postup
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--levels="):
			levels_limit = int(a.split("=")[1])
		if a.begins_with("--time="):
			time_limit = float(a.split("=")[1])
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
	while g.level <= levels_limit and t < time_limit and guard < 400000:
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
	else:
		print("  DOHRANO: %d levelu za %.0f s" % [levels_limit, t])
	print("  hrac za partii: %d prepnuti barvy (%.1f za level)" % [_switches, float(_switches) / float(maxi(1, g.level))])
	print("SIM_END level=%d wave=%d hp=%d switches=%d" % [g.level, g.wave, int(ceil(g.hp)), _switches])


# NAKUPOVANI V BITVE: kazdy snimek zkusi koupit nejblizsi krok z priority.
func _play(g: Game) -> void:
	for id in TEMP_ORDER:
		var have: int = g.temp_level(id)
		if have >= Upgrades.temp_max(id):
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
