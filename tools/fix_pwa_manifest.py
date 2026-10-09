#!/usr/bin/env python3
"""Doplni manifest.json po Godot exportu tak, aby hru slo nainstalovat na Android.

Godot generuje manifest s minimem poli. Androidu (WebAPK) to nestaci - chce
short_name, id, theme_color a hlavne Ikonu 192x192, kterou Godot export vubec
neumi vyrobit (umí jen 144/180/512). Bez toho instalace skonci hlaskou
"Aplikaci nelze otevrit" a prohlibec misto aplikace nabidne jen zkratku.

Skript bezi v CI po exportu a je idempotentni: kdyz uz jsou pole doplnena,
nic nezkazi.

Pouziti: python3 tools/fix_pwa_manifest.py build/web
"""
import json
import os
import shutil
import sys

# 192 je jedina velikost, kterou Godot export neumi a Android ji pozaduje.
ICON_192_SRC = "icons/icon_192.png"
ICON_192_DST = "index.192x192.png"


def main() -> int:
	out = sys.argv[1] if len(sys.argv) > 1 else "build/web"
	mf = os.path.join(out, "index.manifest.json")
	if not os.path.isfile(mf):
		print("FIX_PWA_MANIFEST=fail (chybi %s)" % mf)
		return 1

	with open(mf, "r", encoding="utf-8") as f:
		m = json.load(f)

	# Android pouziva short_name jako popisek pod ikonou.
	m.setdefault("short_name", m.get("name", "Zily"))
	# id musi byt stabilni a v ramci origin; jinak si prohlibec mysli, ze
	# jde o jinou aplikaci a nabizi reinstalaci.
	m.setdefault("id", "./")
	m.setdefault("scope", "./")
	m.setdefault("theme_color", m.get("background_color", "#1a1816"))
	# Aby prohlibec neposlal uzivatele do obchodu s aplikacemi.
	m.setdefault("prefer_related_applications", False)
	m.setdefault("categories", ["games"])

	# Ikona 192: zkopiruj ji do buildu a pridej do manifestu.
	src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ICON_192_SRC)
	if os.path.isfile(src):
		shutil.copyfile(src, os.path.join(out, ICON_192_DST))
		icons = m.setdefault("icons", [])
		if not any(i.get("sizes") == "192x192" for i in icons):
			icons.append({
				"sizes": "192x192",
				"src": ICON_192_DST,
				"type": "image/png",
			})
		icons.sort(key=lambda i: int(str(i.get("sizes", "0x0")).split("x")[0]))
	else:
		print("FIX_PWA_MANIFEST=warn (chybi %s)" % ICON_192_SRC)

	# purpose "any" je pro instalaci povinny; maskable zamerne NEDAVAME -
	# ikona je ctverec na ctyri ctvrty a maskable by ho oriznul.
	for i in m.get("icons", []):
		i.setdefault("purpose", "any")

	with open(mf, "w", encoding="utf-8") as f:
		json.dump(m, f, ensure_ascii=False)

	# Kontrola, ze vse, co Android pozaduje, tam opravdu je.
	need = ["name", "short_name", "start_url", "display", "theme_color", "background_color", "icons"]
	missing = [k for k in need if not m.get(k)]
	sizes = [i.get("sizes") for i in m.get("icons", [])]
	has_192 = "192x192" in sizes
	has_512 = "512x512" in sizes
	if missing or not has_192 or not has_512:
		print("FIX_PWA_MANIFEST=fail missing=%s sizes=%s" % (missing, sizes))
		return 1
	print("FIX_PWA_MANIFEST=ok sizes=%s" % sizes)
	return 0


if __name__ == "__main__":
	sys.exit(main())
