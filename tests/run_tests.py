#!/usr/bin/env python3
"""
Jeste automated level verification.

1. Lists every room-traversal and collectible task for each chapter.
2. Replays cached solutions; solves anything missing/stale with the in-engine
   solver (parallel Godot workers).
3. Builds the room graph and proves, for every chapter, that
     - the chapter end is reachable from the start, and
     - every collectible can be collected on a route that still reaches the end.
4. Repeats steps 2-3 with the basic moveset only (no supers, hypers or
   wall-bounces, which the game never teaches), caching those routes in
   tests/solutions_basic/, and scores their timing robustness. That is the
   closer proxy for how hard a room is for a player.
5. Plays every chapter end-to-end through the real Level scene, chaining the
   proven room solutions, and checks every collectible lands in the save file
   with zero deaths (which also proves each Golden Sunberry run).

Usage:  python3 tests/run_tests.py [--chapters 0 1 2] [--jobs N] [--budget N] [--no-e2e] [--resolve]
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOL_DIR = os.path.join(ROOT, "tests", "solutions")
BASIC_DIR = os.path.join(ROOT, "tests", "solutions_basic")
GODOT = os.environ.get("GODOT", "godot")
# Godot's user:// (saves, settings, logs) goes to a throwaway folder in the
# git-ignored build/, so no test can touch a player's real save or settings.
TEST_USER = os.path.join(ROOT, "build", "test_user")
ENV = dict(os.environ, XDG_DATA_HOME=os.path.join(TEST_USER, "data"),
           XDG_CONFIG_HOME=os.path.join(TEST_USER, "config"), XDG_CACHE_HOME=os.path.join(TEST_USER, "cache"))


def godot(args, timeout=None):
    cmd = [GODOT, "--headless", "--path", ROOT, "--script"] + args
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV)
    return p


def list_tasks(chapters):
    out = os.path.join(tempfile.gettempdir(), "jeste_tasks.json")
    p = godot(["res://tests/list_tasks.gd", "--", out] + [str(c) for c in chapters], timeout=600)
    if not os.path.exists(out):
        print(p.stdout, p.stderr)
        sys.exit("list_tasks failed")
    with open(out) as f:
        data = json.load(f)
    for line in (p.stdout + p.stderr).splitlines():
        if "SCRIPT ERROR" in line or line.startswith("ERROR"):
            print("  [godot]", line)
    return data


def sol_path(tid, sol_dir=SOL_DIR):
    return os.path.join(sol_dir, tid + ".json")


def load_cached(task, sol_dir=SOL_DIR):
    path = sol_path(task["id"], sol_dir)
    if not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            d = json.load(f)
    except Exception:
        return None
    return d


def run_worker(jobs, budget, verify_only=False, timeout=None):
    fd, jpath = tempfile.mkstemp(suffix=".json", prefix="jeste_jobs_")
    os.close(fd)
    rpath = jpath.replace("jobs", "res")
    with open(jpath, "w") as f:
        json.dump(jobs, f)
    args = ["res://tests/worker.gd", "--", jpath, rpath, "--budget", str(budget)]
    if verify_only:
        args.append("--verify-only")
    try:
        p = godot(args, timeout=timeout)
    except subprocess.TimeoutExpired:
        p = None
    results = []
    if os.path.exists(rpath):
        with open(rpath) as f:
            try:
                results = json.load(f)
            except Exception:
                results = []
    done = {r["id"] for r in results}
    for j in jobs:
        if j["id"] not in done:
            err = "worker crashed/timeout"
            if p is not None:
                tail = [l for l in (p.stdout + p.stderr).splitlines() if "ERROR" in l][-3:]
                if tail:
                    err += ": " + " | ".join(tail)
            results.append({"id": j["id"], "ok": False, "error": err})
    for pth in (jpath, rpath):
        if os.path.exists(pth):
            os.remove(pth)
    return results


def solve_all(tasks, jobs_n, budget, resolve, basic=False):
    sol_dir = BASIC_DIR if basic else SOL_DIR
    os.makedirs(sol_dir, exist_ok=True)
    results = {}
    verify, need = [], []
    for t in tasks:
        c = None if resolve else load_cached(t, sol_dir)
        if basic and not (c and c.get("solution")) and not resolve:
            c = load_cached(t)   # the regular route may already avoid advanced tech
            if c:
                c = dict(c, hash=None)
        if c and c.get("hash") == t["hash"] and c.get("solution"):
            j = dict(t, basic=basic)
            j["solution"] = c["solution"]
            verify.append(j)
        else:
            j = dict(t, basic=basic)
            if c and c.get("solution"):
                j["solution"] = c["solution"]   # may still replay fine
            need.append(j)
    if verify:
        print(f"  replaying {len(verify)} cached solutions...")
        chunks = [verify[i::jobs_n] for i in range(min(jobs_n, len(verify)))]
        with ThreadPoolExecutor(len(chunks)) as ex:
            for res in ex.map(lambda ch: run_worker(ch, budget, verify_only=True, timeout=1800), chunks):
                for r in res:
                    results[r["id"]] = r
        for t in verify:
            r = results.get(t["id"])
            if not r or not r.get("ok"):
                j = dict(t)
                j.pop("solution", None)
                need.append(j)
    if need:
        print(f"  solving {len(need)} tasks with {jobs_n} workers...")
        # one task per worker invocation keeps memory bounded and spreads load
        t0 = time.time()
        with ThreadPoolExecutor(jobs_n) as ex:
            futs = {ex.submit(run_worker, [j], budget, False, 3600): j for j in need}
            n = 0
            for fut in futs:
                res = fut.result()
                for r in res:
                    results[r["id"]] = r
                    n += 1
                    status = "ok" if r.get("ok") else "FAIL"
                    print(f"    [{n}/{len(need)}] {r['id']}: {status} {r.get('frames', 0)}f {r.get('ms', 0)}ms {r.get('error', '')}")
        print(f"  solved in {time.time() - t0:.1f}s")
    # persist
    by_id = {t["id"]: t for t in tasks}
    for tid, r in results.items():
        if r.get("ok") and r.get("solution"):
            t = by_id[tid]
            with open(sol_path(tid, sol_dir), "w") as f:
                json.dump({"hash": t["hash"], "solution": r["solution"], "exit_target": r.get("exit_target"),
                           "collected": r.get("collected", []), "frames": r.get("frames")}, f)
    return results


def analyse(data, results):
    """Graph proof per chapter. Returns report dict."""
    report = {}
    tasks_by = {}
    for t in data["tasks"]:
        tasks_by.setdefault(t["chapter"], []).append(t)
    for chs, g in data["chapters"].items():
        n = int(chs)
        rooms = g["rooms"]
        edges = {}   # node -> list of (node2, task)
        collect = {}  # node -> task (collect)
        for t in tasks_by.get(n, []):
            r = results.get(t["id"])
            if not r or not r.get("ok"):
                continue
            node = (t["room"], t["spawn"])
            if t["kind"] == "path":
                if t["exit"] == "end":
                    edges.setdefault(node, []).append(("END", t))
                else:
                    sp = next(e["spawn"] for e in rooms[t["room"]]["exits"] if e["target"] == t["exit"])
                    edges.setdefault(node, []).append(((t["exit"], sp), t))
            else:
                collect[node] = (t, r)
        start = (g["start"], 0)
        reach = {start}
        q = deque([start])
        while q:
            u = q.popleft()
            for v, _ in edges.get(u, []):
                if v not in reach:
                    reach.add(v)
                    if v != "END":
                        q.append(v)
        # nodes that can reach END
        rev = {}
        for u, lst in edges.items():
            for v, _ in lst:
                rev.setdefault(v, []).append(u)
        to_end = {"END"}
        q = deque(["END"])
        while q:
            u = q.popleft()
            for v in rev.get(u, []):
                if v not in to_end:
                    to_end.add(v)
                    q.append(v)
        end_ok = "END" in reach
        col_status = {}
        for rid, info in rooms.items():
            for cid in info["collectibles"]:
                col_status[cid] = False
        for node, (t, r) in collect.items():
            if node not in reach:
                continue
            ex = r.get("exit_target")
            if ex == "end":
                nxt = "END"
            else:
                sp = next((e["spawn"] for e in rooms[node[0]]["exits"] if e["target"] == ex), None)
                nxt = (ex, sp)
            if nxt in to_end:
                for cid in r.get("collected", []):
                    if cid in col_status:
                        col_status[cid] = True
        unreached_rooms = sorted({rid for rid in rooms if not any(node[0] == rid for node in reach if node != "END")})
        report[chs] = {"name": g["name"], "end_reachable": end_ok, "collectibles": col_status,
                       "unreached_rooms": unreached_rooms, "edges": edges, "collect": collect,
                       "reach": reach, "to_end": to_end, "start": start, "rooms": rooms}
    return report


def build_route(rep):
    """Shortest chapter route (in room visits) that collects every proven
    collectible and reaches the end. BFS over (node, collected-set) states."""
    edges, collect, rooms = rep["edges"], rep["collect"], rep["rooms"]
    goal = frozenset(c for c, ok in rep["collectibles"].items() if ok)

    def exit_node(node, r):
        ex = r.get("exit_target")
        if ex == "end":
            return "END"
        sp = next((e["spawn"] for e in rooms[node[0]]["exits"] if e["target"] == ex), None)
        return (ex, sp)

    start = (rep["start"], frozenset())
    prev = {start: None}
    q = deque([start])
    found = None
    while q:
        st = q.popleft()
        node, got = st
        if node == "END":
            if got >= goal:
                found = st
                break
            continue
        moves = []
        for v, t in edges.get(node, []):
            moves.append(((v, got), {"room": node[0], "inputs": rep["results"][t["id"]]["solution"], "task": t["id"]}))
        c = collect.get(node)
        if c:
            t, r = c
            got2 = got | (frozenset(r.get("collected", [])) & goal)
            if got2 != got:
                moves.append(((exit_node(node, r), got2), {"room": node[0], "inputs": r["solution"], "task": t["id"]}))
        for nst, chunk in moves:
            if nst[0] is None or (nst[0] != "END" and nst[0][1] is None):
                continue
            if nst not in prev:
                prev[nst] = (st, chunk)
                q.append(nst)
    if not found:
        return []
    chunks = []
    st = found
    while prev[st] is not None:
        st, chunk = prev[st]
        chunks.append(chunk)
    return list(reversed(chunks))


def build_hints(rep, results):
    """Route Ghost hints: for every reachable (room, spawn), the basic-moveset
    traversal toward the exit with the fewest rooms left to the chapter end."""
    edges = rep["edges"]
    rev = {}
    for u, lst in edges.items():
        for v, _ in lst:
            rev.setdefault(v, []).append(u)
    dist = {"END": 0}
    q = deque(["END"])
    while q:
        u = q.popleft()
        for v in rev.get(u, []):
            if v not in dist:
                dist[v] = dist[u] + 1
                q.append(v)
    hints = {}
    for node, lst in edges.items():
        if node not in rep["reach"]:
            continue
        best = min(lst, key=lambda e: (dist.get(e[0], 1 << 20), results[e[1]["id"]].get("frames", 0)))
        t = best[1]
        hints[f"{node[0]}:{node[1]}"] = {"exit": t["exit"], "inputs": results[t["id"]]["solution"]}
    missing = sorted(f"{n[0]}:{n[1]}" for n in rep["reach"] if n != "END" and f"{n[0]}:{n[1]}" not in hints)
    return hints, missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chapters", nargs="*", type=int, default=[])
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) - 2))
    ap.add_argument("--budget", type=int, default=200000)
    ap.add_argument("--no-e2e", action="store_true")
    ap.add_argument("--resolve", action="store_true")
    args = ap.parse_args()

    t0 = time.time()
    print("== Listing tasks")
    data = list_tasks(args.chapters)
    for e in data["errors"]:
        print("  LEVEL ERROR:", e)
    print(f"  {len(data['tasks'])} tasks across {len(data['chapters'])} chapters")
    print("== Solving / verifying rooms")
    results = solve_all(data["tasks"], args.jobs, args.budget, args.resolve)
    print("== Proving chapters")
    report = analyse(data, results)
    all_ok = not data["errors"]
    lines = ["# Jeste level verification report", "",
             f"Generated {time.strftime('%Y-%m-%d %H:%M:%S')}", ""]
    routes = {}
    for chs in sorted(report, key=int):
        rep = report[chs]
        rep["results"] = results
        cols = rep["collectibles"]
        got = sum(1 for v in cols.values() if v)
        ok = rep["end_reachable"] and got == len(cols)
        all_ok &= ok
        status = "PASS" if ok else "FAIL"
        print(f"  Chapter {chs} {rep['name']}: end {'reachable' if rep['end_reachable'] else 'NOT reachable'}, collectibles {got}/{len(cols)} -> {status}")
        lines.append(f"## Chapter {chs}: {rep['name']} - {status}")
        lines.append(f"- End reachable from start: {'yes' if rep['end_reachable'] else 'NO'}")
        lines.append(f"- Collectibles proven: {got}/{len(cols)}")
        for cid, v in sorted(cols.items()):
            if not v:
                print(f"     missing: {cid}")
                lines.append(f"  - NOT PROVEN: `{cid}`")
        if rep["unreached_rooms"]:
            lines.append(f"- Rooms not reachable: {', '.join(rep['unreached_rooms'])}")
            print(f"     unreached rooms: {rep['unreached_rooms']}")
        lines.append("")
        if rep["end_reachable"]:
            routes[chs] = build_route(rep)
    rob = sorted(((r.get("robustness", 1.0), r["id"], r.get("frames", 0)) for r in results.values() if r.get("ok")))
    if rob:
        lines.append("## Route robustness")
        lines.append("Share of random 1-frame timing slips that still clear each task (lower = tighter timing).")
        lines.append("")
        lines.append("| task | frames | robustness |")
        lines.append("|---|---|---|")
        for v, tid, fr in rob:
            lines.append(f"| `{tid}` | {fr} | {v * 100:.0f}% |")
        lines.append("")
        avg = sum(v for v, _, _ in rob) / len(rob)
        print(f"  route robustness: average {avg * 100:.0f}%, tightest {rob[0][1]} {rob[0][0] * 100:.0f}%")
    print("== Basic moveset only (no supers, hypers or wall-bounces)")
    basic_results = solve_all(data["tasks"], args.jobs, args.budget, args.resolve, basic=True)
    basic_report = analyse(data, basic_results)
    lines.append("## Basic moveset only")
    lines.append("The same proofs with supers, hypers and wall-bounces forbidden (the game never teaches them).")
    lines.append("")
    for chs in sorted(basic_report, key=int):
        rep = basic_report[chs]
        cols = rep["collectibles"]
        got = sum(1 for v in cols.values() if v)
        ok = rep["end_reachable"] and got == len(cols)
        all_ok &= ok
        print(f"  Chapter {chs} {rep['name']}: end {'reachable' if rep['end_reachable'] else 'NOT reachable'}, collectibles {got}/{len(cols)} -> {'PASS' if ok else 'FAIL'}")
        lines.append(f"- Chapter {chs} {rep['name']}: end {'reachable' if rep['end_reachable'] else 'NOT reachable'}, collectibles {got}/{len(cols)} - {'PASS' if ok else 'FAIL'}")
        for cid, v in sorted(cols.items()):
            if not v:
                print(f"     missing: {cid}")
                lines.append(f"  - NOT PROVEN: `{cid}`")
    lines.append("")
    hints = {}
    for chs in sorted(basic_report, key=int):
        h, missing = build_hints(basic_report[chs], basic_results)
        hints[chs] = h
        if missing:
            all_ok = False
            print(f"  Chapter {chs}: no Route Ghost hint for {missing}")
            lines.append(f"- Chapter {chs}: no Route Ghost hint for {', '.join(missing)} (FAIL)")
    n_hints = sum(len(h) for h in hints.values())
    print(f"  Route Ghost hints: {n_hints} room entries")
    lines.append(f"- Route Ghost hints: {n_hints} room entries (`data/hints.json`), each a proven basic-moveset traversal.")
    lines.append("")
    if not args.chapters:
        with open(os.path.join(ROOT, "data", "hints.json"), "w") as f:
            json.dump(hints, f, separators=(",", ":"), sort_keys=True)
    hp = godot(["res://tests/hints_check.gd"], timeout=600)
    hout = hp.stdout + hp.stderr
    hok = "HINTS PASS" in hout and hp.returncode == 0
    all_ok &= hok
    for l in hout.splitlines():
        if l.startswith("HINTS FAIL:"):
            print("  " + l)
            lines.append(f"  - {l}")
    print(f"  data/hints.json replays: {'PASS' if hok else 'FAIL'}")
    lines.append(f"- `data/hints.json` replays to every exit: {'PASS' if hok else 'FAIL'}")
    print("== Save files (atomic writes, backup and recovery)")
    sp = godot(["res://tests/save_check.gd"], timeout=300)
    sout = sp.stdout + sp.stderr
    sok = "SAVES PASS" in sout and sp.returncode == 0
    all_ok &= sok
    for l in sout.splitlines():
        if l.startswith("SAVES FAIL:") or l.startswith("SAVES NOTE:"):
            print("  " + l)
    sdetail = next((l for l in sout.splitlines() if l.startswith("SAVES PASS") or l.startswith("SAVES FAIL ")), "no result")
    print(f"  {'PASS' if sok else 'FAIL'} - {sdetail}")
    lines.append(f"- Save files survive damaged writes (`tests/save_check.gd`): {'PASS' if sok else 'FAIL'} ({sdetail})")
    lines.append("")
    brob = sorted(((-r.get("lethal", 0.0), r.get("robustness", 1.0), r["id"], r.get("frames", 0)) for r in basic_results.values()
                   if r.get("ok") and "_to_" in r["id"]))
    if brob:
        lines.append("### Room traversals, basic-moveset routes")
        lines.append("Each room's route from entry to exit (no collectibles) with the basic moveset, under random 1-frame "
                     "timing slips. *Lethal* is the share of slips that kill: how close the route runs to hazards, and the "
                     "difficulty proxy used for tuning. *Clears* is the share of inserted-frame slips that still finish "
                     "without correction (an open-loop replay can't steer the way a player does).")
        lines.append("")
        lines.append("| task | frames | lethal | clears |")
        lines.append("|---|---|---|---|")
        for nl, v, tid, fr in brob:
            lines.append(f"| `{tid}` | {fr} | {-nl * 100:.0f}% | {v * 100:.0f}% |")
        lines.append("")
        avg = sum(-nl for nl, _, _, _ in brob) / len(brob)
        print(f"  basic traversal lethality: average {avg * 100:.0f}%, highest {brob[0][2]} {-brob[0][0] * 100:.0f}%")
    for r in basic_results.values():
        if not r.get("ok"):
            print(f"  unsolved (basic): {r['id']}: {r.get('error', '')}")
    failed = [r for r in results.values() if not r.get("ok")] + [dict(r, id=r["id"] + " (basic)") for r in basic_results.values() if not r.get("ok")]
    if failed:
        lines.append("## Unsolved tasks")
        for r in sorted(failed, key=lambda r: r["id"]):
            lines.append(f"- `{r['id']}`: {r.get('error', '')}")
            print(f"  unsolved: {r['id']}: {r.get('error', '')}")
        lines.append("")
    full_run = not args.chapters
    if routes and full_run:
        # (partial runs must not clobber the full route file used by tools/demo.gd)
        with open(os.path.join(ROOT, "tests", "routes.json"), "w") as f:
            json.dump(routes, f)
    if not args.no_e2e and routes:
        print("== End-to-end playthroughs (real Level scene)")
        rpath = os.path.join(tempfile.gettempdir(), "jeste_routes.json")
        opath = os.path.join(tempfile.gettempdir(), "jeste_e2e.json")
        with open(rpath, "w") as f:
            json.dump({k: [{"room": c["room"], "inputs": c["inputs"]} for c in v] for k, v in routes.items()}, f)
        if os.path.exists(opath):
            os.remove(opath)
        p = subprocess.run([GODOT, "--headless", "--path", ROOT, "res://tests/e2e.tscn", "--", rpath, opath],
                           capture_output=True, text=True, timeout=1200, env=ENV)
        e2e = {}
        if os.path.exists(opath):
            with open(opath) as f:
                e2e = json.load(f)
        else:
            print(p.stdout[-2000:], p.stderr[-2000:])
        script_errors = [l for l in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in l]
        if script_errors:
            all_ok = False
            print("  SCRIPT ERRORS during end-to-end run:")
            for l in script_errors[:10]:
                print("   ", l)
        lines.append("## End-to-end playthroughs")
        if script_errors:
            lines.append(f"- {len(script_errors)} script errors during the run (FAIL)")
        for chs in sorted(routes, key=int):
            r = e2e.get(chs)
            rep = report[chs]
            expected = {c for c, v in rep["collectibles"].items() if v}
            if not r:
                ok = False
                msg = "no result"
            else:
                missing = expected - set(r.get("collected", [])) - {c for c in expected if ":golden" in c}
                golden_needed = any(":golden" in c for c in expected)
                ok = r.get("ok") and not missing and r.get("deaths", 1) == 0 and (r.get("golden") or not golden_needed)
                msg = f"{len(r.get('rooms', []))} room visits, {r.get('frames', 0)} frames ({r.get('frames', 0) / 60:.1f}s), deaths {r.get('deaths')}, collected {len(set(r.get('collected', [])))}"
                if golden_needed:
                    msg += ", golden " + ("carried to the end" if r.get("golden") else "LOST")
                if missing:
                    msg += f", MISSING {sorted(missing)}"
                if r.get("error"):
                    msg += f", error: {r['error']}"
            all_ok &= ok
            print(f"  Chapter {chs}: {'PASS' if ok else 'FAIL'} - {msg}")
            lines.append(f"- Chapter {chs}: {'PASS' if ok else 'FAIL'} - {msg}")
        lines.append("")
    if not args.no_e2e:
        print("== Menu flow (title, options, chapter select, pause, assist, results, credits)")
        p = subprocess.run([GODOT, "--headless", "--path", ROOT, "--fixed-fps", "60", "res://tests/ui_flow.tscn"],
                           capture_output=True, text=True, timeout=600, env=ENV)
        out = p.stdout + p.stderr
        errs = [l for l in out.splitlines() if "SCRIPT ERROR" in l]
        ok = "UI FLOW PASS" in out and not errs
        all_ok &= ok
        detail = next((l for l in out.splitlines() if l.startswith("UI FLOW")), "no result")
        if errs:
            detail += f" ({len(errs)} script errors: {errs[0]})"
        print(f"  {'PASS' if ok else 'FAIL'} - {detail}")
        lines.append("## Menu flow")
        lines.append(f"- {'PASS' if ok else 'FAIL'} - {detail}")
        lines.append("")
    lines.append(f"**Overall: {'PASS' if all_ok else 'FAIL'}**  ({time.time() - t0:.0f}s)")
    report_path = os.path.join(ROOT, "tests", "REPORT.md") if full_run else os.path.join(tempfile.gettempdir(), "jeste_REPORT_partial.md")
    with open(report_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"== Overall: {'PASS' if all_ok else 'FAIL'} ({time.time() - t0:.0f}s) - see {os.path.relpath(report_path, ROOT) if full_run else report_path}")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
