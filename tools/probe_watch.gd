extends SceneTree
## tools/probe_watch.gd — does the arena RENDER what it computed?
##
## `probe_fps_real.gd` showed the frame cost is ~4.3 ms (230 fps) and `probe_timing` showed
## a fixed step costs 0.1 ms, so neither the logic nor the renderer's workload explains a
## visibly slow swing. What is left is the THIRD possibility: the screen computes a smooth
## value every frame and then does not draw it — `render()` only runs on a 100 ms tick, so
## the rings, the bars and the walk-in move ten times a second regardless of the frame rate.
##
## This probe drives `_process` itself over a window of real frames and records, every frame,
## the exact numbers the player sees (the swing arc's ratio, the hero's position, the enemy
## HP ratio). A smooth screen is one whose numbers CHANGE EVERY FRAME; a screen that only
## moves on a tick shows a value that repeats ten frames in a row.
##
## Run:  godot --headless --path . --script res://tools/probe_watch.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

const FRAME_MS := 16.6667
const FRAMES := 120

var _data: Node
var _gen: ItemGen
var _state
var _screen


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	var loot := LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.load_from_disk()
	_state.set_class("barbarian")
	_screen = ArenaScreen.new(_data, _gen, loot, _state, _resolve)
	root.add_child(_screen)
	_screen._build()
	_screen.start(_state, _resolve)
	_screen.battle.enemy_max_hp = 1000000.0
	_screen.battle.enemy_hp = _screen.battle.enemy_max_hp
	_screen.battle.hero_max_hp = 1000000.0
	_screen.battle.hero_hp = _screen.battle.hero_max_hp
	_screen.battle.gap = 0.0
	# The arena needs a size for the hero placement; standalone it never gets one.
	_screen._arena.size = Vector2(390, 693)

	# `_process` is what a real frame calls. Feed it 60 Hz frames for two seconds and watch
	# the two values the eye reads as the swing.
	print("frame_ms=%.2f  frames=%d  player_swing_ms=%d" % [FRAME_MS, FRAMES,
		int(_screen.battle.player_swing_ms)])
	var changes_arc := 0
	var changes_hero := 0
	var prev_arc := -1.0
	var prev_hero := Vector2(-1, -1)
	var rows: Array[String] = []
	for i in FRAMES:
		_screen._process(FRAME_MS / 1000.0)
		var arc: float = _screen._arc_player.value
		var hero: Vector2 = _screen._hero_sprite.position
		if not is_equal_approx(arc, prev_arc):
			changes_arc += 1
		if hero != prev_hero:
			changes_hero += 1
		if i < 40 or (i % 10 == 0):
			rows.append("  f%3d arc=%.3f hero=(%.0f,%.0f) enemyHp=%.4f ticks=%d" % [
				i, arc, hero.x, hero.y,
				_screen.battle.enemy_hp / maxf(_screen.battle.enemy_max_hp, 1.0),
				int(_screen.battle.ticks_elapsed)])
		prev_arc = arc
		prev_hero = hero
	print("frames=%d  the swing arc CHANGED in %d of them  (smooth = %d)" % [
		FRAMES, changes_arc, FRAMES])
	print("hero position changed in %d of them" % changes_hero)
	for r in rows.slice(0, 24):
		print(r)
	quit(0)


func probe_size() -> Vector2:
	return _screen._arena.size


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	if not static_item.is_empty():
		return static_item
	return _state.loot_item(item_id)
