extends SceneTree

# SONDA BOSSU (docasny nastroj, ne test).
#
# ODPOVIDA NA JANOVU OTAZKU: "Zluty nemuze zemrit drive, nez si ho vsimnu.
# Ma byt veliky. Vyrazne jiny nez ostatni nepratele kolem. Vsiml bych si ho,
# kdyby tam byl."
#
# Dve veci se tu meri:
#   1. CHODI ZLUTY BOSS VUBEC? Bere se to z REALNE CESTY (`_start_wave`), ne
#      z `wave_plan` - hra si plan sklada i s urovnemi a jinym poradim losovani,
#      takze mereni mimo `_start_wave` by merilo jiny svet.
#   2. STIHNE BOSS DOJIT K VEZI, nebo ho vez zabije cestou? U bosse plati, ze
#      vez se deli mezi nej a poutniky vlny, takze se pocita DOBA, kterou boss
#      stravi v dostrelu (`TRAVEL_S / BOSS_SPEED_MULT` minus cas, nez do
#      dostrelu vstoupi), a poskozeni vezе, ktere na nej za tu dobu padne.
#
#   godot4 --headless --path . --script res://tools/boss_color_probe.gd [levely]

var levels: int = 3


func _init() -> void:
	Profile.allow_save = false
	BattleSave.allow_save = false
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			levels = int(a)
	var l := ScreenLayout.new()
	l.update(Vector2(390.0, 844.0))
	# POSKOZENI VEZE: bere se ze hry samotne (bez nakupu = zaklad), aby cisla
	# nebyla opsana. Hrac ma na 10. vlne prvniho levelu nakoupeno - proto se
	# tiskne i "kolik DPS staci na cerveneho bosse dnes".
	for lv in range(1, levels + 1):
		var g := Game.new()
		g.set_field(l.field_r, l.unit_r, l.center)
		g.start_level(lv)
		var colors: Array = []
		var rows: Array = []
		for w in range(1, Game.WAVES_PER_LEVEL + 1):
			if not g.boss_wave(w):
				continue
			g.wave = w
			g._start_wave()
			var idx: int = clampi(g.boss_at, 0, g.plan.size() - 1)
			var h: int = int(g.plan[idx])
			var tier: int = int(g.plan_tier[idx])
			colors.append(Hue.name_of(h))
			# NOVE PRAVIDLO (`Game.boss_hp`) proti STARE (zivoty se nasobily
			# barvou) - aby bylo videt, co se ktere barve stalo.
			var now: float = g.boss_hp()
			var before: float = Game.BASE_HP * pow(Game.LEVEL_HP, float(lv - 1)) \
				* pow(Game.WAVE_HP, float(w - 1)) * Hue.hp_mult(h) * Game.BOSS_HP_MULT
			rows.append("v%02d %-9s nyni %6.0f ziv. (drive %6.0f, %+.0f %%)"
				% [w, Hue.name_of(h), now, before, (now / before - 1.0) * 100.0])
		print("LEVEL %d (pool %d barev): %s" % [lv, Hue.palette_at(lv).size(), ", ".join(colors)])
		for r in rows:
			print("      %s" % r)
	# DOBA V DOSTRELU: boss jde celou cestu 1/5 rychlosti, dostrel je zlomek
	# cesty - doba, po kterou na nej vez muze strilet, je tedy zlomek cesty.
	var g2 := Game.new()
	g2.set_field(l.field_r, l.unit_r, l.center)
	g2.start_level(1)
	print("dostrel je %.2f cesty, boss jde %.1f s, v dostrelu je %.1f s"
		% [g2.range_frac(), Game.TRAVEL_S / Game.BOSS_SPEED_MULT,
		g2.range_frac() * Game.TRAVEL_S / Game.BOSS_SPEED_MULT])
	# JAK JE BOSS VELKY (Jan: "Ma byt veliky. Vyrazne jiny nez ostatni
	# nepratele kolem.") - polomer v pixelech na telefonu 390x844.
	print("na 390x844: poutnik %.1f px v polomeru, boss %.1f px (%.2fx)"
		% [l.pilgrim_r * Game.PILGRIM_SIZE,
		l.pilgrim_r * Game.PILGRIM_SIZE * Game.BOSS_SIZE, Game.BOSS_SIZE])
	print("driv: zluty boss 329 ziv. proti 1033 cerveneho na stejne vlne - "
		+ "umrel za 23,5 s z 26 s okna, tedy TISE mezi poutniky")
	quit()

