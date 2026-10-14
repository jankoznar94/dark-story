extends SceneTree

# ZMERENI OBTIZNOSTI. Hraje partii za skriptovaneho hrace a vypisuje, jak si
# vodi - kolik poutniku proslo, kolik zilo zivotu a jak se zvetsoval dostrel.
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
#   ... --waves 20          (delsi partie, nez level dovoli)

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
	# Rozvrzeni telefonu na vysku (iPhone 14): plocha je to, co omezi sirka.
	g.set_field(183.3, 22.0, Vector2(195.0, 460.0))
	g.wave = 1
	var dt: float = 1.0 / 60.0
	var t: float = 0.0
	var passed: int = 0
	var last_wave: int = 0
	var printed: Dictionary = {}
	print("  vlna  poutniku  zivoty  zlato  dostrel")
	while not g.is_over() and t < 600.0:
		_play(g)
		g.step(dt)
		t += dt
		if g.wave != last_wave:
			last_wave = g.wave
			if not printed.has(g.wave) and g.wave <= waves_limit:
				printed[g.wave] = true
				print("  %4d  %s" % [g.wave, _row(g)])
		if g.phase == "lost":
			break
	print("  konec: faze=%s, vlna=%d, zbyva zivotu=%d, zlato=%d, stupen veze=%d"
		% [g.phase, g.wave, g.lives, g.gold, g.tower.level])
	# POCET PREPNUTI je odpoved na "aby hrac jen tupě nezíral": kolikrat za
	# partii musi hrac opravdu neco udelat. Nula by znamenala, ze mechanika
	# nema na hru vliv, i kdyby cisla vypadala dobre.
	print("  hrac za partii: %d prepnuti barvy za %.1f s (%.1f za vlnu)"
		% [_switches, t, float(_switches) / maxf(1.0, float(g.wave))])
	print("SIM_END phase=%s wave=%d lives=%d switches=%d" % [g.phase, g.wave, g.lives, _switches])


func _row(g: Game) -> String:
	return "zivoty=%-3d zlato=%-4d dostrel=%d%% cilu=%d" % [
		g.lives, g.gold, int(round(g.tower.range_frac() * 100.0)), g.tower.targets()]


# SKRIPTOVANY HRAC: prepni na barvu, ktera ma v dostrelu nejvic poutniku.
# Kdyz je nejvic prazdno, zustan na te, ktera ma nejblizsiho.
func _play(g: Game) -> void:
	if not g.tower.can_upgrade() and g.gold < 999999:
		pass
	if g.tower.can_upgrade() and g.gold >= g.tower.upgrade_cost() and g.phase == "build":
		g.buy_upgrade()
	var r: float = g.tower.range_px(g.field_r)
	var counts: Dictionary = {}
	var best_el: int = -1
	var best_n: int = -1
	for p in g.pilgrims:
		if not p.alive or not g.in_range(p, r):
			continue
		counts[p.element] = int(counts.get(p.element, 0)) + 1
	for e in counts:
		if int(counts[e]) > best_n:
			best_n = int(counts[e])
			best_el = int(e)
	if best_el >= 0 and best_el != g.tower.element:
		g.tower.set_element(best_el)
		_switches += 1
