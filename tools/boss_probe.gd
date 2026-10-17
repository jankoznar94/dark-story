extends SceneTree

# SONDA BOSS VLNY (docasny nastroj, ne test).
#
# MERI, CO JAN POPISUJE: "Teď vždy hráč pobije všechny ostatní a boss sám pak
# cestuje strašně dlouho k věži o samotě. Ve chvíli, kdy boss dochází k věži,
# ještě musí zabývat nějací nepřátelé."
#
# Hraje partii level 1 s NECITELNYMI zivoty veze (`hp = 1e9`) - jinak by sondu
# zastavil prvni boss a ona by v 10. vlne skoncila. PRO KAZDOU BOSS VLNU VYPISE:
#   * barvu bosse, jeho zivoty a to, jestli ho vez stihla zabit,
#   * cas vstupu a cas, kdy se objevil V DOSTRELU a kdy dosel k vezi
#     (vsechno od zacatku VLNY, ne od stavby pred ni),
#   * KOLIK BEZNYCH POUTNIKU BYLO V TU CHVILI NA PLOSE a kolik jich teprve
#     vstupovalo (= jestli boss dosel sam, nebo uprostred vlny),
#   * kolik jich bylo na plose, kdyz boss UMIRAL/DOSEL.
#
#   godot4 --headless --path . --script res://tools/boss_probe.gd [pocet_vln]

var waves_to_watch: int = 50


func _init() -> void:
	Profile.allow_save = false
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			waves_to_watch = int(a)
	_run()
	quit()


func _run() -> void:
	var g := Game.new()
	var l := ScreenLayout.new()
	l.update(Vector2(390.0, 844.0))
	g.set_field(l.field_r, l.unit_r, l.center)
	g.start_level(1)
	var dt: float = 1.0 / 60.0
	var t: float = 0.0
	var wave: int = -1
	var t0: float = -1.0          # zacatek VLNY (faze "wave"), ne stavby
	var boss: Pilgrim = null
	var t_spawn: float = -1.0
	var t_range: float = -1.0
	var t_end: float = -1.0
	var at_range: Array = []      # [na plose, jeste vstoupi, z celku] v okamziku dostrelu
	var at_end: Array = []
	var rows: Array = []
	var guard: int = 0
	# STROP SIMULACE: 60 minut herniho casu (level ma padesat vln a boss vlny
	# jsou pomale - s dvaceti minutami se sonda dostala jen na 20. vlnu).
	while wave <= waves_to_watch and guard < 60 * 60 * 60:
		guard += 1
		if g.wave != wave:
			if wave >= 1:
				rows.append(_report(g, wave, boss, t_spawn, t_range, t_end, at_range, at_end))
			wave = g.wave
			t0 = -1.0
			boss = null
			t_spawn = -1.0
			t_range = -1.0
			t_end = -1.0
			at_range = []
			at_end = []
		g.step(dt)
		# SONDA NESMI SKONCIT PROHROU - merime casovani, ne obtiznost.
		g.hp = 1.0e9
		g.max_hp = 1.0e9
		t += dt
		if g.phase == "wave" and t0 < 0.0:
			t0 = t
		if t0 < 0.0:
			continue
		if boss == null:
			for p in g.pilgrims:
				if p.is_boss and p.alive:
					boss = p
					t_spawn = t - t0
					break
			continue
		if t_range < 0.0 and boss.alive and g.in_range(boss, g.range_px()):
			t_range = t - t0
			at_range = _counts(g)
		if t_end < 0.0 and not boss.alive:
			t_end = t - t0
			at_end = _counts(g)
	for row in rows:
		print(row)
	print("BOSS_PROBE_END vln=%d, guard=%d, t=%.0f" % [waves_to_watch, guard, t])


# [na plose, jeste vstoupi, z celku] - bez bosse.
func _counts(g: Game) -> Array:
	var alive: int = 0
	for p in g.pilgrims:
		if p.alive and not p.is_boss:
			alive += 1
	return [alive, maxi(0, g.plan.size() - g.spawned), g.plan.size()]


func _report(g: Game, wave: int, boss: Pilgrim, t_spawn: float, t_range: float, t_end: float,
		at_range: Array, at_end: Array) -> String:
	if boss == null:
		return "VLNA %d: boss se neobjevil" % wave
	var killed: String = "ZABIT" if boss.hp <= 0.0 else "DOSEL K VEZI se %d ziv." % int(ceil(boss.hp))
	var out: String = ("VLNA %2d: %-9s boss %5.0f ziv. · cesta %.1f s · vstup %5.1f s"
		% [wave, Hue.name_of(boss.hue), boss.max_hp, Game.TRAVEL_S / Game.BOSS_SPEED_MULT, t_spawn]
		+ " · v dostrelu %5.1f s" % t_range)
	if t_range >= 0.0:
		out += " · TEHDY na plose %d poutniku (+%d jeste vstupuje z %d)" % [at_range[0], at_range[1], at_range[2]]
	out += " · %s v %.1f s" % [killed, t_end]
	if t_end >= 0.0:
		out += " · pri konci na plose %d poutniku" % at_end[0]
	return out
