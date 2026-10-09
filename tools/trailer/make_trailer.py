#!/usr/bin/env python3
"""
Builds the Jeste feature trailer, the README teaser loop, the trailer poster
and the README screenshots from the real game.

    python3 tools/trailer/make_trailer.py                  # every stage
    python3 tools/trailer/make_trailer.py capture plates   # just some stages
    python3 tools/trailer/make_trailer.py --force capture  # re-record footage

Stages
  capture      Godot's Movie Maker records every source shot at the native
               320x180 / 60 fps through tools/trailer/rec.tscn: full chapter
               runs driven by the solver-proven routes in tests/routes.json,
               cutscenes, a staged death, menus and the title / end cards,
               all at Options > Graphics: Ultra (Movie Maker renders offline,
               so every frame is kept whatever the step costs).
               Music is muted in the captures, sound effects are kept.
  plates       tools/trailer/plates.tscn renders the caption plates with the
               game's pixel font and UI colours.
  trailer      Every beat is cut from the captures, scaled 6x (nearest
               neighbour) to 1920x1080 and captioned; ffmpeg slides and fades
               the plates in. Beats are joined with cuts, fades and pixelate
               transitions on the music grid, the game's own music is laid
               underneath, ducked under the sound effects and loudness
               normalised (-14 LUFS). A near-lossless master is then encoded
               in two passes to fit 40 MB. Output: docs/media/jeste_trailer.mp4
  qc           Frame grabs of every beat, black / frozen frame detection and
               audio levels, written to build/trailer/qc/.
  teaser       docs/media/teaser.gif, an 8 second loop for the README.
  poster       docs/media/trailer_poster.png, the clickable trailer still.
  screenshots  docs/media/screenshot_*.png (1920x1080).

Work files go to build/trailer/ (ignored by git and by Godot). Needs Godot 4.6+
on PATH (or $GODOT) with a display, and ffmpeg with libx264, aac and gif.
"""
import inspect
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT", "godot")
WORK = os.path.join(ROOT, "build", "trailer")
REC = os.path.join(WORK, "rec")
PLATES = os.path.join(WORK, "plates")
SEG = os.path.join(WORK, "seg")
QC = os.path.join(WORK, "qc")
MEDIA = os.path.join(ROOT, "docs", "media")
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
TRAILER = os.path.join(MEDIA, "jeste_trailer.mp4")
FPS = 60
W, H = 1920, 1080
SFX_VOLUME = 0.45      # in-game sound volume for captures (default 0.8 clips when busy)
FIDELITY = 3           # Options > Graphics for every capture: 0 Low .. 3 Ultra
MAX_MB = 39.0


def sh(cmd):
    """Run a command at low priority so long encodes don't starve other work."""
    p = subprocess.run(["nice", "-n", "10"] + cmd, capture_output=True, text=True)
    if p.returncode != 0:
        print(" ".join(cmd)[:2000])
        print(p.stdout[-3000:], p.stderr[-3000:])
        sys.exit("command failed")
    return p


# ---------------------------------------------------------------- sources

def route_frames(ch):
    with open(os.path.join(ROOT, "tests", "routes.json")) as f:
        chunks = json.load(f)[str(ch)]
    n = sum(int(c) for chunk in chunks for _, c in re.findall(r"(\d+):(\d+)", chunk["inputs"]))
    return n + 45 * len(chunks) + 300


