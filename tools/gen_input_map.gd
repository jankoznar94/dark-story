extends SceneTree
## Regenerates the [input] section of project.godot so every control is an ACTION
## (move / attack / skill_1 ...), never a hardcoded key. That is what keeps
## touch, keyboard and gamepad all working from one code path.
## Run: godot --headless --path . --script res://tools/gen_input_map.gd

const KEYMAP := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack": [KEY_SPACE, KEY_J],
	"skill_1": [KEY_Q, KEY_K],
	"skill_2": [KEY_E, KEY_L],
	"potion": [KEY_1],
	"run": [KEY_SHIFT],
}

const PADMAP := {
	"attack": [JOY_BUTTON_A],
	"skill_1": [JOY_BUTTON_X],
	"skill_2": [JOY_BUTTON_Y],
	"potion": [JOY_BUTTON_B],
	"run": [JOY_BUTTON_LEFT_SHOULDER],
	"move_up": [],
	"move_down": [],
	"move_left": [],
	"move_right": [],
}


func _init() -> void:
	for action in KEYMAP.keys():
		var events: Array = []
		for k in KEYMAP[action]:
			var ek := InputEventKey.new()
			ek.physical_keycode = k
			events.append(ek)
		for b in PADMAP.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			events.append(jb)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	print("actions written: ", KEYMAP.size())
	var err := ProjectSettings.save()
	print("ProjectSettings.save() -> ", err)
	quit()
