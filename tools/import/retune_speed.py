"""Apply the convert.mjs `retune()` speed pass to the already-generated data/ tables.

Kept as a one-shot tool so the current data/*.json match what a regeneration would write
(the retune itself lives in tools/import/convert.mjs, which owns the numbers).
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
DATA = ROOT / "data"


def snap(v):
    return round(v / 10) * 10


def main():
    items_path = DATA / "ITEMS.json"
    items = json.loads(items_path.read_text(encoding="utf-8"))
    n = 0
    for it in items:
        if it.get("type") != "weapon" or not it.get("swingMs"):
            continue
        it["swingMs"] = min(1000, max(400, snap(400 + (it["swingMs"] - 700) * (600 / 1100))))
        n += 1
    items_path.write_text(json.dumps(items, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    mon_path = DATA / "MONSTER_DB.json"
    themes = json.loads(mon_path.read_text(encoding="utf-8"))
    m = 0
    for theme in themes:
        for row in theme:
            if not row.get("attackSpeed"):
                continue
            row["attackSpeed"] = max(700, snap(row["attackSpeed"] * 0.65))
            m += 1
    mon_path.write_text(json.dumps(themes, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"weapons retuned: {n}, monster attack speeds retuned: {m}")


if __name__ == "__main__":
    main()
