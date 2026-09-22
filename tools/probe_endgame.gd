extends SceneTree
## tools/probe_endgame.gd — what really happens at the END of a fight.
##
## Jan's report: "the win and the loss do not work the way they should" (vedle "bezi
## extremne rychle"). Both are claims about the rules, so this prints the RULES' own
## counters after a real fight, and asserts nothing — a probe, not a test.
##
## The three things it measures, each a place the port has been wrong before:
##   1. a PACK fight — does killing one member end the fight, or does the next one step up
##      and the elite LEADER get its turn (the PWA's `packTryAdvance`)?
##   2. a LOSS — deaths counted once or twice, fight counter reset, consolation XP/gold,
##      and the HP the save is left with.
##   3. a WIN — fight counter, XP, gold, and where the hero's HP ends up.
##
## Run:  godot --headless --path . --script res://tools/probe_endgame.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")

var _data: Node
var _gen: ItemGen
var _state


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_probe_pack()
	_probe_loss()
	_probe_win()
	quit(0)


func _fresh(level: int, str_points: int, weapon: String) -> void:
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")
	_state.hero()["level"] = level
	_state.hero()["attrStr"] = str_points
	_state.equip()["weapon"] = weapon
	_state.hero()["maxHp"] = _gen.hero_max_hp(_state.hero(), _state.equip(), _resolve)
	_state.hero()["hp"] = _state.hero()["maxHp"]
	_state.data["locationProgress"][0] = 0


## A champion pack (fight 5/10) and an elite pack (fight 10/10): how many kills does one
## fight cost, and which member is the last one standing?
func _probe_pack() -> void:
	print("=== PACK ===")
	for fight in [4, 9]:
		_fresh(30, 145, "blade_shortSword")
		_state.data["areaFightProgress"][0] = fight
		var b := Battle.new(_data, 20240915)
		b.act_id = 0
		b.setup(_state, _resolve)
		b.apply_swing_timers(_state, _resolve)
		b.gap = 0.0
		var members := b.pack_size()
		var ticks := 0
		var names: Array = [b.enemy_name]
		var last_active := b.pack_active
		while not b.ended and ticks < 20000:
			b.tick(100.0, _state, _resolve)
			ticks += 1
			if b.pack_active != last_active:
				last_active = b.pack_active
				names.append(b.enemy_name)
			if b.pending_kill:
				b.tick(100.0, _state, _resolve)
				ticks += 1
				if b.pack_active != last_active:
					last_active = b.pack_active
					names.append(b.enemy_name)
		print("fight %d/10: pack members=%d  hand-overs=%d  ticks=%d  won=%s"
			% [fight + 1, members, names.size() - 1, ticks, str(b.won)])
		print("   sequence: %s" % str(names))
		print("   fight counter after: %d/10" % int(_state.data["areaFightProgress"][0]))


## Death, at the battle level (what `test_combat` can see) and through the SCREEN (where
## the port adds its own death bookkeeping on top).
func _probe_loss() -> void:
	print("=== LOSS (rules only) ===")
	_fresh(1, 0, "fists")
	_state.data["areaFightProgress"][0] = 6
	var b := Battle.new(_data, 31337)
	b.act_id = 0
	b.setup(_state, _resolve)
	b.apply_swing_timers(_state, _resolve)
	b.gap = 0.0
	b.hero_hp = 1.0
	b.hero_max_hp = 1.0
	var hero: Dictionary = _state.hero()
	var xp_before := int(hero["xp"])
	var gold_before := int(hero["gold"])
	var ticks := 0
	while not b.ended and ticks < 400:
		b.tick(100.0, _state, _resolve)
		ticks += 1
	print("ended=%s won=%s in %d ticks" % [str(b.ended), str(b.won), ticks])
	print("deaths=%d (expected 1 per death)" % int(_state.data["deaths"]))
	print("fight counter=%d (PWA resets it to 0 on death)"
		% int(_state.data["areaFightProgress"][0]))
	print("xp %d->%d  gold %d->%d (PWA gives consolation on a death)"
		% [xp_before, int(hero["xp"]), gold_before, int(hero["gold"])])
	print("hero hp in the save: %.0f / %.0f" % [float(hero["hp"]), float(hero["maxHp"])])


func _probe_win() -> void:
	print("=== WIN ===")
	_fresh(30, 145, "blade_shortSword")
	_state.data["areaFightProgress"][0] = 0
	var b := Battle.new(_data, 2024)
	b.act_id = 0
	b.setup(_state, _resolve)
	b.apply_swing_timers(_state, _resolve)
	b.gap = 0.0
	var hero: Dictionary = _state.hero()
	# A real fight: the hero is level 30 and armed, the enemy is left as spawned.
	var ticks := 0
	while not b.ended and ticks < 4000:
		b.tick(100.0, _state, _resolve)
		if b.pending_kill:
			b.tick(100.0, _state, _resolve)
		ticks += 1
	print("won=%s in %d ticks (%d ms of game time)" % [str(b.won), ticks, ticks * 100])
	print("fight counter=%d/10  wins=%d  xp=%d  gold=%d  hero hp=%.0f"
		% [int(_state.data["areaFightProgress"][0]), int(_state.data["wins"]),
			int(hero["xp"]), int(hero["gold"]), float(hero["hp"])])


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	if not static_item.is_empty():
		return static_item
	if _state != null:
		return _state.loot_item(item_id)
	return {}