def sources():
    src = {}
    for ch in range(9):
        src["ch%d" % ch] = {"kind": "route", "ch": ch, "frames": route_frames(ch)}
    src.update({
        "story_pro": {"kind": "route", "ch": 0, "from": 0, "to": 1, "story": ["pro_arrive"], "frames": 1900},
        "story_ch3": {"kind": "route", "ch": 3, "from": 0, "to": 1, "story": ["ch3_arrive"], "frames": 400},
        "death": {"kind": "route", "ch": 1, "from": 3, "to": 4, "cut": 75, "append": "0:240", "frames": 300},
        # Mira stops; pause > Assist > Route Ghost, back, resume: the ghost runs the room.
        "assist": {"kind": "route", "ch": 4, "from": 2, "to": 3, "cut": 20, "append": "0:900", "frames": 720,
                   "calls": [[40, "press:pause"], [62, "press:down"], [76, "press:down"], [92, "press:confirm"]]
                   + [[112 + 13 * i, "press:down"] for i in range(5)] + [[190, "press:confirm"], [228, "press:back"],
                                                                          [252, "press:pause"]]},
        # Mira stops; pause > Options > Graphics, stepped Ultra > Low > Ultra.
        "graphics": {"kind": "route", "ch": 1, "from": 2, "to": 3, "cut": 40, "append": "0:900", "frames": 520,
                     "calls": [[50, "press:pause"]] + [[70 + 12 * i, "press:down"] for i in range(3)]
                     + [[110, "press:confirm"]] + [[130 + 12 * i, "press:down"] for i in range(4)]
                     + [[200, "press:left"], [245, "press:left"], [290, "press:left"],
                        [340, "press:right"], [385, "press:right"], [430, "press:right"]]},
        # chapter select, then the checkpoint picker of The Hollow Stage
        "select": {"kind": "scene", "scene": "res://scenes/chapter_select.tscn", "save": "progress", "frames": 520,
                   "presses": [[90, "left"], [150, "left"], [215, "confirm"], [290, "right"], [350, "right"],
                               [410, "right"]]},
        "title_screen": {"kind": "scene", "scene": "res://scenes/main.tscn", "frames": 360},
        "title_card": {"kind": "card", "mode": "title", "frames": 330},
        "end_card": {"kind": "card", "mode": "end", "frames": 450},
        "poster": {"kind": "card", "mode": "poster", "frames": 240},
    })
    for s in src.values():
        s.setdefault("settings", {})["sfx"] = SFX_VOLUME
        s["settings"]["fidelity"] = FIDELITY
    return src


def frame_path(name, i):
    return os.path.join(REC, name, "f%08d.png" % i)


def capture(force=False):
    os.makedirs(REC, exist_ok=True)
    for name, spec in sources().items():
        d = os.path.join(REC, name)
        spec_txt = json.dumps(spec, sort_keys=True)
        stamp = os.path.join(d, "spec.json")
        if not force and os.path.exists(stamp) and open(stamp).read() == spec_txt:
            continue
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        cmd = ["nice", "-n", "10", GODOT, "--path", ROOT, "--rendering-method", "mobile", "--resolution", "320x180",
               "--fixed-fps", str(FPS), "--write-movie", os.path.join(d, "f.png"),
               "res://tools/trailer/rec.tscn", "--", spec_txt]
        # A capture can stall at startup on a busy machine: give each try a generous
        # limit (a busy machine records about 4 frames a second) and retry twice.
        for attempt in range(3):
            print("  capturing", name, "(retry %d)" % attempt if attempt else "")
            for f in os.listdir(d):
                os.remove(os.path.join(d, f))
            try:
                p = subprocess.run(cmd, capture_output=True, text=True, timeout=120 + spec["frames"] * 0.6)
                if p.returncode == 0:
                    break
                print(p.stdout[-2000:], p.stderr[-2000:])
            except subprocess.TimeoutExpired:
                print("  timed out")
        else:
            sys.exit("capture %s failed" % name)
        n = len([f for f in os.listdir(d) if f.endswith(".png")])
        if n < spec["frames"]:
            sys.exit("capture %s: only %d frames" % (name, n))
        with open(stamp, "w") as f:
            f.write(spec_txt)


# ---------------------------------------------------------------- captions

