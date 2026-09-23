#!/usr/bin/env python3
"""Summarise probe_modal_pwa.py's output: one line per element, per tab."""

import json
import sys

txt = open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/modal_pwa.txt").read()
blocks = txt.split("--- ")
for block in blocks[1:]:
    lines = block.splitlines()
    name = lines[0].strip()
    data = json.loads("\n".join(lines[1:]))
    print(f"== {name} ==")
    print("  content ", data["content"], data["contentStyle"]["minH"],
          "max", data["contentStyle"]["maxH"])
    print("  tabs    ", data["tabs"])
    print("  body    ", data["body"])
    print("  screen  ", data["screen"], "flex", data["screenStyle"]["flex"],
          "minH", data["screenStyle"]["minHeight"],
          "overflowY", data["screenStyle"]["overflowY"])
    for c in data["children"]:
        t = f"  <{c['title']}>" if c["title"] else ""
        print(f"  {c['tag']:<6} {c['cls'][:28]:<28} {c['rect']}{t}")
