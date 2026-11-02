#!/usr/bin/env python3
"""Rebuild the Android signing keystore from the `ANDROID_KEYSTORE_BASE64` secret.

Why this is not a one-line `base64 -d`: a secret is pasted by hand from a text file,
and the three ways that goes wrong are all silent.

  * the whole file was copied, label lines and all (letters are VALID base64
    characters, so `base64 -d -i` happily decodes them into a corrupt keystore);
  * the value was wrapped by an editor, so the one line became twenty;
  * quotes or a trailing newline came along.

So: take the longest run of base64 characters in the value, decode it, and accept the
result only if it starts with a real keystore magic (`FE ED FE ED` for JKS, `30 82` for
PKCS#12). Anything else exits non-zero with a message that names the problem — a build
that quietly signs with the runner's debug key produces an APK that can never be
updated over, which is the failure this whole pipeline exists to prevent.

    DR_ANDROID_KEYSTORE_B64   the secret's value
    argv[1]                   where to write the .jks
"""

import base64
import os
import re
import sys

ALPHABET = re.compile(r"[A-Za-z0-9+/=]+")
JKS_MAGIC = b"\xfe\xed\xfe\xed"


def main() -> int:
    if len(sys.argv) < 2:
        print("ci_android_keystore: usage: ci_android_keystore.py <output.jks>", file=sys.stderr)
        return 1
    out_path = sys.argv[1]
    raw = os.environ.get("DR_ANDROID_KEYSTORE_B64", "")
    if raw.strip() == "":
        print("ci_android_keystore: the secret is empty", file=sys.stderr)
        return 1

    # Wrapped or indented pasting is the norm, and so is pasting the WHOLE text file the
    # value came from. Work line by line and collect RUNS of base64-looking lines: the
    # label lines around the value are letters, i.e. valid base64 characters, so splicing
    # them in would decode into a corrupt key.
    #
    # ⚠️  No `FE ED FE ED` anchor: modern `keytool` writes PKCS#12 (`30 82 …`), so the
    # keystore we generated does not start with the JKS magic at all. Validate by magic
    # AFTER decoding, never by assuming one container format.
    candidates: list[str] = []
    run: list[str] = []
    for raw_line in raw.splitlines():
        line = raw_line.strip().strip('"').strip("'").replace(" ", "")
        if re.fullmatch(r"[A-Za-z0-9+/=]+", line) and len(line) >= 8:
            run.append(line)
        elif run:
            candidates.append("".join(run))
            run = []
    if run:
        candidates.append("".join(run))
    # Last resort: the whole value with the whitespace taken out.
    candidates.append("".join(raw.split()))
    candidates.sort(key=len, reverse=True)

    data = b""
    for blob in candidates:
        try:
            decoded = base64.b64decode(blob + "=" * (-len(blob) % 4), validate=False)
        except Exception:
            continue
        # A PKCS#12/JKS holding one RSA-2048 key is ~2.7 kB. Anything under 1.5 kB is a
        # TRUNCATED secret that still starts with the right magic — accept it and the
        # export fails later with a confusing keytool error instead of here.
        if len(decoded) >= 1500 and (decoded.startswith(JKS_MAGIC)
                                     or decoded.startswith(b"\x30\x82")):
            data = decoded
            break
    if data == b"":
        print("ci_android_keystore: could not find a keystore in the secret "
              "(value %d chars, %d base64-ish runs, longest %d) — paste the whole long "
              "line, or the value is truncated"
              % (len(raw), len(candidates), len(candidates[0]) if candidates else 0),
              file=sys.stderr)
        return 1

    with open(out_path, "wb") as f:
        f.write(data)
    os.chmod(out_path, 0o600)
    print("ci_android_keystore: wrote %d bytes to %s" % (len(data), out_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
