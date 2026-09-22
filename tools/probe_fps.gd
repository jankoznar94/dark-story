extends SceneTree
## tools/probe_fps.gd — how long ONE rendered frame of the arena really costs.
##
## Jan's report: "the whole port runs as if it were 5 FPS; the swing animation is not
## smooth at all". That is a claim about FRAME TIME, so this measures frame time — in the
## real main loop, with the real layout, on a real fight.
##
## Run headless (the logic half) and with `--rendering-driver opengl3` (the drawing half):
##
##   godot --headless                     --path . --script res://tools/probe_fps.gd
##   godot --rendering-driver opengl3     --path . --script res://tools/probe_fps.gd
##
## Every frame's wall time is kept, so the report can be read as a distribution: a single
## slow frame is a hitch, a slow MEDIAN is a frame rate.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

const FRAMES := 240

var _data: Node
var _gen: ItemGen
var _state
var _screen
var _frames: Array[float] = []
var _last_usec := 0
var _drawn_usec := 0


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	var loot := LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	# Jan's own save, when there is one — the port must be measured on a real hero and a
	# real zone (level 1 with bare fists is a different fight and a different frame).
	var resumed: bool = _state.load_from_disk()
	_state.set_class("barbarian")
	if not resumed:
		_state.set_class("barbarian")
	print("save loaded=%s  hero level=%d  class=%s" % [str(resumed),
		int(_state.hero().get("level", 1)), str(_state.data.get("heroClass", ""))])

	_screen = ArenaScreen.new(_data, _gen, loot, _state, _resolve)
	root.add_child(_screen)
	_screen._build()
	var ok: bool = _screen.start(_state, _resolve)
	print("fight started=%s" % str(ok))
	# A fight that cannot end: this measures the frame, not the outcome.
	_screen.battle.enemy_max_hp = 1000000.0
	_screen.battle.enemy_hp = 1000000.0
	_screen.battle.hero_max_hp = 1000000.0
	_screen.battle.hero_hp = 1000000.0
	_screen.battle.gap = 0.0
	var monitor := _Monitor.new()
	monitor.probe = self
	root.add_child(monitor)


func frame_done() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	_frames.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	if _frames.size() >= FRAMES:
		_report()
		quit(0)


func _report() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	var mid: float = sorted[sorted.size() / 2]
	var p95: float = sorted[int(float(sorted.size()) * 0.95)]
	print("frames=%d  median=%.2f ms  mean=%.2f ms  p95=%.2f ms  worst=%.2f ms" % [
		_frames.size(), mid, total / float(_frames.size()), p95, sorted[sorted.size() - 1]])
	print("median frame rate=%.1f fps   (60 fps needs 16.7 ms, 5 fps is 200 ms)" % (1000.0 / maxf(mid, 0.001)))
	print("arena size=%s  battle ticks=%d" % [str(_screen._arena.size),
		int(_screen.battle.ticks_elapsed)])


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	if not static_item.is_empty():
		return static_item
	return _state.loot_item(item_id)


class _Monitor:
	extends Node
	var probe


	func _process(_delta: float) -> void:
		probe.frame_done()
