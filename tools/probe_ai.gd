extends SceneTree
## Why does a monster not move? One body, one step, printed: where it stands, whether that spot is
## walkable, whether it can see the hero, what the flow field says, and what `_step_body` returns.
##
##   godot4 --headless --path . --script res://tools/probe_ai.gd -- --zone 0 --seed 7

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
		int(args.get("seed", "7")), int(args.get("zone", "0")))
	r._spawn_one()
	if r.monsters.is_empty():
		print("no monster spawned")
		quit(0)
		return
	var m: Dictionary = r.monsters[0]
	var mp: Vector2 = m["pos"]
	print("hero=%s  monster=%s  gap=%.1f  speed=%.1f ranged=%s keep=%.1f"
		% [str(r.player_pos), str(mp), mp.distance_to(r.player_pos), float(m["speed"]),
			str(m["ranged"]), float(m["keep_range"])])
	print("walkable(monster)=%s walkable(hero)=%s line_clear=%s"
		% [str(r.walkable(mp, r.MON_RADIUS)), str(r.walkable(r.player_pos, r.MON_RADIUS)),
			str(r._line_clear(mp, r.player_pos))])
	r._flow_field()
	print("flow_dir=%s  flow_here=%d" % [str(r._flow_dir(mp)),
		r._flow_dist[r.cell_index(r.cell_of(mp).x, r.cell_of(mp).y)]])
	var dir: Vector2 = (r.player_pos - mp).normalized()
	print("step_body(full)=%s" % str(r._step_body(mp, dir * 2.0, r.MON_RADIUS)))
	print("step_body(x)=%s" % str(r._step_body(mp, Vector2(dir.x * 2.0, 0.0), r.MON_RADIUS)))
	print("step_body(y)=%s" % str(r._step_body(mp, Vector2(0.0, dir.y * 2.0), r.MON_RADIUS)))
	for _i in 60:
		r.step(1.0 / 60.0, Vector2.ZERO)
	print("after 60 steps: gap=%.1f  hp=%d finished=%s"
		% [r.monsters[0]["pos"].distance_to(r.player_pos), r.hp, str(r.finished)])
	var c: Vector2i = r.cell_of(mp)
	for dy in range(-4, 5):
		var row := ""
		for dx in range(-4, 5):
			row += "." if r.is_floor_cell(c.x + dx, c.y + dy) else "#"
		print("  %s" % row)
	quit(0)
