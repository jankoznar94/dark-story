extends SceneTree
## tools/probe_wheel.gd — does holding the ACTION WHEEL's attack sector actually make the hero
## swing? The capture tool (`look_survivor.gd`) hangs on `--wait_swing` when it does not, and a
## hanging capture says nothing about WHY, so this prints the state every 20 frames.
##
##   godot4 --headless --path . --script res://tools/probe_wheel.gd

const GameData := preload("res://scripts/data/game_data.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorScreen := preload("res://scripts/ui/survivor_screen.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

var _data: Node


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	var gen := ItemGen.new(_data)
	var loot := LootSystem.new(_data, gen)
	var state = GameState.new()
	state.bind_data(_data)
	state.reset()
	state.set_class("barbarian")

	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(state, Callable(self, "_find_item"), loot, 0)

	var run = screen.run
	run.monsters.clear()
	for i in 5:
		run._spawn_one()
		var ang := TAU * float(i) / 5.0 + 0.4
		run.monsters[i]["pos"] = run.player_pos + Vector2(cos(ang), sin(ang)) * 105.0

	# The wheel, pushed UP past the ring: the sector the default binds to ATTACK.
	screen._on_press(Vector2(96, 630), 7)
	screen._on_drag(Vector2(96, 630 - SurvivorScreen.WHEEL_ACTIVATE - 10.0), 7)
	print("wheel: slot=%d action='%s' attack_held=%s" % [
		screen._wheel_slot, screen.wheel_action(screen._wheel_slot), str(run.attack_held)])

	for f in 320:
		screen._process(1.0 / 60.0)
		if f % 20 == 0:
			var closest := 1e9
			for m in run.monsters:
				closest = minf(closest, (m["pos"] as Vector2).distance_to(run.player_pos))
			print("f=%3d t=%.1f held=%s target=%d alive=%d closest=%.0f reach=%.0f swing=%.2f hp=%d" % [
				f, run.elapsed, str(run.attack_held), int(run.target_id), run.monsters.size(),
				closest, run.reach_main + SurvivorRun.MON_RADIUS, float(run.swing_age), run.hp])
	quit()


func _find_item(id: Variant) -> Dictionary:
	if id == null:
		return {}
	var s := str(id)
	if s == "":
		return {}
	var item: Dictionary = _data.item(s)
	return item
