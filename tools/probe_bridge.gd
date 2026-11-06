extends SceneTree
## Why does a zone with `has_bridge=true` have no deck? Print the cells around the bridge and the
## result of the flood fill, so the answer is measured instead of guessed.
##
##   godot4 --headless --path . --script res://tools/probe_bridge.gd -- --zone 4 --seed 21

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
		if str(raw[i]).begins_with("--"):
			var body := str(raw[i]).substr(2)
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
		int(args.get("seed", "21")), int(args.get("zone", "4")))
	print("entry_side=%d feature=%s zone=%d act=%d" % [r.entry_side, str(r.feature), r.zone_index, r.act_id])
	print("planned=%s has_bridge=%s span=%d mid=%s near=%s far=%s"
		% [str(r.river_planned), str(r.has_bridge), r.bridge_span, str(r.bridge_mid),
			str(r.bridge_near), str(r.bridge_far)])
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for v in r.cell_kind:
		counts[int(v)] = int(counts[int(v)]) + 1
	print("kinds rock=%d ground=%d water=%d deck=%d"
		% [counts[0], counts[1], counts[2], counts[3]])
	var mid: Vector2i = r.cell_of(r.bridge_mid)
	print("bridge cell %s kind=%d" % [str(mid), r.cell_kind_at(mid.x, mid.y)])
	for dy in range(-3, 4):
		var row := ""
		for dx in range(-6, 7):
			var k: int = r.cell_kind_at(mid.x + dx, mid.y + dy)
			row += match_char(k)
		print("  %s  %s" % [str(mid.y + dy).pad_zeros(2), row])
	var start: Vector2i = r.cell_of(r.start_point)
	var exit_c: Vector2i = r.cell_of(r.exit_point)
	print("start %s kind=%d  exit %s kind=%d"
		% [str(start), r.cell_kind_at(start.x, start.y),
			str(exit_c), r.cell_kind_at(exit_c.x, exit_c.y)])
	# Is the far bank reachable from the start?
	var seen := {}
	var stack: Array = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= r.COLS or n.y >= r.ROWS:
				continue
			if seen.has(n):
				continue
			var k: int = r.cell_kind_at(n.x, n.y)
			if k != 1 and k != 3:
				continue
			seen[n] = true
			stack.append(n)
	print("reachable floor from start: %d cells; exit reached=%s"
		% [seen.size(), str(seen.has(exit_c))])
	quit(0)


func match_char(k: int) -> String:
	match k:
		0:
			return "#"
		1:
			return "."
		2:
			return "~"
		3:
			return "="
	return "?"