PLATE_TEXT = [
    # id, kicker, title, line
    ("story", "THE STORY", "A STORY OF GRIEF AND LAUGHTER", "Meet the odd, kind folk of Mount Jeste"),
    ("climb", "THE CLIMB", "RUN, JUMP AND CLIMB", "Wall-jump up anything - mind your stamina"),
    ("dash", "THE CLIMB", "DASH IN EIGHT DIRECTIONS", "Then chain it into supers and hypers"),
    ("springs", "CH 1 - LANTERN TOWN", "JACK-IN-THE-BOX SPRINGS", "...and boards that crumble underfoot"),
    ("gems", "CH 1 - LANTERN TOWN", "DASH GEMS", "Refill your dash in mid-air"),
    ("curtains", "CHAPTERS 2, 5 & 7", "VELVET CURTAINS", "Dash in to glide through - mirrors too"),
    ("chase", "CH 2 - THE HOLLOW STAGE", "OUTRUN THE GRIN", "Your reflection retraces every move"),
    ("masks", "CH 3 - THE GRAND CARNIVAL", "COMEDY & TRAGEDY MASKS", "Every dash swaps which blocks are solid"),
    ("keys", "CH 3 - THE GRAND CARNIVAL", "KEYS, GATES & CRACKED WALLS", "Dash through walls to find secrets"),
    ("gondolas", "CH 4 - WHISTLING RIDGE", "GONDOLAS AND HOWLING WIND", "Ride the cables, lean into the gale"),
    ("balloons", "CH 5 - MIRROR CATHEDRAL", "CIRCUS BALLOONS", "Catch one, then launch any direction"),
    ("bumpers", "CH 6 - UNDERTOW", "PINBALL BUMPERS", "A blast of speed - and a fresh dash"),
    ("twin", "CH 6 - UNDERTOW", "TWIN GEMS", "Two dashes until you touch the ground"),
    ("summit", "CH 7 - THE SUMMIT", "TWO DASHES, EVERY TRICK", "The final climb throws it all at you"),
    ("berries", "COLLECTIBLES", "61 SUNBERRIES TO HUNT", "Winged ones fly off if you dash"),
    ("bells", "SECRETS", "SEVEN JESTER BELLS", "Hidden behind fake and cracked walls"),
    ("death", "PRECISION PLATFORMING", "FAIL FAST, RETRY INSTANTLY", "Every death puts you back in a second"),
    ("assist", "PLAY YOUR WAY", "ASSIST MODE & ROUTE GHOST", "A ghost runs a proven way through"),
    ("graphics", "OPTIONS", "FOUR GRAPHICS STEPS", "Ultra adds terrain shadows"),
    ("select", "PROGRESSION", "NINE CHAPTERS, 69 ROOMS", "Restart from any checkpoint you reached"),
    ("proven", "UNDER THE HOOD", "EVERY ROOM PROVEN BEATABLE", "The solver played every climb shown here"),
]
BIG_TEXT = [("w_climb", "CLIMB."), ("w_dash", "DASH."), ("w_fall", "FALL."), ("w_up", "GET BACK UP.")]


def plates():
    os.makedirs(PLATES, exist_ok=True)
    spec = [{"id": i, "kicker": k, "title": t, "line": l} for i, k, t, l in PLATE_TEXT]
    spec += [{"id": i, "big": t} for i, t in BIG_TEXT]
    path = os.path.join(PLATES, "plates.json")
    with open(path, "w") as f:
        json.dump(spec, f, indent=1)
    sh([GODOT, "--path", ROOT, "--rendering-method", "mobile", "--resolution", "320x180",
        "res://tools/trailer/plates.tscn", "--", path, PLATES])


# ---------------------------------------------------------------- the edit

HALF_BAR = 60.0 / 128.0 * 2.0      # "ch7" plays at 128 bpm
CHASE_BAR = 60.0 / 150.0 * 4.0     # "chase" plays at 150 bpm
TRANS = {"cut": 1, "fade": 12, "pixelize": 24, "fadewhite": 9, "fadeblack": 30}

# Cold open: the best moments, cut on the bars of "chase".
COLD = [("ch6", 1420), ("ch7", 1636), ("ch4", 1628), ("ch7", 2068)]

# Feature beats on the "ch7" half-bar grid:
#   (plate, half bars, anchor, transition into the next beat, [(source, start frame, frames|None)])
FEATURES = [
    ("story", 6, "br", "pixelize", [("story_pro", 1530, 165), ("story_ch3", 40, None)]),
    ("climb", 4, "tl", "fade", [("ch0", 250, None)]),
    ("dash", 4, "tl", "pixelize", [("ch0", 1222, 125), ("ch1", 975, None)]),
    ("springs", 4, "br", "fade", [("ch1", 345, None)]),
    ("gems", 4, "bl", "pixelize", [("ch1", 790, None)]),
    ("curtains", 4, "tl", "fade", [("ch2", 925, 90), ("ch5", 1002, 70), ("ch7", 578, None)]),
    ("chase", 5, "tl", "pixelize", [("ch2", 1490, None)]),
    ("masks", 4, "tr", "fade", [("ch3", 226, None)]),
    ("keys", 4, "br", "pixelize", [("ch3", 70, 125), ("ch3", 870, None)]),
    ("gondolas", 5, "bl", "pixelize", [("ch4", 440, 120), ("ch4", 1612, None)]),
    ("balloons", 4, "bl", "pixelize", [("ch5", 262, None)]),
    ("bumpers", 4, "bl", "fade", [("ch6", 205, None)]),
    ("twin", 4, "tl", "pixelize", [("ch6", 1625, None)]),
    ("summit", 4, "tl", "pixelize", [("ch7", 225, None)]),
    ("berries", 4, "bl", "fade", [("ch1", 1712, 110), ("ch1", 2950, None)]),
    ("bells", 4, "tl", "pixelize", [("ch1", 1340, None)]),
    ("death", 4, "tl", "fade", [("death", 36, None)]),
    ("assist", 6, "tl", "fade", [("assist", 100, 110), ("assist", 405, None)]),
    ("graphics", 5, "tl", "fade", [("graphics", 178, None)]),
    ("select", 5, "bc", "fade", [("select", 140, None)]),
    ("proven", 4, "tr", "fadewhite", [("ch7", 1950, None)]),
]

