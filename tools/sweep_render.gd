extends SceneTree
## Render MANY lighting variants of the real game scene in ONE run.
##
## Why this exists: tuning art one render per iteration is the bottleneck. Each
## render costs a full engine start (~10 s) plus a round trip through chat, so a
## six-value decision took six renders and six exchanges. This sweeps the whole
## parameter space in a single engine start and writes a labelled contact sheet,
## so a decision becomes "look at one image" instead of "iterate".
##
##   godot --path . --rendering-driver opengl3 --resolution 480x270 \
##     --script res://tools/sweep_render.gd -- --presets /tmp/lights.json --out sweep
##
## presets JSON: {"presets": [{"name": "...", "sun": 0.95, "amb": 0.34, ...}, ...]}
## Every key is optional; omitted keys keep whatever main.gd set.

var t := 0.0
var scene: Node3D
var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var cam: Camera3D
var presets: Array = []
var idx := -1
var settle := 0
var outdir := "user://sweep"
var results: Array = []
var started := false


func _arg(flag: String, dflt: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return args[i + 1]
	return dflt


func _initialize() -> void:
	var presets_path := _arg("--presets", "")
	outdir = _arg("--out", "user://sweep")
	if presets_path == "":
		print("SWEEP_NO_PRESETS")
		quit(1)
		return
	var f := FileAccess.open(presets_path, FileAccess.READ)
	if f == null:
		print("SWEEP_CANT_OPEN ", presets_path)
		quit(1)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	presets = parsed.get("presets", [])
	if presets.is_empty():
		print("SWEEP_EMPTY")
		quit(1)
		return
	print("SWEEP_PRESETS_LOADED %d" % presets.size())


func _boot() -> void:
	# main.tscn's Main node builds its WorldEnvironment and lights in _ready(),
	# so the nodes only exist once the scene is actually inside the tree. Doing
	# this from _initialize found nothing (env=false sun=false fill=false) and the
	# run then hung until the timeout.
	var packed: PackedScene = load("res://scenes/main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	cam = scene.get_node_or_null("Camera")
	if cam:
		cam.set_process(false)
		cam.global_position = Vector3(0, 12.5, 9.0)
		cam.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	for c in scene.get_children():
		if c is WorldEnvironment:
			env = c.environment
		elif c is DirectionalLight3D:
			if c.name == "Sun":
				sun = c
			elif c.name == "Fill":
				fill = c
	# main.gd adds the world nodes in _ready; if this ran before that, retry.
	print("SWEEP_READY presets=%d env=%s sun=%s fill=%s" % [presets.size(), env != null,
		sun != null, fill != null])
	if env == null or sun == null:
		print("SWEEP_MISSING_WORLD_NODES")
		quit(1)


func _apply(p: Dictionary) -> void:
	if env:
		if p.has("sun"):
			sun.light_energy = float(p["sun"])
		if p.has("sun_color"):
			var c: Array = p["sun_color"]
			sun.light_color = Color(c[0], c[1], c[2])
		if p.has("fill"):
			fill.light_energy = float(p["fill"])
		if p.has("amb"):
			env.ambient_light_energy = float(p["amb"])
		if p.has("amb_color"):
			var a: Array = p["amb_color"]
			env.ambient_light_color = Color(a[0], a[1], a[2])
		if p.has("brightness"):
			env.adjustment_brightness = float(p["brightness"])
		if p.has("contrast"):
			env.adjustment_contrast = float(p["contrast"])
		if p.has("saturation"):
			env.adjustment_saturation = float(p["saturation"])
		if p.has("fog"):
			env.fog_density = float(p["fog"])
		if p.has("shadow_opacity"):
			sun.shadow_opacity = float(p["shadow_opacity"])
		if p.has("tonemap"):
			env.tonemap_mode = int(p["tonemap"])


func _next() -> bool:
	idx += 1
	if idx >= presets.size():
		var f := FileAccess.open(outdir.path_join("sweep.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"results": results, "outdir": outdir}))
		f.close()
		print("SWEEP_DONE count=%d out=%s" % [results.size(), ProjectSettings.globalize_path(outdir)])
		return true
	_apply(presets[idx])
	settle = 0
	return false


func _process(delta: float) -> bool:
	t += delta
	if not started:
		if t < 0.5:
			return false
		started = true
		_boot()
		# Apply preset 0 HERE, otherwise the settle logic captures one frame
		# before any preset is applied and every label in the sheet is off by one.
		if not _next():
			t = 0.0
			return false
		return true
	if t < 0.4:
		return false
	if settle == 0:
		settle = 1
		return false
	if settle == 1:
		settle = 2
		return false
	var img := get_root().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
	var nm := str(presets[idx].get("name", "v%d" % idx))
	var path := outdir.path_join("%02d_%s.png" % [idx, nm])
	img.save_png(path)
	results.append({"idx": idx, "name": nm, "file": ProjectSettings.globalize_path(path),
		"preset": presets[idx]})
	print("CAPTURED %s" % ProjectSettings.globalize_path(path))
	t = 0.0
	return _next()
