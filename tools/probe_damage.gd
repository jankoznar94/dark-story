extends SceneTree

# Diagnostika: proc se nepocita poskozeni.

func _init() -> void:
	var g := Game.new()
	g.setup(Rect2(40.0, 80.0, 880.0, 420.0))
	g.gold = 999
	var b1: bool = g.try_build(1, 0, Element.WATER)
	var b2: bool = g.try_build(1, 1, Element.WATER)
	print("build1=%s build2=%s towers=%d gold=%d" % [b1, b2, g.towers.size(), g.gold])
	for item in g.towers:
		var t: Tower = item
		print("  vez lane=%d slot=%d el=%d lvl=%d dps=%.1f" % [t.lane, t.slot, t.element, t.level, t.dps()])
	print("at(1,0)=%s at(1,1)=%s" % [g.tower_at(1, 0) != null, g.tower_at(1, 1) != null])
	g.set_switch(1)
	print("switch_lane=%d" % g.net.switch_lane)
	print("trunk_len=%.1f lane_len[1]=%.1f" % [g.net.trunk_len, g.net.lane_len[1]])
	print("mult(fire,water)=%.2f" % Element.multiplier(Element.FIRE, Element.WATER))

	g.phase = "wave"
	g.spawn_left = 0
	g.wave = 1
	g._spawn(Element.FIRE)
	var e: Enemy = g.enemies[0]
	print("nepritel: el=%d hp=%.1f speed=%.1f lane=%d" % [e.element, e.hp, e.speed, e.lane])

	for i in range(1800):
		g.step(1.0 / 60.0)
		if i % 120 == 0:
			print("  t=%.1fs lane=%d s=%.0f hp=%.2f enemies=%d lives=%d alive=%s" % [
				float(i) / 60.0, e.lane, e.s, e.hp, g.enemies.size(), g.lives, e.alive])
	print("konec: hp=%.2f enemies=%d lives=%d alive=%s" % [e.hp, g.enemies.size(), g.lives, e.alive])
	print("log:")
	for l in g.log:
		print("  " + str(l))
	quit()
