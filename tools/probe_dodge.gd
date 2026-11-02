extends SceneTree
class_name ProbeDodge
## ProbeDodge — what the reaction row and the middle icon ACTUALLY are, on a real frame.
##
##   godot4 --path . --script res://tools/probe_dodge.gd
##
## Jan: "the Dodge button is somehow fallen apart". A PNG cannot say which child is drawn
## where, so this prints every rect, size, minimum and texture of the three reaction buttons
## and of the middle icon while an opportunity window is open.
##
## ⚠️  It FORCES `battle.opp_type` for the dodge button rather than rolling for a window.
## That is the one hack: the chance is 12-40 % per enemy swing and a probe that waits for it
## prints a different state from run to run. The rules are not under test here, the LAYOUT is.
const ToolHelpers := preload("res://tools/tool_helpers.gd")

var _main: Node = null
var _started := false
var _armed := false
var _frames := 0


func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)
	# ⚠️  Do NOT touch `root.size` here. A headless root Window is 64x64, but forcing
	# Vector2i(390, 844) does NOT give the game a 390x844 screen — it gave the ARENA
	# 844x844 (the probe printed arena_rect=S:(844,844) against a viewport of (64,64))
	# and a row of buttons 112 high. Run this the way `capture_screen` runs: with a real
	# (offscreen) display, where the window is the project's 390x844.


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		ToolHelpers.enter_arena(_main, 0, 0)
		return false
	_frames += 1
	var arena = _main._screens.get("arena", null)
	if arena == null or arena.battle == null:
		if _frames > 240:
			print("probe_dodge: FAIL no battle after ", _frames, " frames")
			quit(2)
		return false
	if not _armed:
		if not arena._reaction_row == null and arena._reaction_row.visible == false:
			pass
		# Wait for a layout pass with a live fight, then force ONE dodge window.
		if _frames < 12:
			return false
		_armed = true
		var b = arena.battle
		b.opp_type = "dodge"
		b.opp_resolved = false
		b.opp_failed = false
		return false
	if _frames < 40:
		return false
	_report(arena)
	quit(0)
	return false


func _report(arena) -> void:
	var b = arena.battle
	print("=== state ===")
	print("viewport=", root.size, " arena_rect=", arena.get_global_rect(),
		" battle.opp_type=", b.opp_type, " open=", b.opportunity_open())
	var row: Control = arena._reaction_row
	print("=== reaction row ===")
	print("visible=", row.visible, " rect=", row.get_global_rect(),
		" size=", row.size, " pos=", row.position,
		" align=", row.alignment, " sep=", row.get_theme_constant("separation"))
	for kind in arena._reaction_buttons:
		var btn: Button = arena._reaction_buttons[kind]
		print("--- button '", kind, "' visible=", btn.visible,
			" rect=", btn.get_global_rect(), " size=", btn.size,
			" min=", btn.custom_minimum_size, " children=", btn.get_child_count())
		for child in btn.get_children():
			var line := "      child %s rect=%s size=%s visible=%s" % [
				child.get_class(), str(child.get_global_rect()), str(child.size), str(child.visible)]
			if child is TextureRect and (child as TextureRect).texture != null:
				line += " tex=%s tex_size=%s" % [
					str((child as TextureRect).texture.resource_path),
					str((child as TextureRect).texture.get_size())]
			if "texture" in child:
				var t = child.texture
				if t != null:
					line += " tex=%s tex_size=%s" % [str(t.resource_path), str(t.get_size())]
				line += " ring_w=%s ring_col=%s backdrop=%s" % [
					str(child.ring_width), str(child.ring_colour), str(child.backdrop)]
			print(line)
	print("=== middle icon ===")
	var icon: Control = arena._action_icon
	print("visible=", icon.visible, " rect=", icon.get_global_rect(), " size=", icon.size,
		" pos=", icon.position, " min=", icon.custom_minimum_size)
	var img = arena._action_image
	print("  image rect=", img.get_global_rect(), " size=", img.size, " pos=", img.position,
		" min=", img.custom_minimum_size, " ring_w=", img.ring_width,
		" ring_col=", img.ring_colour, " backdrop=", img.backdrop)
	if img.texture != null:
		print("  image tex=", img.texture.resource_path, " tex_size=", img.texture.get_size())
	else:
		print("  image tex=NONE")
	var ring: Control = arena._action_ring
	print("  ring visible=", ring.visible, " rect=", ring.get_global_rect(), " size=", ring.size)
