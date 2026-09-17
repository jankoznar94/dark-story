extends SceneTree
## Reports whether the local Android toolchain is where Godot expects it.
## Run: godot --headless --path . --script res://tools/check_android_env.gd

const JDK := "/home/martin_fabian/tools/jdk-17"
const SDK := "/home/martin_fabian/tools/android-sdk"
const KEYSTORE := "/home/martin_fabian/.android/debug.keystore"


func _init() -> void:
	var ok := true
	ok = _check("java binary", JDK + "/bin/java", false) and ok
	ok = _check("sdkmanager", SDK + "/cmdline-tools/bin/sdkmanager", false) and ok
	ok = _check("build-tools 35.0.0", SDK + "/build-tools/35.0.0", true) and ok
	ok = _check("platform android-35", SDK + "/platforms/android-35", true) and ok
	ok = _check("platform-tools", SDK + "/platform-tools", true) and ok
	ok = _check("debug keystore", KEYSTORE, false) and ok
	print("ANDROID_ENV_OK=", ok)
	quit()


func _check(label: String, path: String, is_dir: bool) -> bool:
	var present := DirAccess.dir_exists_absolute(path) if is_dir else FileAccess.file_exists(path)
	print(("  OK   " if present else "  MISS ") + label + "  (" + path + ")")
	return present
