extends SceneTree
## LookZoneMap — draw ONE zone's generated map as a PNG and print its terrain numbers.
##
## Why this exists: the survivor screen draws the area in `_draw()` and the camera shows ~8 cells,
## so neither a headless test nor a phone screenshot can answer "is the valley DIVIDED by a river?".
## A zone is 41 x 99 cells; this writes the whole thing in one frame, cell by cell.
##
##   godot4 --path . --headless --script res://tools/look_zone_map.gd -- \
##       --zone 4 --seed 7 --out /tmp/zone4.png [--act 0] [--scale 10] [--seeds 1,7,42]
##
## Colours: rock #1b1a18, ground #6e7a55, water #3c6f86, deck #8a6a3c, path dots #d9d2c0,
## packs #b03b2e, start #f0e6c0, exit #f0d060.
##
## It also reports the numbers a river is judged by — water cells, deck cells, how many separate
## crossings the walk makes, the thickness of the water along the path at the crossing, and the
## packs that stand within 3 cells of a bridge end.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

const COL_ROCK := Color(0.106, 0.102, 0.094)
const COL_GROUND := Color(0.431, 0.478, 0.333)
const COL_WATER := Color(0.235, 0.435, 0.525)
const COL_DECK := Color(0.541, 0.416, 0.235)
const COL_PATH := Color(0.851, 0.824, 0.753)
const COL_PACK := Color(0.690, 0.231, 0.180)
const COL_START := Color(0.941, 0.902, 0.753)
const COL_EXIT := Color(0.941, 0.816, 0.376)

var _data: Node
var _gen: ItemGen
var _loot: LootSystem


func _initialize() -> void:
	var args := _parse_args()
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	var zone := int(args.get("zone", "4"))
	var act := int(args.get("act", "0"))
	var scale := int(args.get("scale", "10"))
	var seeds: Array = str(args.get("seeds", "")).split(",", false)
	if seeds.is_empty():
		seeds = [int(args.get("seed", "7"))]
	for s in seeds:
		var seed_value := int(s)
		var run = _build(act, zone, seed_value)
		var out := str(args.get("out", "/tmp/zone.png"))
		if seeds.size() > 1:
			out = out.get_basename() + "_%d.png" % seed_value
		_dump(run, out, scale, act, zone, seed_value)
	quit(0)


func _parse_args() -> Dictionary:
	var out := {}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		var s := str(argv[i])
		i += 1
		if not s.begins_with("--"):
			continue
		var body := s.substr(2)
		var eq := body.find("=")
		if eq >= 0:
			out[body.substr(0, eq)] = body.substr(eq + 1)
			continue
		# `--zone 4` as well as `--zone=4`: the shell passes them as separate arguments.
		if i < argv.size() and not str(argv[i]).begins_with("--"):
			out[body] = str(argv[i])
			i += 1
		else:
			out[body] = "1"
	return out


func _build(act: int, zone: int, seed_value: int):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = 20
	var r = SurvivorRun.new()
	r.setup(s, _resolve(s), _loot, act, seed_value, zone)
	return r


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _dump(run, out: String, scale: int, act: int, zone: int, seed_value: int) -> void:
	var cols: int = run.COLS
	var rows: int = run.ROWS
	var img := Image.create(cols * scale, rows * scale, false, Image.FORMAT_RGB8)
	img.fill(COL_ROCK)
	var water := 0
	var deck := 0
	for cy in rows:
		for cx in cols:
			var k: int = run.cell_kind_at(cx, cy)
			var c := COL_ROCK
			match k:
				SurvivorRun.KIND_GROUND:
					c = COL_GROUND
				SurvivorRun.KIND_WATER:
					c = COL_WATER
					water += 1
				SurvivorRun.KIND_DECK:
					c = COL_DECK
					deck += 1
			img.fill_rect(Rect2i(cx * scale, cy * scale, scale, scale), c)
	# The walked centreline as dots, so the river's relation to the path is visible.
	for p in run.path_points:
		var cp: Vector2i = run.cell_of(p)
		img.fill_rect(Rect2i(cp.x * scale + scale / 4, cp.y * scale + scale / 4,
			maxi(1, scale / 2), maxi(1, scale / 2)), COL_PATH)
	for z in run.zones:
		var zc: Vector2i = run.cell_of(z["centre"])
		img.fill_rect(Rect2i(zc.x * scale - scale, zc.y * scale - scale,
			scale * 2, scale * 2), COL_PACK)
	var sp: Vector2i = run.cell_of(run.start_point)
	img.fill_rect(Rect2i(sp.x * scale - scale, sp.y * scale - scale, scale * 2, scale * 2), COL_START)
	var ep: Vector2i = run.cell_of(run.exit_point)
	img.fill_rect(Rect2i(ep.x * scale - scale, ep.y * scale - scale, scale * 2, scale * 2), COL_EXIT)
	img.save_png(out)
	print("[zone] act %d zone %d seed %d -> %s" % [act, zone, seed_value, out])
	print("[zone] water=%d deck=%d packs=%d zone_name=%s"
		% [water, deck, run.zones.size(), str(run.zone_index)])
	for line in _crossing_report(run):
		print("  " + line)


## How many TIMES the walk crosses water, how thick the water is at the widest crossing, and
## which packs stand at a bridge end.
func _crossing_report(run) -> Array:
	var lines: Array = []
	var pts: Array = run.path_points
	var crossings := 0
	var widest := 0
	var in_water := false
	var thickness := 0
	var bridge_ends: Array = []
	var prev_wet := false
	for i in pts.size():
		var c: Vector2i = run.cell_of(pts[i])
		var wet: bool = run.is_water_cell(c.x, c.y)
		var on_deck: bool = run.is_deck_cell(c.x, c.y)
		if wet and not prev_wet:
			crossings += 1
			thickness = 0
			bridge_ends.append(pts[i])
		if wet:
			thickness += 1
			widest = maxi(widest, thickness)
		if on_deck and prev_wet:
			bridge_ends.append(pts[i])
		prev_wet = wet or (prev_wet and on_deck)
		if not wet and not on_deck:
			prev_wet = false
	lines.append("path crossings of WATER = %d (path points, not cells)" % crossings)
	lines.append("widest water run along the path = %d path points" % widest)
	for be in bridge_ends:
		var best := 1e9
		var kind := ""
		for z in run.zones:
			var d: float = (z["centre"] as Vector2).distance_to(be)
			if d < best:
				best = d
				kind = str(z["kind"])
		lines.append("bridge end at cell %s: nearest pack %.0f px away (%s)"
			% [str(run.cell_of(be)), best, kind])
	return lines
