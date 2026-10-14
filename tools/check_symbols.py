#!/usr/bin/env python3
"""KONTROLA OPACNYM SMEREM: co obrazovka/tool vola na hernich objektech, musi
na tech objektech opravdu byt.

Proc: GDScript pri `game.neco` bez te vlastnosti NESPADNE, jen to ohlasi do
logu jako "Invalid get index" - a v prohlizeci to znamena, ze se funkce ani
nedokresli (presne tak zmizela paleta: `game.palette` po refaktoru neexistoval,
i kdyz ho `game_view` pouzival na peti mistech a vsechny testy byly zelene).

Pouziti: python3 tools/check_symbols.py [adresar_repozitare]
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
SCRIPTS = ROOT / "scripts"
TOOLS = ROOT / "tools"

# Ktere promenne v obrazovce patri kteremu skriptu. Klic = jmeno promenne
# v game_view, hodnota = soubor, ktery tu tridu definuje.
OWNERS = {
    "game": "game.gd",
    "layout": "screen_layout.gd",
    "menu": "menu.gd",
    "settings": "settings.gd",
    "profile": "profile.gd",
}

DECL = re.compile(r"^(?:@?\w+\s+)*?(?:var|const)\s+(\w+)")
FUNC = re.compile(r"^func\s+(\w+)")
# Jmena, ktera nejsou pristup k vlastnosti: nazvy souboru v textu/komentari
# (`game.gd`) a pripony (`settings.cfg`). Bez toho hlasi kontrola poplach
# na kazde vete, kde je jmeno souboru.
SKIP_NAMES = {"gd", "cfg", "png", "json", "txt", "py", "tscn", "sh", "md",
              "gd.uid", "html", "wasm", "pck"}


def members_of(path: Path) -> set:
    out = set()
    src = path.read_text(encoding="utf-8", errors="replace")
    for line in src.splitlines():
        m = DECL.match(line.strip())
        if m:
            out.add(m.group(1))
        m = FUNC.match(line.strip())
        if m:
            out.add(m.group(1))
        # signály
        m = re.match(r"^signal\s+(\w+)", line.strip())
        if m:
            out.add(m.group(1))
    # vestavene veci, ktere Godot prida kazdemu objektu
    out |= {"new", "get", "set", "has_method", "get_property_list", "free",
            "call", "callv", "get_class", "is_class", "duplicate", "equals",
            "get_script", "set_script", "get_instance_id", "connect", "emit",
            "notify", "to_string", "get_meta", "set_meta", "has_meta"}
    return out


def main() -> int:
    owners = {}
    for var, fname in OWNERS.items():
        p = SCRIPTS / fname
        if p.exists():
            owners[var] = (fname, members_of(p))

    problems = []
    files = sorted(list(SCRIPTS.glob("*.gd")) + list(TOOLS.glob("*.gd")))
    for f in files:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, raw in enumerate(lines):
            line = raw.strip()
            if line.startswith("#"):
                continue
            for var, (fname, members) in owners.items():
                for name in re.findall(r"\b" + var + r"\.(\w+)", raw):
                    if name in members or name in SKIP_NAMES:
                        continue
                    problems.append("%s:%d  %s.%s  (chybi v %s)  | %s"
                                    % (f.relative_to(ROOT), i + 1, var, name, fname, line))

    # game.tower.<x> zvlast (tower.gd)
    tower_members = members_of(SCRIPTS / "tower.gd")
    for f in files:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, raw in enumerate(lines):
            if raw.strip().startswith("#"):
                continue
            for name in re.findall(r"\btower\.(\w+)", raw):
                if name in tower_members or name in SKIP_NAMES:
                    continue
                problems.append("%s:%d  tower.%s  (chybi v tower.gd)"
                                % (f.relative_to(ROOT), i + 1, name))

    if problems:
        print("CHYBI_%d" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("SYMBOLS_OK (vsechno, co obrazovky a nastroje volaji, existuje)")
    return 0


sys.exit(main())
