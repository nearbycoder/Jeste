#!/usr/bin/env python3
"""
Generates all Jeste sound effects and music as WAV files using only the
Python standard library (a tiny chiptune synthesizer + hand-written scores).

    python3 tools/gen_audio.py
"""
import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUS_DIR = os.path.join(ROOT, "assets", "audio", "music")


def write_wav(path, samples, rate=RATE):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = min(1.0, 0.92 / peak)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))


# ---------------------------------------------------------------- oscillators

def osc(kind, phase, duty=0.5):
    p = phase % 1.0
    if kind == "square":
        return 1.0 if p < duty else -1.0
    if kind == "tri":
        return 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p
    if kind == "saw":
        return 2.0 * p - 1.0
    if kind == "sine":
        return math.sin(2 * math.pi * p)
    return 0.0


def tone(dur, f0, f1=None, kind="square", vol=0.5, attack=0.005, release=0.05, duty=0.5, vibrato=0.0, curve=1.0):
    n = int(dur * RATE)
    out = []
    phase = 0.0
    f1 = f0 if f1 is None else f1
    for i in range(n):
        t = i / RATE
        k = (i / max(1, n - 1)) ** curve
        f = f0 + (f1 - f0) * k
        if vibrato:
            f *= 1.0 + 0.01 * vibrato * math.sin(2 * math.pi * 6 * t)
        phase += f / RATE
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if t > dur - release:
            env *= max(0.0, (dur - t) / release)
        out.append(osc(kind, phase, duty) * vol * env)
    return out


def noise(dur, vol=0.5, attack=0.002, release=0.1, lp=0.5, seed=1):
    rnd = random.Random(seed)
    n = int(dur * RATE)
    out = []
    y = 0.0
    for i in range(n):
        t = i / RATE
        x = rnd.uniform(-1, 1)
        y += (x - y) * lp
        env = min(1.0, t / attack) if attack > 0 else 1.0
        env *= max(0.0, 1.0 - t / dur) ** 1.5
        if t > dur - release:
            env *= max(0.0, (dur - t) / release)
        out.append(y * vol * env)
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    n = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * n
    for t, o in zip(tracks, offsets):
        s = int(o * RATE)
        for i, v in enumerate(t):
            out[s + i] += v
    return out


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def silence(d):
    return [0.0] * int(d * RATE)


