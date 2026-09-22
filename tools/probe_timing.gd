extends SceneTree
## tools/probe_timing.gd — a parity probe for the DUEL'S PACE.
##
## Jan's report: "the fight runs extremely fast and does not respect the weapon speeds".
## That is a claim about TIME, so this prints time: the swing interval the rules settled,
## the gap between the hits that actually landed, and how long one arena frame costs.
##
## Both halves are printed side by side, because the port has two clocks and only one of
## them can be wrong:
##
##   * battle.gd's clock — a fixed 100 ms step.
##   * the SCREEN's frame — `_process(delta)` accumulates REAL time and runs as many fixed
##     steps as elapsed. This was the bug: it used to pump exactly ONE 100 ms tick per
##     frame and ignore `delta`, so the frame rate (not the clock) decided the pace and the
##     fight ran ~6x fast. The measurement below is what caught it; keep it as the
##     standing check that the two clocks still agree.
##
## Run:  godot --headless --path . --script res://tools/probe_timing.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const Progression := preload("res://scripts/combat/progression.gd")

var _data: Node
var _gen: ItemGen
var _state


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")
	_state.hero()["level"] = 30
	_state.hero()["attrStr"] = 145
	_state.hero()["maxHp"] = _gen.hero_max_hp(_state.hero(), _state.equip(), _resolve)
	_state.hero()["hp"] = _state.hero()["maxHp"]
	_state.data["locationProgress"][0] = 0
	_state.data["areaFightProgress"][0] = 0

	var weapon: Dictionary = _data.item("blade_shortSword")
	print("weapon %s swingMs=%d" % [str(weapon.get("id")), int(weapon.get("swingMs", 0))])

	var b := Battle.new(_data, 4242)
	b.act_id = 0
	b.setup(_state, _resolve)
	b.apply_swing_timers(_state, _resolve)
	b.gap = 0.0
	# An unemptyable pool: this measures the PACE, not who wins.
	b.enemy_max_hp = 1000000.0
	b.enemy_hp = b.enemy_max_hp
	print("player_swing_ms=%d  enemy_swing_ms=%d  (battle's own rules)" % [b.player_swing_ms, b.enemy_swing_ms])

	# The hero's swing clock, sampled every tick: the gap between two landed swings IS
	# the interval the fight really uses.
	var hits: Array = []
	for i in 2000:
		var before := b.log.size()
		b.tick(100.0, _state, _resolve)
		for j in range(before, b.log.size()):
			var e: Dictionary = b.log[j]
			if str(e.get("kind", "")).begins_with("HIT") or str(e.get("kind", "")) == "CRIT":
				hits.append(i * 100)
		if b.ended:
			break
	print("landed hits in %d ticks: %d" % [2000, hits.size()])
	if hits.size() > 3:
		var deltas: Array = []
		for k in range(1, hits.size()):
			deltas.append(int(hits[k]) - int(hits[k - 1]))
		print("gap between landed hits: %s" % str(deltas.slice(0, 12)))
		var sum := 0
		for d in deltas:
			sum += int(d)
		print("mean interval between landed hits: %.0f ms over %d swings" % [float(sum) / float(deltas.size()), deltas.size()])

	# The screen's frame cost, now that the screen owns the clock. `_process` turns real time
	# into whole fixed steps (`MAX_STEPS_PER_FRAME` of them at most), so what matters is that
	# a frame's own cost stays far below one step: a frame that costs more than TICK_MS
	# cannot keep up with the clock at all.
	_measure_frame()

	quit(0)


## What the arena screen costs per frame: the tick, and the render it triggers. Measured
## HERE as separate pieces so a slow sub-step cannot hide inside the total.
func _measure_frame() -> void:
	var b := Battle.new(_data, 777)
	b.act_id = 0
	b.setup(_state, _resolve)
	b.apply_swing_timers(_state, _resolve)
	b.gap = 0.0
	b.enemy_max_hp = 1000000.0
	b.enemy_hp = b.enemy_max_hp

	var t0 := Time.get_ticks_usec()
	for _i in 300:
		b.tick(100.0, _state, _resolve)
	var tick_us := Time.get_ticks_usec() - t0
	print("battle.tick x300: %d us total (%.2f ms each)" % [tick_us, float(tick_us) / 300000.0])

	var t1 := Time.get_ticks_usec()
	for _i in 300:
		b.spell_bar(_state, _resolve)
	var bar_us := Time.get_ticks_usec() - t1
	print("battle.spell_bar x300: %d us total (%.2f ms each)" % [bar_us, float(bar_us) / 300000.0])

	var t2 := Time.get_ticks_usec()
	for _i in 300:
		_gen.hero_max_hp(_state.hero(), _state.equip(), _resolve)
	var hp_us := Time.get_ticks_usec() - t2
	print("ItemGen.hero_max_hp x300: %d us total (%.2f ms each)" % [hp_us, float(hp_us) / 300000.0])


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	if not static_item.is_empty():
		return static_item
	return _state.loot_item(item_id)
