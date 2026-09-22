extends SceneTree
## test_duel_distance — the duel arena's distance rule and the class kit.
##
## Two failures this pins, both of which looked like "the combat does not work":
##
##   1. The hero swung the instant the fight started, because `_gap` was never ported.
##      The PWA starts at maximum separation, the hero walks in, and out of his weapon's
##      reach the swing is DISCARDED and restarted. The first hit therefore lands at
##      624-1024 ms, not at 0.
##   2. The hero had the wrong HP and almost no mana, because `set_class()` set
##      `heroClass` and never applied the class's `attrBonus`. VIT seeds max HP and INT
##      seeds max mana, so the pools were level-1 pools for the whole game.
##
## Both are RULES, so both are assertable here. Run:
##   godot4 --headless --path . --script res://tools/test_duel_distance.gd

const GameData := preload("res://scripts/data/game_data.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Progression := preload("res://scripts/combat/progression.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")

var _ok := true


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		print("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])
		_ok = false


func _initialize() -> void:
	var data := GameData.new()
	var state := GameState.new()
	state.bind_data(data)
	var prog := Progression.new(data)
	var find_item := func(id: Variant) -> Dictionary:
		return data.item(str(id)) if id != null else {}

	print("== class kit (attrBonus -> attributes -> pools) ==")
	var cls: Dictionary = data.class_by_id("barbarian")
	var bonus: Dictionary = cls.get("attrBonus", {})
	state.set_class("barbarian")
	var hero: Dictionary = state.hero()
	_check("attrStr from the class", int(hero["attrStr"]) == int(bonus.get("str", 0)),
		"str=%d (class %d)" % [int(hero["attrStr"]), int(bonus.get("str", 0))])
	_check("attrVit from the class", int(hero["attrVit"]) == int(bonus.get("vit", 0)),
		"vit=%d (class %d)" % [int(hero["attrVit"]), int(bonus.get("vit", 0))])
	_check("attrInt from the class", int(hero["attrInt"]) == int(bonus.get("int", 0)),
		"int=%d (class %d)" % [int(hero["attrInt"]), int(bonus.get("int", 0))])

	# A pool that does not include VIT/INT is the bug: VIT*5 lands in max HP and INT*2
	# in max mana, so both must exceed the bare level-1 formula.
	var bare_hp := 30 + int(floor(float(hero["level"]) * 5.0))
	var bare_mana := int(cls.get("baseMana", 0))
	_check("max HP includes VIT*5", int(hero["maxHp"]) == bare_hp + int(hero["attrVit"]) * 5,
		"%d (bare %d + vit %d)" % [int(hero["maxHp"]), bare_hp, int(hero["attrVit"]) * 5])
	_check("max mana includes INT*2",
		int(hero["maxMana"]) == bare_mana + int(hero["attrInt"]) * 2,
		"%d (base %d + int %d)" % [int(hero["maxMana"]), bare_mana, int(hero["attrInt"]) * 2])
	_check("pools start full",
		int(hero["hp"]) == int(hero["maxHp"]) and int(hero["mana"]) == int(hero["maxMana"]),
		"hp %d/%d mana %d/%d" % [int(hero["hp"]), int(hero["maxHp"]),
			int(hero["mana"]), int(hero["maxMana"])])
	# The PWA's startWeapons map.
	_check("start weapon equipped", str(state.equip().get("weapon", "")) == "blade_shortSword",
		str(state.equip().get("weapon", "")))
	_check("class portrait set", str(hero["face"]) == "hero_barbarian_m", str(hero["face"]))

	print("== the duel arena's distance ==")
	# Reach and closing speed come off the weapon type, so drive the fight with the
	# short sword the class kit just equipped: blade -> reach 0.20, speed 0.62 + 0.35.
	var battle := Battle.new(data, 12345)
	battle.act_id = 0
	var setup_ok := battle.setup(state, find_item)
	_check("fight set up", setup_ok)
	battle.apply_swing_timers(state, find_item)
	_check("weapon type read off the equipped weapon", battle.weapon_type == "blade",
		battle.weapon_type)
	_check("reach is the blade's", is_equal_approx(battle.weapon_reach(), 0.20),
		str(battle.weapon_reach()))
	_check("a fight starts at maximum separation", is_equal_approx(battle.gap, 1.0),
		str(battle.gap))
	_check("out of reach at the start", not battle.player_in_reach())

	# Walk in on the rule's own clock and find the tick the hero first gets in reach.
	# blade: 0.62 + 0.35 = 0.97 gap/s, so reach 0.20 is ~825 ms. The PWA measured
	# 624-1024 ms across weapons; assert the BAND rather than one number.
	var ms_to_reach := -1
	var t := 0
	while t < 3000:
		battle.advance_gap(100.0)
		t += 100
		if battle.player_in_reach():
			ms_to_reach = t
			break
	_check("in reach within the PWA's band (624-1024 ms)", ms_to_reach >= 624 and ms_to_reach <= 1024,
		"%d ms" % ms_to_reach)

	# And a swing that lands must still do damage — the control for the gate above. Ten
	# tries, because an even fight is 50 % to hit and a single swing proves nothing.
	var walker := Battle.new(data, 999)
	walker.act_id = 0
	walker.setup(state, find_item)
	walker.apply_swing_timers(state, find_item)
	var enemy_hp_before := walker.enemy_hp
	for _i in 10:
		walker.player_attack(state, find_item)
	var direct_damage := enemy_hp_before - walker.enemy_hp
	_check("a swing that lands does damage (control)", direct_damage > 0.0,
		"%.0f over 10 swings" % direct_damage)

	# The gate itself, at the RULE level. A realistic fight is a weak probe here: the
	# blade's first swing boundary (1360 ms) comes AFTER the hero is already in reach
	# (~1030 ms), so the gate never fires and an ungated port passes the test. Drive a
	# swing boundary while still out of reach instead, and assert nothing is damaged.
	var gated := Battle.new(data, 4242)
	gated.act_id = 0
	gated.setup(state, find_item)
	gated.apply_swing_timers(state, find_item)
	gated.gap = 0.9                       # out of reach for every weapon in the game
	var hp_before_gate := gated.enemy_hp
	gated.player_swing_elapsed = float(gated.player_swing_ms) + 1.0
	gated.tick(100.0, state, find_item)
	_check("a swing out of reach is discarded, not landed",
		gated.enemy_hp >= hp_before_gate,
		"enemy %.0f -> %.0f (gap %.2f, reach %.2f)" % [hp_before_gate, gated.enemy_hp,
			gated.gap, gated.weapon_reach()])
	_check("the discarded swing restarts the clock", gated.player_swing_elapsed < 200.0,
		"%.0f ms into a %d ms swing" % [gated.player_swing_elapsed, gated.player_swing_ms])

	# ...and in contact the same swing DOES land, so the gate is a gate and not a wall.
	gated.gap = 0.0
	var hp_before_hit := gated.enemy_hp
	for _i in 10:
		gated.player_swing_elapsed = float(gated.player_swing_ms) + 1.0
		gated.gap = 0.0
		gated.tick(100.0, state, find_item)
		if gated.ended:
			break
	_check("in contact the swing lands", gated.enemy_hp < hp_before_hit,
		"enemy %.0f -> %.0f" % [hp_before_hit, gated.enemy_hp])

	# The enemy's half of the same rule: a melee monster cannot hit from across the arena.
	var enemy_gated := Battle.new(data, 31337)
	enemy_gated.act_id = 0
	enemy_gated.setup(state, find_item)
	enemy_gated.apply_swing_timers(state, find_item)
	if enemy_gated.enemy_attack_type != "caster":
		enemy_gated.gap = 0.9
		var hero_hp_before := enemy_gated.hero_hp
		enemy_gated.enemy_swing_elapsed = float(enemy_gated.enemy_swing_ms) + 1.0
		enemy_gated.tick(100.0, state, find_item)
		_check("a melee monster hits nothing from across the arena",
			enemy_gated.hero_hp >= hero_hp_before,
			"hero %.0f -> %.0f" % [hero_hp_before, enemy_gated.hero_hp])
	else:
		_check("a caster reaches the hero from any distance", enemy_gated.enemy_in_reach(),
			enemy_gated.enemy_attack_type)

	# A boss keeps the PWA's old geometry — always in reach.
	var boss := Battle.new(data, 5)
	boss.act_id = 0
	boss.setup(state, find_item)
	boss.is_boss = true
	_check("a boss is always in reach", boss.enemy_in_reach())

	# Mana regen: the port ticks it, so it must actually rise — a regen nobody ticks is
	# the "no mana" half of the report.
	hero["mana"] = 0
	var regen := Battle.new(data, 11)
	regen.act_id = 0
	regen.setup(state, find_item)
	regen.apply_swing_timers(state, find_item)
	for _i in 60:
		regen.tick(100.0, state, find_item)
		if regen.ended:
			break
	_check("hero mana regenerates during a fight", int(hero["mana"]) > 0,
		"mana %d/%d after 6 s" % [int(hero["mana"]), int(hero["maxMana"])])

	_test_renderer_walks_the_hero_in(data, state, find_item)

	# The verdict string is what the CI gate greps for, and it must match EVERY other
	# test's shape: `SCREAMING_SNAKE_ALL_PASS=true`, derived from the GATE's name, not
	# from this file's name. It used to print `test_duel_distance_ALL_PASS=...` while CI
	# grepped `DUEL_DISTANCE_ALL_PASS=true` — the test passed, the grep did not find it,
	# `set -e` failed the step, and the whole export was skipped.
	print("DUEL_DISTANCE_ALL_PASS=%s" % str(_ok))
	quit(0 if _ok else 1)


## The screen does not just READ `_gap`, it has to turn it into pixels, and that half is
## invisible to every rules test above. Two things go wrong here in a way that looks like
## working code:
##
##   - the hero is placed from a size that is still zero (the screen had not run a layout
##     pass yet), so the walk-in renders as nothing at all,
##   - the hero keeps the CONTACT position for the whole approach — the PWA's own comment
##     about the two figures merging ("hlava by se slila s hlavou nepřítele") is exactly
##     what a permanently-near hero reproduces.
##
## Driven through `_place_hero` rather than through the battle, because that is the seam
## between the rule and the pixels: it is the one function the renderer has, and it takes
## only the lunge lift.
func _test_renderer_walks_the_hero_in(data, state, find_item: Callable) -> void:
	print("== the renderer's half of the walk-in ==")
	var screen = ArenaScreen.new(data, ItemGen.new(data), LootSystem.new(data, ItemGen.new(data)),
		state, func(id): return data.item(str(id)) if id != null else {})
	screen._build()
	screen.size = Vector2(390, 844)
	screen._arena.size = Vector2(390, 708)
	var arena_h: float = screen._arena.size.y

	# Far away: the PWA's start position and its smallest scale.
	screen.battle = null
	screen._place_hero(0.0)
	var far_pos: Vector2 = screen._hero_sprite.position
	var far_size: float = screen._hero_sprite.size.x
	_check("at the start the hero is centred and small",
		is_equal_approx(far_pos.x, round(390.0 * 0.50 - far_size * 0.5)),
		"x=%.0f size=%.0f" % [far_pos.x, far_size])

	# At contact: beside the monster, full size.
	var battle := Battle.new(data, 7)
	battle.act_id = 0
	battle.setup(state, find_item)
	battle.gap = 0.0
	screen.battle = battle
	screen._place_hero(0.0)
	var near_pos: Vector2 = screen._hero_sprite.position
	var near_size: float = screen._hero_sprite.size.x
	_check("at contact the hero stands beside the monster",
		near_pos.x < far_pos.x, "start x=%.0f -> contact x=%.0f" % [far_pos.x, near_pos.x])
	_check("and he is bigger than at maximum separation", near_size > far_size,
		"%.0f -> %.0f" % [far_size, near_size])

	# The position has to MOVE with _gap. Sample the approach and require a monotone
	# leftward walk with a strictly larger size at the end: a renderer that ignores `_gap`
	# passes the two endpoint checks above only if it happens to sit at one of them.
	var xs: Array[float] = []
	var sizes: Array[float] = []
	for gap_step in [1.0, 0.75, 0.5, 0.25, 0.0]:
		battle.gap = gap_step
		screen._place_hero(0.0)
		xs.append(screen._hero_sprite.position.x)
		sizes.append(screen._hero_sprite.size.x)
	var monotone := true
	for i in range(1, xs.size()):
		if xs[i] >= xs[i - 1] or sizes[i] < sizes[i - 1]:
			monotone = false
	_check("every step of the approach moves him left and closer", monotone,
		"x %s / size %s" % [str(xs), str(sizes)])
	if not monotone:
		_check("the renderer does not follow _gap", false,
			"x %s / size %s" % [str(xs), str(sizes)])

	# The monster's lean is part of the same walk-in, and a boss must NOT lean: the PWA
	# gates it on `!mb.isBoss`, so an untilted boss is the correct behaviour, not a bug.
	#
	# `_animate` takes real time now, so it is driven with a long enough delta that the
	# decay cannot eat the freshly set lunge — a decayed lunge would make the tilt read as
	# 0 px against an expected 8 and fail for a reason that has nothing to do with the boss.
	battle.is_boss = false
	screen._monster_lunge = 0.0
	screen._animate(0.016)
	var tilt_normal: float = screen._portrait.position.y - (arena_h * 0.5 - 180.0 * 0.5)
	battle.is_boss = true
	screen._monster_lunge = 0.0
	screen._animate(0.016)
	var tilt_boss: float = screen._portrait.position.y - (arena_h * 0.5 - 180.0 * 0.5)
	_check("the monster leans in at contact, and a boss does not",
		is_equal_approx(tilt_normal, screen.MONSTER_TILT_MAX) and is_equal_approx(tilt_boss, 0.0),
		"normal %.0f px, boss %.0f px" % [tilt_normal, tilt_boss])
