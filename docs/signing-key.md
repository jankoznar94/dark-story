# Signing key (the one file that must never be lost)

## What it is

`~/.android/debug.keystore` — a standard Android **debug** keystore, reused here as the
release key so the tester can install a new build *over* an old one instead of
uninstalling first.

| | |
|---|---|
| Alias | `androiddebugkey` |
| Store password | `android` |
| Key password | `android` |
| Created | 2026-09-17 |
| Valid until | 2054-02-02 |
| SHA256 | `45:80:66:F0:D8:22:F5:ED:21:50:1D:53:2D:26:71:42:95:23:BD:5E:4E:D7:95:7F:7C:71:78:19:E5:00:EC:A5` |

## Why it matters

Android identifies an installed app by its signing key. If a build is signed with a
**different** key, Android refuses to install it as an update and the player must
uninstall the game first. So this file is effectively permanent.

## Backups

Two copies exist:

1. `~/.android/debug.keystore` — the live one, used by `build.sh`
2. `~/tools/backup/dark-story-debug.keystore` — restore copy on this machine
3. A copy was emailed to Jan as an off-machine backup

`build.sh` **restores from (2) automatically** if (1) goes missing, and refuses to build
if neither exists — deliberately, because silently generating a fresh key would break
every existing install.

It also compares the key's SHA256 against the value above and warns loudly on a mismatch.

## Restoring by hand

```bash
mkdir -p ~/.android
cp ~/tools/backup/dark-story-debug.keystore ~/.android/debug.keystore
chmod 600 ~/.android/debug.keystore

# prove it is the right key - must match the SHA256 in the table above
~/tools/jdk-17/bin/keytool -list -v \
  -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey \
  | grep SHA256
```

## Generating a replacement (only if every copy is lost)

Accept that updates break, then:

```bash
mkdir -p ~/.android
~/tools/jdk-17/bin/keytool -keyalg RSA -genkeypair -alias androiddebugkey \
  -keypass android -keystore ~/.android/debug.keystore -storepass android \
  -dname "CN=Android Debug,O=Android,C=US" -validity 10000 -deststoretype pkcs12
```

Then update the SHA256 in **both** this file and the `KS_SHA` variable in `build.sh`,
and tell the tester they must uninstall the game once.
