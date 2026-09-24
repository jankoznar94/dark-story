extends SceneTree
## probe_map_expand — capture the port's map with an act EXPANDED, i.e. the stop cards.
##
## The map's stop path only exists while `_expanded_act` is set, and the capture tool
## (`capture_screen.gd --screen map`) always shoots the COLLAPSED map. Every image on this
## screen that Jan reports as wrong — act art and stop art — is judged here, so this probe
## exists rather than a manual poke through main.gd.
##
##   godot4 --path . --rendering-driver opengl3 \
##       --script res://tools/probe_map_expand.gd -- --act 0 --out /tmp/port_map_exp_0.png
##
## `--act -1` leaves the map collapsed (the reference frame's own state).
var _main: Node = null
var _act := 0
var _out := "/tmp/port_map_exp.png"
var _frames := 0
var _target := 90
var _started := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--act":
				_act = int(args[i + 1])
			"--out":
				_out = args[i + 1]
			"--frames":
				_target = int(args[i + 1])
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("map") or _main._nav_bar == null:
			return false
		_started = true
		_main.show_screen("map")
		var map = _main._screens["map"]
		map.refresh()
		if _act >= 0:
			map._toggle_act(_act)
		_report(map)
		return false
	_frames += 1
	if _frames < _target:
		return false
	_capture()
	return false


## Print every act card's and stop card's rect plus the texture each one actually resolved,
## because "the art is wrong" is either a NULL texture or a wrong rect and the two look the
## same in a screenshot.
func _report(map) -> void:
	print("--- map report (expanded act %d) ---" % _act)
	var list: VBoxContainer = map._list
	for child in list.get_children():
		if child is Button:
			var b := child as Button
			print("act card  rect=%s  modulate=%s  children=%d" % [b.get_rect(), b.modulate,
				b.get_child_count()])
			for sub in b.get_children():
				if sub is TextureRect:
					var t := sub as TextureRect
					print("    art   rect=%s texture=%s stretch=%d" % [t.get_rect(),
						str(t.texture.resource_path if t.texture != null else "<NULL>"),
						t.stretch_mode])
		elif child is VBoxContainer:
			for card in child.get_children():
				if card is Button:
					var sb := card as Button
					print("stop card rect=%s modulate=%s" % [sb.get_rect(), sb.modulate])
					for sub in sb.get_children():
						if sub is TextureRect:
							var st := sub as TextureRect
							print("    art   rect=%s texture=%s stretch=%d" % [st.get_rect(),
								str(st.texture.resource_path if st.texture != null else "<NULL>"),
								st.stretch_mode])
				else:
					print("stop path child: %s" % child.get_class())


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	print("probe_map_expand: %dx%d -> %s" % [img.get_width(), img.get_height(), _out])
	quit()
