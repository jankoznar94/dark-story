extends SceneTree
## tools/probe_fps_real.gd — the arena's FRAME TIME, measured the way Jan plays it.
##
## `probe_fps.gd` builds an arena standalone and measured 145 fps headless, which proved
## the arena's own workload is small. It did NOT prove the game is smooth: it missed the
## screen the player is looking at, the real canvas (390x844) and the real renderer.
##
## So this probe boots the REAL main.gd, taps through the REAL route to a fight — the map's
## stop selection, i.e. `main._on_stop_selected(act, 0)`, which is what a tap does — and
## then times every frame of the real loop for a few hundred frames. Two numbers come out:
##
##   * the LOGIC frame: how long the whole tree's `_process`/`_draw` costs, and
##   * the WALL frame: what the compositor actually delivered, because that is the number
##     the eye reads as smoothness.
##
## Run:  godot --rendering-driver opengl3 --path . --script res://tools/probe_fps_real.gd

const FRAMES := 300

var _main: Node = null
var _started := false
var _frames: Array[float] = []
var _wall: Array[float] = []
var _last_usec := 0
var _arc_moves := 0
var _arc_samples := 0
var _hero_moves := 0
var _prev_arc := -1.0
var _prev_hero := Vector2(-1, -1)


func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		var state = _main.state
		if not bool(state.data.get("_hasSave", false)):
			pass
		# The real route a tap takes: a stop on the map. This is `_on_stop_selected`, so
		# `_enter_arena` -> `arena.start()` runs exactly as it does in play.
		var act := 0
		_main._on_stop_selected(act, 0)
		print("screen=%s  arena visible=%s  battle=%s  hero level=%d" % [
			_main._current,
			str(_main._screens["arena"].visible),
			str(_main._screens["arena"].battle != null),
			int(state.hero().get("level", 1))])
		var arena = _main._screens["arena"]
		if arena.battle != null:
			arena.battle.enemy_max_hp = 1000000.0
			arena.battle.enemy_hp = arena.battle.enemy_max_hp
			arena.battle.hero_max_hp = 1000000.0
			arena.battle.hero_hp = arena.battle.hero_max_hp
			arena.battle.gap = 0.0
		return false

	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_wall.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	_frames.append(_delta * 1000.0)
	sample()

	if _frames.size() >= FRAMES:
		_report()
		quit(0)
	return false


func _report() -> void:
	var arena = _main._screens["arena"]
	print("arena size=%s  ticks=%d  visible=%s" % [str(arena._arena.size),
		int(arena.battle.ticks_elapsed), str(arena.visible)])
	print("motion: the swing arc changed in %d of %d frames; the hero moved in %d" % [
		_arc_moves, _arc_samples, _hero_moves])
	_line("engine delta (logic frame)", _frames)
	_line("wall clock between frames", _wall)


## Counted inside the REAL loop, so this is what the player's eye gets — not a harness that
## supplies its own clock.
func sample() -> void:
	if _main == null or not _main._screens.has("arena"):
		return
	var arena = _main._screens["arena"]
	if arena.battle == null:
		return
	var arc: float = arena._arc_player.value
	var hero: Vector2 = arena._hero_sprite.position
	if _arc_samples > 0:
		if not is_equal_approx(arc, _prev_arc):
			_arc_moves += 1
		if hero != _prev_hero:
			_hero_moves += 1
	_arc_samples += 1
	_prev_arc = arc
	_prev_hero = hero


func _line(name: String, arr: Array) -> void:
	if arr.is_empty():
		return
	var sorted := arr.duplicate()
	sorted.sort()
	var total := 0.0
	for v in arr:
		total += float(v)
	var mid: float = sorted[sorted.size() / 2]
	var p95: float = sorted[int(float(sorted.size()) * 0.95)]
	var p99: float = sorted[int(float(sorted.size()) * 0.99)]
	print("%s: median=%.2f ms  mean=%.2f ms  p95=%.2f  p99=%.2f  worst=%.2f  -> %.1f fps" % [
		name, mid, total / float(arr.size()), p95, p99, sorted[sorted.size() - 1],
		1000.0 / maxf(mid, 0.001)])