# Beats whose caption waits (seconds) for a menu to close, so it doesn't cover it.
PLATE_IN = {"assist": 1.9}

# Escalation montage: two cuts per bar of "chase", a word per bar.
MONTAGE = [
    ("w_climb", [("ch4", 1468), ("ch3", 1322)]),
    ("w_dash", [("ch6", 735), ("ch7", 1482)]),
    ("w_fall", [("death", 120), ("death", 196)]),
    ("w_up", [("ch7", 2200), ("ch7", 2250)]),
]

TITLE_SECS = 5.0
END_SECS = 7.0
COLD_START = 8 * CHASE_BAR           # where in "chase" the cold open starts
MONTAGE_START = 12 * CHASE_BAR


def build_edit():
    """Returns the beat list with frame-exact start, length and tail (overlap)."""
    beats = []
    t = 0
    for src, start in COLD:
        n = round(CHASE_BAR * FPS)
        beats.append({"id": "cold%d" % len(beats), "start": t, "frames": n, "trans": "cut",
                      "clips": [(src, start, None)], "section": "cold"})
        t += n
    n = round(TITLE_SECS * FPS)
    beats.append({"id": "title", "start": t, "frames": n, "trans": "pixelize",
                  "clips": [("title_card", 0, None)], "section": "title"})
    t += n
    feat0 = t
    hb = 0
    for plate, halves, anchor, trans, clips in FEATURES:
        s = feat0 + round(hb * HALF_BAR * FPS)
        hb += halves
        e = feat0 + round(hb * HALF_BAR * FPS)
        beats.append({"id": plate, "start": s, "frames": e - s, "trans": trans, "clips": clips,
                      "plate": plate, "anchor": anchor, "section": "features", "plate_in": PLATE_IN.get(plate, 0.3)})
    t = feat0 + round(hb * HALF_BAR * FPS)
    for word, clips in MONTAGE:
        for k, (src, start) in enumerate(clips):
            n = round(CHASE_BAR * FPS / 2)
            beats.append({"id": "%s%d" % (word, k), "start": t, "frames": n, "trans": "cut",
                          "clips": [(src, start, None)], "section": "montage",
                          "big": word, "big_static": k > 0})
            t += n
    n = round(END_SECS * FPS)
    beats.append({"id": "end", "start": t, "frames": n, "trans": None,
                  "clips": [("end_card", 0, None)], "section": "end"})
    for b in beats:
        b["tail"] = TRANS[b["trans"]] if b["trans"] else 0
    return beats


def plate_meta():
    with open(os.path.join(PLATES, "plates_meta.json")) as f:
        return json.load(f)


