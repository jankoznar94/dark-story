extends SceneTree
## tools/look_confirm.gd — render the clear-save dialog (the ask and the "hotovo" message) as
## PNGs on the REAL game screen.
##
##   ~/tools/godot/godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##       --script res://tools/look_confirm.gd -- --out=/tmp/dr_confirm
##
## A headless run has no viewport texture, so this is never run with `--headless`.
## It is a dev aid: it wipes NOTHING on disk (`save_enabled = false`) and pushes nothing.

var _main
var _phase := 0
var _frame := 0
var _out := "/tmp/dr_confirm"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		root.size = Vector2i(390, 844)
		_main = load("res://scripts/main.gd").new()
		root.add_child(_main)
		return false
	if _frame == 3:
		_main._splash.queue_free()
		_main.state.save_enabled = false
		return false
	# The dialog ignores input for OPEN_GUARD_MS, and this script opens it by calling the tap
	# handler directly — so only the RENDER matters, not a tap.
	if _frame == 10:
		_main._on_clear_save_tapped()
		return false
	if _frame == 16:
		_shot("ask")
		return false
	if _frame == 18:
		_main._clear_save()
		return false
	if _frame == 24:
		_shot("done")
		return false
	if _frame > 26:
		quit(0)
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s_%s.png" % [_out, name]
	var err := img.save_png(path)
	print("LOOK_CONFIRM %s -> %s (%s) dialog=%s" % [
		name, path, error_string(err), str(_main._confirm.title_text())])
