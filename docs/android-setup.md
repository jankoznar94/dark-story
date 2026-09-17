# Android export setup (user-local, no sudo)

Everything lives under `~/tools/` — nothing system-wide, no `sudo` required.
Installed by `~/tools/setup_android.sh`; wired into the Godot editor by
`tools/setup_android_editor.gd`.

| Thing | Path | Size |
|---|---|---|
| JDK 17 (Temurin) | `~/tools/jdk-17` | ~318 MB |
| Android SDK | `~/tools/android-sdk` | ~2 GB once build-tools + platform are in |
| Debug keystore | `~/.android/debug.keystore` | tiny |

## Two pitfalls that cost time

1. **`sdkmanager` must be invoked with `--sdk_root=<path>`.** The downloaded
   `commandlinetools-linux-*.zip` extracts as `cmdline-tools/bin/…`, not the
   `cmdline-tools/latest/bin/…` layout the tool expects, so it refuses to run
   with `Could not determine SDK root`. Passing `--sdk_root` explicitly works
   without moving anything.

2. **`unzip` is not installed on this box.** Extract archives with
   `python3 -c "import zipfile; zipfile.ZipFile(p).extractall(d)"`.

## Packages needed by Godot's Android export

```
platform-tools
build-tools;35.0.0
platforms;android-35
```

## Wiring it into Godot

```bash
~/tools/godot/godot4 --headless --path . --script res://tools/setup_android_editor.gd
```

That writes the EditorSettings keys Godot reads for headless Android export:

- `export/android/android_sdk_path`
- `export/android/java_sdk_path`
- `export/android/debug_keystore` (+ `_user`, `_pass`)

## Then export

```bash
mkdir -p build/android
~/tools/godot/godot4 --headless --path . --export-release "Android"
```

## Signing

Godot signs the APK with `~/.android/debug.keystore` (alias `androiddebugkey`,
password `android`) when the preset has `package/signed=true`. **Keep that keystore
backed up** — Android refuses an update signed with a different key, so losing it
means the tester has to uninstall and reinstall.

## Disk

Budget was approved by the host owner for this (JDK + SDK ≈ 2 GB). Nothing else
on the box should grow without asking.