def caption_filters(beat, base, next_in, meta, total):
    """ffmpeg overlay chain sliding the beat's plates in and out."""
    graph, inputs = [], []
    secs = beat["frames"] / FPS
    if beat.get("plate"):
        body = meta[beat["plate"] + "_body"]
        kick = meta[beat["plate"] + "_kick"]
        m = 42
        dx, dy = kick["x"] - body["x"], kick["y"] - body["y"]
        right = beat["anchor"][1] == "r"
        bx = W - m - body["w"] if right else ((W - body["w"]) // 2 if beat["anchor"][1] == "c" else m)
        by = m - dy if beat["anchor"][0] == "t" else H - m - body["h"]
        if beat["anchor"] == "bc":
            by = H - 24 - body["h"]      # sits over the menu's key hints rather than half-covering them
        a_in, a_out = beat.get("plate_in", 0.3), secs - 0.45
        sign = 1 if right else -1
        for part, x0, y0, delay in (("body", bx, by, 0.0), ("kick", bx + dx, by + dy, 0.12)):
            idx = next_in + len(inputs) // 8   # 8 args per plate input
            inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.4f" % total,
                       "-i", os.path.join(PLATES, "%s_%s.png" % (beat["plate"], part))]
            ti = a_in + delay
            xexpr = "%d+%d*pow(1-clip((t-%.3f)/0.4,0,1),3)+%d*pow(clip((t-%.3f)/0.3,0,1),2)" % (
                x0, sign * 90, ti, sign * 40, a_out)
            graph.append("[%d:v]format=rgba,fade=t=in:st=%.3f:d=0.3:alpha=1,fade=t=out:st=%.3f:d=0.3:alpha=1[p%s]"
                         % (idx, ti, a_out, part))
            graph.append("[%s][p%s]overlay=x='%s':y=%d:eval=frame[%s_%s]" % (base, part, xexpr, y0, base, part))
            base = "%s_%s" % (base, part)
    if beat.get("big"):
        big = meta[beat["big"] + "_big"]
        idx = next_in + len(inputs) // 8   # 8 args per plate input
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.4f" % total,
                   "-i", os.path.join(PLATES, "%s_big.png" % beat["big"])]
        x0, y0 = (W - big["w"]) // 2, 150
        # the word lands on the bar's first cut and stays through the second
        yexpr = str(y0) if beat["big_static"] else "%d+40*pow(1-clip(t/0.25,0,1),3)" % y0
        fade_in = "" if beat["big_static"] else ",fade=t=in:st=0:d=0.15:alpha=1"
        graph.append("[%d:v]format=rgba%s[pbig]" % (idx, fade_in))
        graph.append("[%s][pbig]overlay=x=%d:y='%s':eval=frame[%s_big]" % (base, x0, yexpr, base))
        base += "_big"
    return graph, inputs, base


def render_segment(i, beat, meta):
    out_v = os.path.join(SEG, "%02d_%s.mp4" % (i, beat["id"]))
    out_a = os.path.join(SEG, "%02d_%s.wav" % (i, beat["id"]))
    total = beat["frames"] + beat["tail"]
    beat["seg_v"], beat["seg_a"], beat["seg_frames"] = out_v, out_a, total
    # skip beats whose spec, plates and source captures are unchanged
    key = json.dumps([beat, {k: v for k, v in meta.items() if k.split("_")[0] in (beat.get("plate"), beat.get("big"))},
                      [open(os.path.join(REC, c[0], "spec.json")).read() for c in beat["clips"]],
                      inspect.getsource(caption_filters), inspect.getsource(render_segment)], sort_keys=True)
    stamp = out_v + ".json"
    if os.path.exists(out_a) and os.path.exists(stamp) and open(stamp).read() == key:
        return
    remaining = total
    args, graph, vlabels, alabels = [], [], [], []
    for k, (src, start, n) in enumerate(beat["clips"]):
        n = remaining if (n is None or k == len(beat["clips"]) - 1) else n
        remaining -= n
        if not os.path.exists(frame_path(src, start + n - 1)):
            sys.exit("beat %s: %s has no frame %d" % (beat["id"], src, start + n - 1))
        vi, ai = 2 * k, 2 * k + 1
        args += ["-framerate", str(FPS), "-start_number", str(start), "-i", os.path.join(REC, src, "f%08d.png")]
        args += ["-ss", "%.5f" % (start / FPS), "-t", "%.5f" % (n / FPS), "-i", os.path.join(REC, src, "f.wav")]
        graph.append("[%d:v]trim=end_frame=%d,setpts=PTS-STARTPTS[v%d]" % (vi, n, k))
        graph.append("[%d:a]aresample=48000,aformat=channel_layouts=stereo,apad,atrim=0:%.5f,asetpts=PTS-STARTPTS,"
                     "afade=t=in:d=0.01,afade=t=out:st=%.5f:d=0.01[a%d]" % (ai, n / FPS, n / FPS - 0.01, k))
        vlabels.append("[v%d]" % k)
        alabels.append("[a%d]" % k)
    n_in = 2 * len(beat["clips"])
    graph.append("%sconcat=n=%d:v=1:a=0,scale=%d:%d:flags=neighbor,setsar=1,format=rgb24[base]" % (
        "".join(vlabels), len(vlabels), W, H))
    graph.append("%sconcat=n=%d:v=0:a=1[aout]" % ("".join(alabels), len(alabels)))
    cg, cin, last = caption_filters(beat, "base", n_in, meta, total / FPS)
    graph += cg
    args += cin
    graph.append("[%s]format=yuv420p[vout]" % last)
    sh(["ffmpeg", "-y", "-v", "error"] + args + ["-filter_complex", ";".join(graph),
        "-map", "[vout]", "-frames:v", str(total), "-r", str(FPS), "-c:v", "libx264", "-preset", "veryfast",
        "-crf", "8", out_v, "-map", "[aout]", "-c:a", "pcm_s16le", out_a])
    with open(stamp, "w") as f:
        f.write(key)


