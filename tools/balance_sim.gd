extends SceneTree

# ZMERENI OBTIZNOSTI. Hraje partii za skriptovaneho hrace a vypisuje, jak si
# vodi - kolik poutniku proslo, kolik zbylo zivotu a jak rostla paleta.
#
# PROČ: "nemá to to správné napětí" se neda vyresit dojmem. V predchozi hre se
# takhle zjistilo, ze zed obtiznosti prisla az po konci levelu (hrac dohral
# se ctyrmi zivoty a nikdy se nedostal pod tlak).
#
# Hrac je zamerne HLUPY a cte jen to, co je videt: prepne na barvu, ktera ma
# v dostrelu nejvic poutniku, a kdyz ma zlato, koupi vylepseni. Co tenhle hrac
# nezvladne, je pro cloveka zajimave; co zvladne, je nuda.
#
# Pouziti:
#   godot4 --headless --path . --script res://tools/balance_sim.gd
#   ... -- --waves=6      (kratci partie)

var waves_limit: int = Game.WAVE_MAX
var _switches: int = 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--waves="):
			waves_limit = int(a.split("=")[1])
	_run()
	quit()


func _run() -> void:
	var g := Game.new()
	# ROZVRZENI SE BERE ZE `ScreenLayout`, ne opsane rucne. Telefon na vysku
	# (iPhone 14) - polomer plochy dnes urcuje VYSKA herniho pruhu (spawnovaci
	# kruh je vetsi nez displej), takze opsana cisla by merila jinou hru.
	var l := ScreenLayout.new()
	l.update(Vector2(390.0, 844.0))
	g.set_field(l.field_r, l.unit_r, l.center)
	var dt: float = 1.0 / 60.0
	var t: float = 0.0
	var last_wave: int = 0
	var printed: Dictionary = {}
	print("  vlna  poutniku  barvy   stav")
	while not g.is_over() and t < 900.0:
		_play(g)
		g.step(dt)
		t += dt
		if g.wave != last_wave:
			last_wave = g.wave
			if not printed.has(g.wave) and g.wave <= waves_limit:
				printed[g.wave] = true
				print("  %4d  %8d  %5d   %s"
					% [g.wave, Game.WAVE_SIZES[clampi(g.wave - 1, 0, 9)],
						g.palette.size(), _row(g)])
		if g.phase == "lost":
			break
	print("  konec: faze=%s, vlna=%d, zbyva zivotu=%d, zlato=%d, stupen veze=%d"
		% [g.phase, g.wave, g.lives, g.gold, g.tower.level])
	# POCET PREPNUTI je odpoved na "aby hrac jen tupě nezíral": kolikrat za
	# partii musi hrac opravdu neco udelat. Nula by znamenala, ze mechanika
	# nema na hru vliv, i kdyby cisla vypadala dobre.
	print("  hrac za partii: %d prepnuti barvy za %.1f s (%.1f za vlnu)"
		% [_switches, t, float(_switches) / maxf(1.0, float(g.wave))])
	print("SIM_END phase=%s wave=%d lives=%d switches=%d"
		% [g.phase, g.wave, g.lives, _switches])


func _row(g: Game) -> String:
	return ("zivoty=%-3d zlato=%-5d dostrel=%d%% cilu=%d"
		% [g.lives, g.gold, int(round(g.tower.range_frac() * 100.0)), g.tower.targets()])


# SKRIPTOVANY HRAC: prepne na barvu, ktera ma v dostrelu nejvic poutniku.
func _play(g: Game) -> void:
	if g.tower.can_upgrade() and g.gold >= g.tower.upgrade_cost() and g.phase == "build":
		g.buy_upgrade()
	var r: float = g.tower.range_px(g.field_r)
	var counts: Dictionary = {}
	var best_h: int = -1
	var best_n: int = -1
	for p in g.pilgrims:
		if not p.alive or not p.targetable() or not g.in_range(p, r):
			continue
		if not g.palette.has(p.hue):
			continue
		counts[p.hue] = int(counts.get(p.hue, 0)) + 1
	for h in counts:
		if int(counts[h]) > best_n:
			best_n = int(counts[h])
			best_h = int(h)
	if best_h >= 0 and best_h != g.tower.hue:
		g.select_hue(best_h)
		_switches += 1
