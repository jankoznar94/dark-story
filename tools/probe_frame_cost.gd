extends SceneTree
## What does one frame COST in a real fight, and where do the long ones fall?
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/probe_frame_cost.gd -- --frames=900
##
## Boots the real `main`, walks the real route into the arena (`_on_stop_selected`) and then
## records EVERY frame's wall-clock delta. The report is a TAIL, not a median: an average
## frame time hides exactly the hitch the player feels. Long frames are printed with their
## index so a RHYTHM is visible, and the engine's own monitor breakdown says which part of
## the frame it was (process / physics / idle draw).

const MAX_WAIT_FRAMES := 4000

var _main: Node = null
var _started := false
var _frames := 0
var _battle_frame := -1
var _limit := 900
var _mode := "arena"
## Which ZONE of act 1 to measure. The valley (4) carries the bridge, its masonry and its two
## guard packs, so the cost of a zone is not one number — measure the zone you are asking about.
var _zone := -1
## Stand on the terrain FEATURE (the valley's bridge) instead of in the start clearing. The cost of
## a zone is not one number: the river puts a hundred water cells in frame, and that is exactly the
## frame this probe has to be able to photograph.
var _spot_feature := false
var _last_usec := 0
var _deltas: Array = []
var _long: Array = []
var _scaled := 0
var _proc_ms := 0.0
var _draw_ms := 0.0
var _phys_ms := 0.0
var _isolate := false
var _script_ms := 0.0
var _script_max := 0.0
var _script_over4 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_limit = int(a.split("=")[1])
		if a == "--isolate":
			_isolate = true
		if a.begins_with("--mode="):
			_mode = a.split("=")[1]
		if a.begins_with("--zone="):
			_zone = int(a.split("=")[1])
		if a == "--spot=feature":
			_spot_feature = true
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _started:
		if _main._nav_bar == null:
			return false
		print("PROBE entering %s (zone %d) at frame %d" % [_mode, _zone, _frames])
		if _mode == "survivor":
			_main._enter_survivor(0, _zone)
		else:
			_main._enter_arena(0)
		_started = true
		if _spot_feature and _mode == "survivor":
			var sc = _main._screens.get("survivor")
			if sc != null and sc.run != null and sc.run.has_bridge:
				sc.run.player_pos = sc.run.bridge_mid
		_last_usec = Time.get_ticks_usec()
		return false

	var arena = _main._screens.get("survivor" if _mode == "survivor" else "arena")
	if arena == null:
		if _frames > MAX_WAIT_FRAMES:
			print("PROBE no arena screen after %d frames" % _frames)
			return true
		return false
	if arena.battle == null if _mode == "arena" else arena.run == null:
		if _frames > MAX_WAIT_FRAMES:
			print("PROBE battle never started after %d frames" % _frames)
			return true
		_last_usec = Time.get_ticks_usec()
		return false

	if _battle_frame < 0:
		print("PROBE battle started at frame %d" % _frames)
		_battle_frame = 0
		_last_usec = Time.get_ticks_usec()
		if _isolate:
			arena.set_process(false)

	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	if _isolate:
		var t0 := Time.get_ticks_usec()
		arena._process(dt_ms / 1000.0)
		var cost := float(Time.get_ticks_usec() - t0) / 1000.0
		_script_ms += cost
		if cost > _script_max:
			_script_max = cost
		if cost > 4.0:
			_script_over4 += 1
	if _battle_frame > 0:
		_deltas.append(dt_ms)
		_proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_draw_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_phys_ms += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		if dt_ms > 20.0 and _long.size() < 200:
			_long.append({"i": _deltas.size(), "ms": snappedf(dt_ms, 0.1),
				"scale": snappedf(Engine.time_scale, 0.001)})
		if Engine.time_scale < 0.99:
			_scaled += 1
	_battle_frame += 1
	if _deltas.size() >= _limit:
		_report(arena)
		return true
	return false


func _count_floor(run) -> int:
	var out := 0
	for v in run.floor_cells:
		if int(v) == 1:
			out += 1
	return out


func _report(arena) -> void:
	var n := _deltas.size()
	var sorted := _deltas.duplicate()
	sorted.sort()
	var total_ms := 0.0
	for d in _deltas:
		total_ms += d
	var over20 := 0
	var over33 := 0
	for d in _deltas:
		if d > 20.0: over20 += 1
		if d > 33.4: over33 += 1
	print("FRAME_COST frames=%d wall=%.2fs avg=%.2fms median=%.2fms p95=%.2fms p99=%.2fms max=%.2fms" % [
		n, total_ms / 1000.0, total_ms / n,
		sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1]])
	print("FRAME_COST over20ms=%d over33ms=%d (%.1f%%) time_scale_frames=%d(%.1f%%)" % [
		over20, over33, 100.0 * over33 / n, _scaled, 100.0 * _scaled / n])
	if _mode == "arena":
		print("FRAME_COST avg_process=%.2fms avg_drawcalls=%.1f enemy_hp_end=%.0f ended=%s" % [
			_proc_ms / n, _phys_ms / n, arena.battle.enemy_hp, str(arena.battle.ended)])
	else:
		var packs: int = arena.run.zones.size()
		var bodies := 0
		for z in arena.run.zones:
			bodies += (z["members"] as Array).size()
		print("FRAME_COST avg_process=%.2fms avg_drawcalls=%.1f run_over=%s packs=%d bodies=%d floor=%d canvas=%s" % [
			_proc_ms / n, _phys_ms / n, str(arena.run.finished), packs, bodies,
			_count_floor(arena.run), str(arena.size)])
	if _isolate:
		print("SCRIPT_COST avg=%.3fms max=%.3fms over4ms=%d of %d" % [
			_script_ms / n, _script_max, _script_over4, n])
	print("FRAME_COST long_frames=%s" % JSON.stringify(_long.slice(0, 60)))
