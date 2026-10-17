extends SceneTree

# SONDA MICHANI VLNY (docasny nastroj, ne test).
#
# MERI, CO JAN POPISUJE: "Zluti dorazi mnohem drive nez cerveni a ve chvili,
# kdy dorazi cerveni, uz jsou vsichni zluti mrtvi." Sonda hraje partii (bez
# stavby vezi - vez poskozuje jen tim, co ma na zacatku), a pro kazdou vlnu
# zapisuje:
#   * casy VSTUPU (kdy poutnik vstoupil na plochu),
#   * casy DORAZU (kdy se poprve dostal do dostrelu veze),
# a to zvlast pro kazdou barvu.
# Na konci vypise "promichanost": podil sekundovych oken v dobe dorazu, ve
# kterych dorazily aspon dve barvy. 0 % = barvy se mijejí, 100 % = jdou spolu.
#
#   godot4 --headless --path . --script res://tools/wave_probe.gd [pocet_vln]

var waves_to_watch: int = 5


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
	var wave: int = -1
	var t0: float = 0.0
	var t: float = 0.0
	var known: Dictionary = {}
	var spawn: Dictionary = {}
	var done: Dictionary = {}
	var arrive: Dictionary = {}
	var bins: Dictionary = {}
	var finished: Array = []
	var guard: int = 0
	var frames_any: int = 0
	var frames_mixed: int = 0
	var wave_any: int = 0
	var wave_mixed: int = 0
	while wave <= waves_to_watch and guard < 60 * 60 * 20:
		guard += 1
		# nova vlna = prvni poutnik v planu; merime od prvniho vstupu
		if g.wave != wave:
			if wave >= 1:
				finished.append(_report(wave, spawn, arrive, bins, t - t0, wave_any, wave_mixed))
			wave = g.wave
			t0 = t
			spawn = {}
			done = {}
			arrive = {}
			bins = {}
			wave_any = 0
			wave_mixed = 0
		g.step(dt)
		# VEZDRAVI NA ZKOUSKU: sondu zajima CASOVANI VSTUPU a DORAZU, ne kdy
		# hrac prohraje. Kdyby vez padla, hra by se zastavila v 1. vlne a sonda
		# by nemerila nic (presne to se stalo napoprve: guard=72000, phase=lost,
		# wave=1). Vlny se tim NEMENI - poutnici dal umiraji i dochazeji, jen
		# srdce neupada.
		g.hp = 1.0e9
		g.max_hp = 1.0e9
		t += dt
		# KOLIK BARVY JE PRAVE TED V DOSTRELU. Tohle je to, co hrac vidi: kdyz
		# je v dostrelu jen jedna barva, prepinani barev nema smysl.
		var in_range: Dictionary = {}
		for p in g.pilgrims:
			if p.alive and g.in_range(p, g.range_px()):
				in_range[p.hue] = true
		if not in_range.is_empty():
			frames_any += 1
			wave_any += 1
			if in_range.size() >= 2:
				frames_mixed += 1
				wave_mixed += 1
		for p in g.pilgrims:
			var key: int = p.get_instance_id()
			if not known.has(key):
				known[key] = true
				_add(spawn, p.hue, t - t0)
			elif not done.has(key) and g.in_range(p, g.range_px()):
				done[key] = true
				var sec: int = int(t - t0)
				_add(bins, "%d|%d" % [sec, p.hue], 1.0)
				_add(arrive, p.hue, t - t0)
	for row in finished:
		print(row)
	print("PROBE END vln=%d, guard=%d, t=%.0f, phase=%s, wave=%d" % [waves_to_watch, guard, t, g.phase, g.wave])


func _add(d: Dictionary, key: Variant, v: float) -> void:
	if not d.has(key):
		d[key] = []
	d[key].append(v)


# JEDNO CISLO: podil sekund, ve kterych dorazily aspon dve barvy.
func _mix_frac(arrive: Dictionary, bins: Dictionary) -> float:
	var first: float = 1e9
	var last: float = -1.0
	for h in arrive.keys():
		for v in arrive[h]:
			first = minf(first, v)
			last = maxf(last, v)
	if last < 0.0 or last - first < 1.0:
		return 0.0
	var mixed: int = 0
	var total: int = 0
	for s in range(int(first), int(last) + 1):
		total += 1
		var hues: int = 0
		for h in arrive.keys():
			if bins.has("%d|%d" % [s, h]):
				hues += 1
		if hues >= 2:
			mixed += 1
	return float(mixed) / float(maxi(1, total))


func _span(arr: Array) -> Array:
	if arr.is_empty():
		return [0.0, 0.0]
	return [arr.min(), arr.max()]


func _report(wave: int, spawn: Dictionary, arrive: Dictionary, bins: Dictionary, wave_s: float,
		any_f: int, mixed_f: int) -> String:
	var both: float = 100.0 * float(mixed_f) / float(maxi(1, any_f))
	var head: String = "VLNA %d: délka %.0f s, míchání %d %%, obě barvy v dostřelu %d %% z %d snimku" % [
		wave, wave_s, int(round(100.0 * _mix_frac(arrive, bins))), int(round(both)), any_f]
	var lines: Array = [head]
	for h in spawn.keys():
		var sp: Array = _span(spawn[h])
		var ar: Array = _span(arrive.get(h, []))
		lines.append("   %-9s vstup %5.1f-%5.1f s (%d)   doraz %5.1f-%5.1f s (%d)" % [
			Hue.name_of(int(h)), sp[0], sp[1], spawn[h].size(),
			ar[0], ar[1], arrive.get(h, []).size()])
	return "\n".join(lines)
