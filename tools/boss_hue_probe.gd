extends SceneTree

# DOCASNA SONDA: jakou barvu maji bossove v jednotlivych vlnach.
# Boss je poutnik na indexu `BOSS_SPAWN_FRAC` (0,0 = prvni) vlny, takze staci
# slozit plan vlny a prectenou barvu vypsat. `wave_plan` pouziva rng hry, takze
# se poradi opakuje jen dokud se nemeni neco, co do rng saha.
#
#   godot4 --headless --path . --script res://tools/boss_hue_probe.gd [levely]

func _init() -> void:
	Profile.allow_save = false
	var levels: int = 3
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			levels = int(a)
	var g := Game.new()
	for lv in range(1, levels + 1):
		g.start_level(lv)
		var line: Array = []
		for w in range(1, Game.WAVES_PER_LEVEL + 1):
			if not g.boss_wave(w):
				continue
			var plan: Array = g.wave_plan(w)
			var idx: int = int(round(float(plan.size()) * Game.BOSS_SPAWN_FRAC))
			line.append("v%d:%s" % [w, Hue.name_of(int(plan[clampi(idx, 0, plan.size() - 1)]))])
		print("LEVEL %d (pool %s): %s" % [lv, Hue.palette_at(lv), " ".join(line)])
	quit()
