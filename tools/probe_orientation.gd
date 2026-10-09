extends SceneTree

# Overuje vyznam hodnoty display/window/handheld/orientation primo z enginu,
# aby se "nativne na sirku" nehadalo z dokumentace.

func _init() -> void:
	for p in ProjectSettings.get_property_list():
		var n: String = str(p.get("name", ""))
		if n == "display/window/handheld/orientation":
			print("HINT=", p.get("hint_string", ""))
	print("nastaveno=", ProjectSettings.get_setting("display/window/handheld/orientation"))
	print("SCREEN_LANDSCAPE=", DisplayServer.SCREEN_LANDSCAPE)
	print("SCREEN_PORTRAIT=", DisplayServer.SCREEN_PORTRAIT)
	print("SCREEN_REVERSE_LANDSCAPE=", DisplayServer.SCREEN_REVERSE_LANDSCAPE)
	print("SCREEN_SENSOR_LANDSCAPE=", DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	print("viewport=", get_root().get_visible_rect().size)
	quit()