def note_freq(name):
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n = names[name[0]]
    i = 1
    if len(name) > 2 and name[1] in "#b":
        n += 1 if name[1] == "#" else -1
        i = 2
    elif len(name) == 3:
        pass
    octave = int(name[i:])
    midi = 12 * (octave + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


# ---------------------------------------------------------------- sound effects

def make_sfx():
    S = {}
    S["jump"] = tone(0.12, 300, 620, "square", 0.35, duty=0.25, release=0.06)
    S["walljump"] = mix(tone(0.12, 260, 640, "square", 0.3, duty=0.25), noise(0.06, 0.25, lp=0.6))
    S["land"] = noise(0.08, 0.35, lp=0.25, seed=3)
    S["dash"] = mix(noise(0.22, 0.45, lp=0.7, seed=5), tone(0.18, 900, 200, "saw", 0.18, curve=0.5))
    S["refill"] = tone(0.08, 880, 1320, "tri", 0.25)
    S["gem"] = seq(tone(0.06, 988, kind="square", vol=0.25, duty=0.125), tone(0.06, 1319, kind="square", vol=0.25, duty=0.125), tone(0.14, 1976, kind="square", vol=0.22, duty=0.125, release=0.1))
    S["spring"] = mix(tone(0.25, 200, 900, "square", 0.3, duty=0.3, vibrato=4, curve=0.6), noise(0.05, 0.2))
    S["crumble"] = noise(0.3, 0.35, lp=0.15, seed=9)
    S["break"] = mix(noise(0.45, 0.6, lp=0.3, seed=11), tone(0.2, 120, 50, "square", 0.3))
    S["key"] = seq(tone(0.07, 1047, kind="tri", vol=0.3), tone(0.12, 1568, kind="tri", vol=0.3, release=0.1))
    S["door"] = mix(tone(0.3, 180, 90, "square", 0.3, duty=0.5), noise(0.3, 0.3, lp=0.2))
    S["mask"] = seq(tone(0.05, 660, kind="square", vol=0.2, duty=0.25), tone(0.08, 440, kind="square", vol=0.2, duty=0.25))
    S["balloon"] = tone(0.18, 400, 700, "sine", 0.4, vibrato=8)
    S["bumper"] = mix(tone(0.15, 600, 300, "square", 0.3, duty=0.5), tone(0.15, 900, 450, "tri", 0.3))
    S["zip_start"] = tone(0.2, 150, 400, "saw", 0.25)
    S["zip_hit"] = mix(noise(0.25, 0.5, lp=0.35, seed=13), tone(0.15, 110, 60, "square", 0.35))
    S["curtain"] = mix(noise(0.3, 0.25, lp=0.08, seed=15), tone(0.3, 500, 800, "sine", 0.2, vibrato=10))
    S["berry_touch"] = tone(0.08, 1200, 1500, "tri", 0.2)
    S["berry"] = seq(*[tone(0.07, note_freq(n), kind="square", vol=0.25, duty=0.25) for n in ["C6", "E6", "G6"]], tone(0.25, note_freq("C7"), kind="square", vol=0.22, duty=0.25, release=0.2))
    S["flee"] = tone(0.3, 800, 1600, "tri", 0.25, vibrato=12)
    bell = []
    for h, v in [(1.0, 0.4), (2.76, 0.18), (5.4, 0.1), (8.9, 0.05)]:
        bell.append(tone(1.6, 660 * h, kind="sine", vol=v, attack=0.002, release=1.4, curve=1.0))
    S["bell"] = mix(*bell)
    S["grab"] = noise(0.04, 0.2, lp=0.4, seed=17)
    S["death"] = mix(tone(0.4, 500, 60, "square", 0.35, duty=0.4, curve=0.7), noise(0.35, 0.3, lp=0.4, seed=19))
    S["complete"] = seq(*[tone(0.12, note_freq(n), kind="square", vol=0.25, duty=0.25) for n in ["G5", "C6", "E6"]], tone(0.6, note_freq("G6"), kind="square", vol=0.22, duty=0.25, release=0.4, vibrato=3))
    S["menu_move"] = tone(0.04, 880, kind="square", vol=0.15, duty=0.25)
    S["menu_select"] = seq(tone(0.04, 660, kind="square", vol=0.18, duty=0.25), tone(0.07, 990, kind="square", vol=0.18, duty=0.25))
    S["text_next"] = tone(0.04, 1100, kind="tri", vol=0.18)
    S["blip"] = tone(0.035, 520, kind="square", vol=0.12, duty=0.25, release=0.02)
    for k, v in S.items():
        write_wav(os.path.join(SFX_DIR, k + ".wav"), v)
    print(f"sfx: {len(S)}")


# ---------------------------------------------------------------- music
# Scores: each voice is a list of (note, beats) tuples; "-" is a rest.

CHORD_TONES = {
    "C": ["C", "E", "G"], "Cm": ["C", "Eb", "G"], "D": ["D", "F#", "A"], "Dm": ["D", "F", "A"],
    "E": ["E", "G#", "B"], "Em": ["E", "G", "B"], "F": ["F", "A", "C"], "Fm": ["F", "Ab", "C"],
    "G": ["G", "B", "D"], "Gm": ["G", "Bb", "D"], "A": ["A", "C#", "E"], "Am": ["A", "C", "E"],
    "Bb": ["Bb", "D", "F"], "Bm": ["B", "D", "F#"], "Eb": ["Eb", "G", "Bb"], "Ab": ["Ab", "C", "Eb"],
    "F#m": ["F#", "A", "C#"], "C#m": ["C#", "E", "G#"], "B": ["B", "D#", "F#"],
}


def render_voice(notes, bpm, kind, vol, duty=0.5, release=0.04, vibrato=0.0, legato=0.92):
    beat = 60.0 / bpm
    out = []
    for n, b in notes:
        d = b * beat
        if n == "-":
            out += silence(d)
        else:
            f = note_freq(n)
            t = tone(d * legato, f, kind=kind, vol=vol, duty=duty, release=min(release, d * 0.5), vibrato=vibrato)
            out += t + silence(d - len(t) / RATE)
    return out


def arp(chords, bpm, octave, pattern, kind="square", vol=0.12, duty=0.25, step=0.5, beats_per_chord=4):
    notes = []
    for ch in chords:
        tones = CHORD_TONES[ch]
        steps = int(beats_per_chord / step)
        for i in range(steps):
            idx = pattern[i % len(pattern)]
            o = octave + idx // 3
            notes.append((f"{tones[idx % 3]}{o}", step))
    return render_voice(notes, bpm, kind, vol, duty=duty, release=0.03, legato=0.8)


def bass(chords, bpm, octave, rhythm, kind="tri", vol=0.3, beats_per_chord=4):
    notes = []
    for ch in chords:
        root = CHORD_TONES[ch][0]
        fifth = CHORD_TONES[ch][2]
        t = 0.0
        i = 0
        while t < beats_per_chord - 1e-6:
            b, which = rhythm[i % len(rhythm)]
            nm = root if which == "r" else (fifth if which == "f" else "-")
            notes.append((f"{nm}{octave}" if nm != "-" else "-", b))
            t += b
            i += 1
    return render_voice(notes, bpm, kind, vol, legato=0.85)


def drums(bars, bpm, pattern, vol=0.25, beats_per_bar=4):
    # pattern: string per 8th note: k = kick, s = snare, h = hat, . = rest
    beat = 60.0 / bpm
    step = beat / 2
    out = []
    kick = tone(0.12, 140, 45, "sine", vol * 1.4, curve=0.4)
    snare = noise(0.14, vol * 0.9, lp=0.7, seed=21)
    hat = noise(0.04, vol * 0.4, lp=0.95, seed=23)
    steps_per_bar = beats_per_bar * 2
    for b in range(bars):
        for i in range(steps_per_bar):
            c = pattern[i % len(pattern)]
            seg = silence(step)
            if c == "k":
                seg = mix(seg, kick)[: len(seg)]
            elif c == "s":
                seg = mix(seg, snare)[: len(seg)]
            elif c == "h":
                seg = mix(seg, hat)[: len(seg)]
            out += seg
    return out


def melody(text):
    """'A4:1 C5:0.5 - :1' -> list of (note, beats)"""
    out = []
    for tok in text.split():
        n, b = tok.split(":")
        out.append((n, float(b)))
    return out


def song(name, bpm, chords, mel, bass_oct, arp_oct, arp_pat, bass_rhythm, drum_pat=None, mel_kind="square",
         mel_duty=0.5, mel_vol=0.16, arp_kind="square", arp_vol=0.09, bass_vol=0.26, beats_per_chord=4,
         pad=False, vibrato=2.0, repeats=2):
    chords = chords * repeats
    m = render_voice(melody(mel) * repeats, bpm, mel_kind, mel_vol, duty=mel_duty, vibrato=vibrato, release=0.06)
    a = arp(chords, bpm, arp_oct, arp_pat, kind=arp_kind, vol=arp_vol, beats_per_chord=beats_per_chord)
    b = bass(chords, bpm, bass_oct, bass_rhythm, vol=bass_vol, beats_per_chord=beats_per_chord)
    tracks = [m, a, b]
    if drum_pat:
        tracks.append(drums(len(chords) * beats_per_chord // (4 if beats_per_chord >= 4 else 3), bpm, drum_pat,
                            beats_per_bar=4 if beats_per_chord >= 4 else 3))
    if pad:
        pads = []
        beat = 60.0 / bpm
        for ch in chords:
            d = beats_per_chord * beat
            tt = [tone(d, note_freq(f"{n}4"), kind="sine", vol=0.05, attack=0.3, release=0.4) for n in CHORD_TONES[ch]]
            pads += mix(*tt)
        tracks.append(pads)
    n = min(len(t) for t in tracks)
    out = mix(*[t[:n] for t in tracks])
    write_wav(os.path.join(MUS_DIR, name + ".wav"), out)
    print(f"music: {name} {n / RATE:.1f}s")


def make_music():
    # Title: playful but wistful (D major), the "mountain that laughs back" theme
    title_mel = ("F#5:1 A5:0.5 B5:0.5 A5:1 F#5:1 E5:1 D5:0.5 E5:0.5 F#5:2 "
                 "G5:1 B5:0.5 C#6:0.5 B5:1 G5:1 F#5:1 E5:1 D5:2 "
                 "B4:1 D5:0.5 E5:0.5 F#5:1 A5:1 G5:1 F#5:0.5 E5:0.5 D5:2 "
                 "E5:1 F#5:0.5 G5:0.5 A5:1 C#5:1 D5:3 -:1")
    song("title", 96, ["D", "G", "Bm", "A", "G", "D", "Em", "A"], title_mel, 2, 4, [0, 1, 2, 3, 2, 1, 0, 1],
         [(1, "r"), (1, "f"), (1, "r"), (1, "f")], mel_kind="tri", mel_vol=0.22, arp_vol=0.07, pad=True)
    song("map", 84, ["G", "Em", "C", "D"], " ".join(title_mel.split()[:17]), 2, 4, [0, 2, 1, 2],
         [(2, "r"), (2, "f")], mel_kind="sine", mel_vol=0.2, arp_kind="tri", arp_vol=0.08, pad=True)
    # Prologue: warm, hopeful (G major)
    pro_mel = ("B4:1 D5:1 G5:1.5 F#5:0.5 E5:1 D5:1 B4:2 C5:1 E5:1 A5:1.5 G5:0.5 F#5:2 -:2 "
               "B4:1 D5:1 G5:1.5 A5:0.5 B5:1 A5:1 G5:2 E5:1 F#5:1 G5:1 A5:1 G5:3 -:1")
    song("prologue", 100, ["G", "C", "Am", "D", "G", "C", "D", "G"], pro_mel, 2, 4, [0, 1, 2, 1],
         [(1, "r"), (0.5, "f"), (0.5, "r"), (1, "f"), (1, "r")], drum_pat="h.h.h.h.", mel_kind="tri", mel_vol=0.22)
    # Chapter 1: Lantern Town - quiet night, A minor, plucky
    ch1_mel = ("A4:0.5 C5:0.5 E5:1 D5:0.5 C5:0.5 B4:1 G4:1 A4:2 -:1 "
               "F4:0.5 A4:0.5 C5:1 B4:0.5 A4:0.5 G4:2 E4:2 -:1 "
               "A4:0.5 C5:0.5 E5:1 G5:1 F5:0.5 E5:0.5 D5:2 -:1 "
               "C5:0.5 D5:0.5 E5:1 D5:1 B4:1 A4:3 -:1")
    song("ch1", 108, ["Am", "F", "C", "G", "Am", "F", "G", "Am"], ch1_mel, 2, 4, [0, 2, 1, 2, 0, 2, 1, 3],
         [(1.5, "r"), (0.5, "r"), (1, "f"), (1, "-")], drum_pat="k.h.s.h.", mel_duty=0.25)
    # Chapter 2: Hollow Stage - dreamy music box waltz (3/4), E minor
    ch2_mel = ("B5:1 G5:1 E5:1 F#5:2 D#5:1 E5:2 B4:1 C5:1 E5:1 G5:1 "
               "A5:1 F#5:1 D#5:1 E5:3 G5:1 F#5:1 E5:1 D#5:1 B4:1 E5:1")
    song("ch2", 92, ["Em", "B", "Em", "C", "Am", "B", "Em", "Em"], ch2_mel, 2, 5, [0, 1, 2], [(1, "r"), (2, "f")],
         mel_kind="sine", mel_vol=0.24, arp_kind="tri", arp_vol=0.08, beats_per_chord=3, pad=True, vibrato=5)
    # Chapter 3: Grand Carnival - oom-pah march, C major w/ chromatic wink
    ch3_mel = ("G4:0.5 G#4:0.5 A4:0.5 C5:0.5 E5:1 D5:1 C5:0.5 A4:0.5 G4:1 E4:2 "
               "F4:0.5 F#4:0.5 G4:0.5 A4:0.5 D5:1 C5:1 B4:0.5 G4:0.5 A4:1 B4:2 "
               "G4:0.5 G#4:0.5 A4:0.5 C5:0.5 E5:1 G5:1 F5:0.5 E5:0.5 D5:1 C5:2 "
               "D5:0.5 E5:0.5 F5:1 E5:1 D5:1 C5:3 -:1")
    song("ch3", 126, ["C", "Am", "F", "G", "C", "A", "Dm", "G"], ch3_mel, 2, 4, [1, 2, 1, 2],
         [(1, "r"), (1, "f"), (1, "r"), (1, "f")], drum_pat="k.s.k.s.", mel_duty=0.5, mel_vol=0.15)
    # Chapter 4: Whistling Ridge - driving, F major
    ch4_mel = ("C5:0.5 F5:0.5 A5:1 G5:0.5 F5:0.5 E5:1 C5:1 D5:0.5 E5:0.5 F5:2 -:1 "
               "Bb4:0.5 D5:0.5 F5:1 E5:0.5 D5:0.5 C5:1 A4:1 G4:3 -:1 "
               "C5:0.5 F5:0.5 A5:1 C6:1 Bb5:0.5 A5:0.5 G5:2 -:1 "
               "F5:0.5 G5:0.5 A5:1 G5:1 E5:1 F5:3 -:1")
    song("ch4", 138, ["F", "C", "Dm", "Bb", "F", "C", "Bb", "C"], ch4_mel, 2, 4, [0, 1, 2, 1, 0, 1, 2, 3],
         [(0.5, "r"), (0.5, "r"), (0.5, "f"), (0.5, "r")], drum_pat="khskkhsh", mel_duty=0.25)
    # Chapter 5: Mirror Cathedral - slow organ, D minor
    ch5_mel = ("D5:2 F5:2 A5:3 G5:1 F5:2 E5:2 D5:4 C5:2 E5:2 G5:3 F5:1 E5:2 C#5:2 D5:4")
    song("ch5", 72, ["Dm", "Bb", "Gm", "A", "F", "C", "Gm", "A"], ch5_mel, 2, 4, [0, 1, 2, 3, 2, 1],
         [(4, "r")], mel_kind="saw", mel_vol=0.1, arp_kind="sine", arp_vol=0.1, pad=True, vibrato=4)
    # Chapter 6: Undertow - deep and slow, B minor
    ch6_mel = ("F#5:2 D5:1 B4:1 C#5:2 A4:2 B4:3 -:1 G5:2 F#5:1 E5:1 D5:2 C#5:2 B4:4")
    song("ch6", 78, ["Bm", "G", "D", "A", "Bm", "G", "Em", "F#m"], ch6_mel, 1, 4, [0, 2, 4, 2],
         [(2, "r"), (2, "f")], mel_kind="sine", mel_vol=0.22, arp_kind="tri", arp_vol=0.08, pad=True, vibrato=6)
    # Chapter 7: Summit - triumphant, D major, the title theme grown up
    ch7_mel = title_mel
    song("ch7", 132, ["D", "G", "Bm", "A", "G", "D", "Em", "A"], ch7_mel, 2, 4, [0, 1, 2, 3, 2, 1, 0, 1],
         [(0.5, "r"), (0.5, "r"), (0.5, "f"), (0.5, "r")], drum_pat="khskkhsh", mel_duty=0.25, mel_vol=0.17, pad=True)
    # Epilogue + credits
    song("epilogue", 90, ["D", "G", "Bm", "A", "G", "D", "Em", "A"], title_mel, 2, 4, [0, 2, 1, 2],
         [(2, "r"), (2, "f")], mel_kind="tri", mel_vol=0.22, arp_kind="tri", arp_vol=0.07, pad=True)
    song("credits", 90, ["D", "G", "Bm", "A", "G", "D", "Em", "A"], title_mel, 2, 4, [0, 1, 2, 1],
         [(1, "r"), (1, "f"), (1, "r"), (1, "f")], drum_pat="h.h.h.h.", mel_kind="tri", mel_vol=0.22, pad=True,
         repeats=3)
    # Chase: urgent
    chase_mel = ("E5:0.5 E5:0.5 G5:0.5 E5:0.5 A5:0.5 G5:0.5 E5:0.5 D5:0.5 "
                 "E5:0.5 E5:0.5 G5:0.5 E5:0.5 B5:1 A5:1 "
                 "C6:0.5 B5:0.5 A5:0.5 G5:0.5 A5:0.5 G5:0.5 E5:0.5 D5:0.5 "
                 "E5:0.5 G5:0.5 E5:0.5 D#5:0.5 E5:2")
    song("chase", 150, ["Em", "Em", "C", "B"], chase_mel, 2, 4, [0, 1, 2, 1], [(0.5, "r"), (0.5, "r"), (0.5, "f"), (0.5, "r")],
         drum_pat="kkskkksk", mel_duty=0.25, mel_vol=0.15, repeats=4)


if __name__ == "__main__":
    make_sfx()
    make_music()