def music_pieces(beats):
    """(track, offset in track, timeline start, duration, fade in, fade out, gain dB)"""
    by = {b["section"]: b for b in reversed(beats)}
    first = {}
    for b in beats:
        first.setdefault(b["section"], b)
    t_title = first["title"]["start"] / FPS
    t_feat = first["features"]["start"] / FPS
    t_mont = first["montage"]["start"] / FPS
    t_end = first["end"]["start"] / FPS
    end = (by["end"]["start"] + by["end"]["frames"]) / FPS
    return [
        ("chase", COLD_START, 0.0, t_title, 0.02, 0.06, 0.0),
        ("title", 0.0, t_title, t_feat - t_title + 0.6, 0.25, 0.6, -1.0),
        ("ch7", 0.0, t_feat, t_mont - t_feat, 0.5, 0.12, 0.0),
        ("chase", MONTAGE_START, t_mont, t_end - t_mont, 0.0, 0.05, 0.0),
        ("title", 0.0, t_end, end - t_end, 0.05, 3.0, -1.0),
    ], end


def trailer():
    meta = plate_meta()
    beats = build_edit()
    os.makedirs(SEG, exist_ok=True)
    for i, b in enumerate(beats):
        print("  beat %2d %-10s %6.2fs  %5.2fs" % (i, b["id"], b["start"] / FPS, b["frames"] / FPS))
        render_segment(i, b, meta)
    pieces, end = music_pieces(beats)
    # --- audio, in three passes (one graph with asplit + sidechain can stall):
    # 1. sound effects bus: every beat's capture audio at its start time
    args, graph, sfx = [], [], []
    for i, b in enumerate(beats):
        args += ["-i", b["seg_a"]]
        fin = TRANS[beats[i - 1]["trans"]] / FPS if i > 0 and beats[i - 1]["trans"] else 0.01
        fout = b["tail"] / FPS if b["tail"] > 1 else 0.01
        dur = b["seg_frames"] / FPS
        gain = -3.0 if b["section"] in ("cold", "montage") else 0.0
        graph.append("[%d:a]afade=t=in:d=%.3f,afade=t=out:st=%.3f:d=%.3f,volume=%.1fdB,adelay=%d:all=1[s%d]"
                     % (i, fin, dur - fout, fout, gain, round(b["start"] / FPS * 1000), i))
        sfx.append("[s%d]" % i)
    graph.append("%samix=inputs=%d:normalize=0:dropout_transition=0,apad=whole_dur=%.4f,atrim=0:%.4f[out]"
                 % ("".join(sfx), len(sfx), end, end))
    sfx_wav = os.path.join(WORK, "sfx.wav")
    sh(["ffmpeg", "-y", "-v", "error"] + args + ["-filter_complex", ";".join(graph), "-map", "[out]",
                                                  "-c:a", "pcm_f32le", sfx_wav])
    # 2. music bed: the game's tracks, faded and placed on the timeline
    args, graph, mus = [], [], []
    for k, (track, off, start, dur, fin, fout, gain) in enumerate(pieces):
        args += ["-stream_loop", "2", "-i", os.path.join(MUSIC, track + ".ogg")]
        graph.append("[%d:a]aresample=48000,atrim=%.4f:%.4f,asetpts=PTS-STARTPTS,afade=t=in:d=%.3f,"
                     "afade=t=out:st=%.4f:d=%.3f,volume=%.1fdB,adelay=%d:all=1[m%d]"
                     % (k, off, off + dur, fin, dur - fout, fout, gain, round(start * 1000), k))
        mus.append("[m%d]" % k)
    graph.append("%samix=inputs=%d:normalize=0:dropout_transition=0,apad=whole_dur=%.4f,atrim=0:%.4f[out]"
                 % ("".join(mus), len(mus), end, end))
    music_wav = os.path.join(WORK, "music.wav")
    sh(["ffmpeg", "-y", "-v", "error"] + args + ["-filter_complex", ";".join(graph), "-map", "[out]",
                                                  "-c:a", "pcm_f32le", music_wav])
    # 3. duck the music under the sound effects and mix
    mix = os.path.join(WORK, "mix.wav")
    sh(["ffmpeg", "-y", "-v", "error", "-i", music_wav, "-i", sfx_wav, "-i", sfx_wav, "-filter_complex",
        "[0:a][1:a]sidechaincompress=threshold=0.04:ratio=4:attack=8:release=260:makeup=1[duck];"
        "[duck][2:a]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.95:level=disabled[out]",
        "-map", "[out]", "-c:a", "pcm_s24le", mix])
    p = sh(["ffmpeg", "-hide_banner", "-i", mix, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json",
            "-f", "null", "-"])
    i = p.stderr.rindex("{")
    m = json.loads(p.stderr[i:p.stderr.index("}", i) + 1])
    norm = ("loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:"
            "offset=%s:linear=true" % (m["input_i"], m["input_tp"], m["input_lra"], m["input_thresh"],
                                       m["target_offset"]))
    # --- video: join the beats with transitions on their cut points
    args, graph = [], []
    for b in beats:
        args += ["-i", b["seg_v"]]
    prev = "0:v"
    for i in range(1, len(beats)):
        tr = beats[i - 1]["trans"]
        kind = "fade" if tr == "cut" else tr
        graph.append("[%s][%d:v]xfade=transition=%s:duration=%.5f:offset=%.5f[x%d]"
                     % (prev, i, kind, TRANS[tr] / FPS, beats[i]["start"] / FPS, i))
        prev = "x%d" % i
    graph.append("[%s]fade=t=out:st=%.3f:d=0.8,format=yuv420p[vout]" % (prev, end - 0.8))
    args += ["-i", mix]
    graph.append("[%d:a]%s,aresample=48000[aout]" % (len(beats), norm))
    os.makedirs(MEDIA, exist_ok=True)
    # near-lossless master first, so the delivery encode can be redone quickly
    master = os.path.join(WORK, "master.mkv")
    sh(["ffmpeg", "-y", "-v", "error"] + args + ["-filter_complex", ";".join(graph), "-map", "[vout]",
        "-map", "[aout]", "-t", "%.4f" % end, "-r", str(FPS), "-c:v", "libx264", "-preset", "veryfast",
        "-crf", "6", "-pix_fmt", "yuv420p", "-c:a", "pcm_s24le", master])
    encode(master, end)
    with open(os.path.join(WORK, "edit.json"), "w") as f:
        json.dump([{k: b[k] for k in ("id", "start", "frames", "trans", "section")} for b in beats], f, indent=1)
    print("  %s: %.1fs, %.1f MB" % (os.path.relpath(TRAILER, ROOT), end, os.path.getsize(TRAILER) / 1e6))


