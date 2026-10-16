extends SceneTree

# SONDA: STRIBRNA MENI PODOBU (Oct 2026). Hra se krokuje jako v bitve a sonda
# vypisuje kazdou zmenu: barvu, schopnost, zivotni pool a RYCHLOST.
#
# Pouziti: godot4 --headless --path . --script res://tools/shift_probe.gd
#
# Testy (`test_core._test_silver_shift_form`) overuji pravidla, tahle sonda
# ukazuje, jak to vypada v opravdovem kroku hry - hlavne ze zmena prijde po
# PETI vterinach herniho casu a ze se pri ni prenasi PROCENTO zivotu.

const START_HP_FRAC := 0.40
const SEKUND := 30.0


func _init() -> void:
	Profile.allow_save = false
	var g := Game.new()
	g.profile = Profile.new()
	var l := ScreenLayout.new()
	l.update(Vector2(390.0, 844.0))
	g.set_field(l.field_r, l.unit_r, l.center)
	g.start_level(5)
	# Faze "test" = zadna vlna, jen pohyb, vez a efekty (jako v testech).
	g.phase = "test"
	g.plan = []
	g.spawned = 0
	g.pilgrims = []
	g.locks = []
	g.beams = []

	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.SILVER)
	# SONDA MERI PODOBU, NE CHUZI: poutnik stoji na miste (mimo dostrel veze),
	# aby za 30 s prosel sest podob a nezomrel na to, ze dosel k vezi.
	p.dir = Vector2.ZERO
	p.hp = p.max_hp * START_HP_FRAC
	_vypis(0.0, p, "start")

	var t: float = 0.0
	var last: int = p.hue
	while t < SEKUND:
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
		# VEZ JE CERVENA A STRIBRNA SE MENI I V JEJI BARVU - aby poutnik ve
		# sonde nezomrel, drzi se na 40 % (a je videt, ze to procento zmena
		# podoby opravdu drzi).
		if p.hp_frac() > START_HP_FRAC + 0.01:
			p.hp = p.max_hp * START_HP_FRAC
		if p.hue != last:
			last = p.hue
			_vypis(t, p, "zmena")
		if not p.alive:
			print("t=%.1f s: poutnik umrel" % t)
			break
	print("SHIFT_PROBE_DONE=true")
	quit()


func _vypis(t: float, p: Pilgrim, co: String) -> void:
	print("t=%5.1f s  %-8s %-9s zivoty %6.1f / %6.1f (%3.0f %%)  rychlost %.1f px/s  chovani %s"
		% [t, co, Hue.name_of(p.hue), p.hp, p.max_hp, p.hp_frac() * 100.0,
			p.speed, p.behaviour])
