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

The APK that reaches the phone is signed by CI with a **dedicated release keystore**,
not with the local debug key. That is the whole delivery rule: Android refuses to
install an APK signed with a different key than the installed one, so a stable key is
what makes "download → install over the old build → keep the save" possible.

| What | Where |
|---|---|
| Keystore | `~/dr-godot-keys/dungeon-recall-release.jks` (outside the repo, mode 600) |
| Alias | `dungeonrecall` |
| Store + key password | `~/dr-godot-keys/password.txt` |
| Certificate SHA-256 | `C1:0C:E8:30:DE:D1:F3:3F:7F:85:F6:38:99:00:FF:1B:C6:FB:98:92:2F:CC:E9:66:A1:8F:1C:5B:9E:A8:F6:10` |
| Valid until | 2054 |

**Back this keystore up somewhere outside the box.** Losing it means every installed
copy has to be uninstalled (and its save deleted) before a new build can go on.

Godot 4.7 reads the signing key from the environment, so no secret is ever written
into `export_presets.cfg` or any other tracked file:

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH
GODOT_ANDROID_KEYSTORE_RELEASE_USER
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

CI supplies those from repository secrets (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASSWORD`); locally you export with them
set in the shell, which is what `tools/ci_android_version.py` plus a plain
`--export-release "Android"` does.

⚠️  Do not move these values into `[preset.2.options.keystore]`. Godot 4.7 *writes*
that sub-block but its loader only reads the flat `[preset.N.options]` section, so a
keystore placed there is silently ignored and the export fails with
"Could not find release keystore" while the file looks perfectly configured.

## Delivery to the phone

Every push to `dr-godot` runs the workflow, which exports the APK, stamps it with
`version/code = <run number>` and publishes it to a rolling GitHub release:

```
https://github.com/jankoznar94/dark-story/releases/download/android-latest/dungeon-recall.apk
```

Open that link on the phone, install over the old build, save kept. The same URL
always serves the newest build, so nothing has to be rebuilt or copied by hand. The
APK is also kept as a workflow artifact for when a release step itself fails.

⚠️  Address the release by TAG (`/releases/download/android-latest/…`), never by
`/releases/latest/…`: this repository also publishes Zily and Thrower builds, so the
"latest" badge must not be claimed by this workflow.

⚠️  The publish step runs on whichever branch was pushed last, exactly like the web
deploy — the phone build must be the same code the browser serves. It only runs once
the keystore secret exists; an APK signed with a throwaway key would install but
could never be updated over.

First install only: Android asks once for permission to install from this source.

## Disk

Budget was approved by the host owner for this (JDK + SDK ≈ 2 GB). Nothing else
on the box should grow without asking.
