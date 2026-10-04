#!/usr/bin/env python3
"""Replace (or append) a room block in a level file.
Usage: python3 tools/set_room.py <level file> < block.txt
The block must start with '=== <id>'. Comment lines directly above the old
block are kept."""
import sys, re
path = sys.argv[1]
block = sys.stdin.read().strip("\n") + "\n"
rid = block.split("\n")[0][3:].strip()
lines = open(path).read().split("\n")
start = None
for i, l in enumerate(lines):
    if l.startswith("===") and l[3:].strip() == rid:
        start = i
        break
if start is None:
    out = "\n".join(lines).rstrip("\n") + "\n\n" + block
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("===") or (lines[j].startswith("; ----") ):
            end = j
            break
    out = "\n".join(lines[:start]) + "\n" + block + "\n" + "\n".join(lines[end:])
open(path, "w").write(out)
rows = [l for l in block.split("\n")[block.split("\n").index("---") + 1:] if l.strip()]
widths = set(map(len, rows))
print(f"{rid}: {len(rows)} rows, widths {sorted(widths)}")
if len(widths) > 1:
    sys.exit(f"ERROR: {rid} has inconsistent row widths")
