#!/usr/bin/env python3
"""Reports rooms whose map rows have inconsistent widths."""
import glob, sys
bad = 0
for p in sorted(glob.glob("data/levels/*.txt")):
    cur = None; rows = []; inmap = False
    def flush():
        global bad
        if cur and rows and len(set(map(len, rows))) > 1:
            bad += 1
            w = max(set(map(len, rows)), key=list(map(len, rows)).count)
            for i, r in enumerate(rows):
                if len(r) != w:
                    print(f"{p} {cur} row {i}: width {len(r)} (expected {w})")
    for line in open(p).read().split("\n"):
        if line.startswith("==="):
            flush(); cur = line[3:].strip(); rows = []; inmap = False; continue
        if line.strip() == "---": inmap = True; continue
        if inmap and line.strip() and not line.startswith(";"): rows.append(line)
    flush()
sys.exit(1 if bad else 0)
