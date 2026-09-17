extends SceneTree
## Points the Godot editor at the user-local JDK + Android SDK, and at the debug
## keystore, so `--export-release "Android"` works headlessly without opening the GUI.
##
## Run AFTER tools/setup_android.sh:
##   godot --headless --path . --script res://tools/setup_android_editor.gd

const JDK := "/home/martin_fabian/tools/jdk-17"
const SDK := "/home/martin_fabian/tools/android-sdk"
const KEYSTORE := "/home/martin_fabian/.android/debug.keystore"


func _init() -> void:
	var es := EditorSettings.new()

	es.set_setting("export/android/android_sdk_path", SDK)
	es.set_setting("export/android/java_sdk_path", JDK)
	es.set_setting("export/android/debug_keystore", KEYSTORE)
	es.set_setting("export/android/debug_keystore_user", "androiddebugkey")
	es.set_setting("export/android/debug_keystore_pass", "android")

	# Gradle-less builds keep this fast; gradle is only needed for plugins/AAB.
	es.set_setting("export/android/gradle_build/use_gradle_build", false)

	var err: int = es.save()
	print("EditorSettings.save() -> ", err)
	print("android_sdk_path  = ", es.get_setting("export/android/android_sdk_path"))
	print("java_sdk_path     = ", es.get_setting("export/android/java_sdk_path"))
	print("debug_keystore    = ", es.get_setting("export/android/debug_keystore"))
	quit()
