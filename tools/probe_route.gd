extends SceneTree
## Why is an assembled route shorter than drawn? Prints the drawn length, the route the assembler
## returns, and the gate chunks — the answer, not a guess.
##
##   godot4 --headless --path . --script res://tools/probe_route.gd -- --zone 0 --seed 1234

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")


func _initialize() -> void:
	var args := {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var a := str(raw[i])
		if a.begins_with("--"):
			var body := a.substr(2)
			var eq := body.find("=")
			if eq >= 0:
				args[body.substr(0, eq)] = body.substr(eq + 1)
			elif i + 1 < raw.size():
				args[body] = str(raw[i + 1])
				i += 1
			else:
				args[body] = "1"
		i += 1
	var data = GameData.new()
	root.add_child(data)
	var gen := ItemGen.new(data)
	var loot := LootSystem.new(data, gen)
	var st = GameState.new()
	st.bind_data(data)
	st.set_class("barbarian")
	st.hero()["level"] = 20
	var r = SurvivorRun.new()
	r.setup(st, func(id): return data.item(str(id)), loot, int(args.get("act", "0")),
		int(args.get("seed", "1234")), int(args.get("zone", "0")))
	var total := 0.0
	for k in range(1, r.path_points.size()):
		total += (r.path_points[k - 1] as Vector2).distance_to(r.path_points[k] as Vector2)
	print("points=%d total=%.0f px entry_side=%d exit_side=%d river=%s"
		% [r.path_points.size(), total, r.entry_side, r.exit_side, str(r.river_planned)])
	print("gate grid: entry=%s exit=%s  chunk grid=%dx%d"
		% [str(r._gate_chunk(r.entry_side)), str(r._gate_chunk(r.exit_side)), r.CHUNK_GX, r.CHUNK_GY])
	# Replay the route with the same rng state the build had is impossible (setup consumed it), so
	# this only shows what a fresh call produces.
	var route: Array = r._chunk_route(r._gate_chunk(r.entry_side), r._gate_chunk(r.exit_side))
	print("fresh _chunk_route size=%d" % route.size())
	quit(0)