def encode(master, end):
    """Two-pass H.264 to the size budget. Light deblocking and psy tuning keep the 6x pixels
    crisp ("tune animation" smooths pixel art too much)."""
    kbps = int((MAX_MB * 8000 / end - 192) * 0.98)
    log = os.path.join(WORK, "x264pass")
    common = ["-i", master, "-map", "0:v", "-map", "0:a", "-c:v", "libx264", "-preset", "slower",
              "-profile:v", "high", "-pix_fmt", "yuv420p", "-g", "120", "-b:v", "%dk" % kbps,
              "-x264-params", "deblock=-2,-2:aq-mode=3:psy-rd=1.0,0.15",
              "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart"]
    sh(["ffmpeg", "-y", "-v", "error"] + common + ["-pass", "1", "-passlogfile", log, "-f", "mp4", os.devnull])
    sh(["ffmpeg", "-y", "-v", "error"] + common + ["-pass", "2", "-passlogfile", log, TRAILER])


# ---------------------------------------------------------------- checks

def qc():
    os.makedirs(QC, exist_ok=True)
    with open(os.path.join(WORK, "edit.json")) as f:
        beats = json.load(f)
    shots = []
    for b in beats:
        # one grab with the caption fully in, one late in the beat
        for k, frac in enumerate((0.45, 0.85)):
            t = (b["start"] + b["frames"] * frac) / FPS
            out = os.path.join(QC, "%s_%d.png" % (b["id"], k))
            sh(["ffmpeg", "-y", "-v", "error", "-ss", "%.3f" % t, "-i", TRAILER, "-frames:v", "1",
                "-vf", "scale=640:360", out])
            shots.append(out)
    for n in range(0, len(shots), 12):
        sh(["magick", "montage"] + shots[n:n + 12] + ["-tile", "4x", "-geometry", "+2+2",
                                                      os.path.join(QC, "sheet_%02d.png" % (n // 12))])
    probe = sh(["ffprobe", "-v", "error", "-show_entries",
                "stream=codec_name,width,height,r_frame_rate,sample_rate,channels:format=duration,size",
                "-of", "default=nw=1", TRAILER]).stdout
    det = sh(["ffmpeg", "-hide_banner", "-i", TRAILER, "-vf", "blackdetect=d=0.25:pix_th=0.06,freezedetect=n=0.001:d=1.0",
              "-af", "volumedetect,ebur128=framelog=quiet", "-f", "null", "-"]).stderr
    keep = [l.strip() for l in det.splitlines()
            if any(k in l for k in ("black_start", "freeze_start", "freeze_duration", "mean_volume", "max_volume", " I:", "LRA:", "Peak:"))]
    report = probe + "\n".join(keep) + "\n"
    with open(os.path.join(QC, "report.txt"), "w") as f:
        f.write(report)
    print(report)


# ---------------------------------------------------------------- README media

TEASER = [("ch7", 1636, 96), ("ch6", 205, 96), ("ch2", 1520, 96), ("ch4", 1628, 96), ("ch5", 262, 96)]


def teaser():
    os.makedirs(MEDIA, exist_ok=True)
    args, graph, labels = [], [], []
    for k, (src, start, n) in enumerate(TEASER):
        args += ["-framerate", str(FPS), "-start_number", str(start), "-i", os.path.join(REC, src, "f%08d.png")]
        graph.append("[%d:v]trim=end_frame=%d,setpts=PTS-STARTPTS[v%d]" % (k, n, k))
        labels.append("[v%d]" % k)
    graph.append("%sconcat=n=%d:v=1:a=0,fps=30,scale=960:540:flags=neighbor,split[a][b];"
                 "[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle"
                 % ("".join(labels), len(labels)))
    out = os.path.join(MEDIA, "teaser.gif")
    sh(["ffmpeg", "-y", "-v", "error"] + args + ["-filter_complex", ";".join(graph), "-loop", "0", out])
    print("  teaser.gif %.1f MB" % (os.path.getsize(out) / 1e6))


def upscale(src_png, out):
    os.makedirs(MEDIA, exist_ok=True)
    sh(["ffmpeg", "-y", "-v", "error", "-i", src_png, "-vf", "scale=%d:%d:flags=neighbor" % (W, H), out])


def poster():
    upscale(frame_path("poster", 220), os.path.join(MEDIA, "trailer_poster.png"))


SCREENSHOTS = [
    ("title", "title_screen", 300),
    ("story", "story_pro", 1690),
    ("dash", "ch1", 852),
    ("curtains", "ch2", 948),
    ("chase", "ch2", 1600),
    ("cathedral", "ch5", 1020),
    ("gondola", "ch4", 1650),
    ("undertow", "ch6", 240),
    ("summit", "ch7", 2108),
    ("chapter_select", "select", 200),
    ("checkpoints", "select", 470),
    ("route_ghost", "assist", 300),
    ("graphics", "graphics", 470),
]


def screenshots():
    for name, src, f in SCREENSHOTS:
        out = os.path.join(MEDIA, "screenshot_%s.png" % name)
        upscale(frame_path(src, f), out)
        print("  %s %.2f MB" % (os.path.basename(out), os.path.getsize(out) / 1e6))


STAGES = {"capture": None, "plates": plates, "trailer": trailer, "qc": qc, "teaser": teaser,
          "poster": poster, "screenshots": screenshots}

if __name__ == "__main__":
    argv = [a for a in sys.argv[1:] if a != "--force"]
    todo = argv or list(STAGES)
    for st in todo:
        print("== " + st)
        if st == "capture":
            capture("--force" in sys.argv)
        else:
            STAGES[st]()
