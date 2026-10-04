#!/usr/bin/env python3
"""
Generates all of Jeste's sound effects, music and ambience.

    pip install numpy        (a venv works fine)
    python3 tools/gen_audio.py [names...]

Music and ambience loops are rendered as seamless loops and encoded to Ogg
Vorbis with ffmpeg; short sound effects are written as 44.1 kHz WAV.
The instruments live in tools/synth.py.
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402
from synth import SR, hz, midi, spectral, tarr, adsr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUS_DIR = os.path.join(ROOT, "assets", "audio", "music")
RNG = np.random.default_rng(1234)

# ---------------------------------------------------------------- harmony helpers

QUALITY = {
    "": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7], "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14], "dim": [0, 3, 6],
    "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9],
}


def chord_pcs(sym):
    root = sym[0]
    i = 1
    if len(sym) > 1 and sym[1] in "#b":
        root += sym[1]
        i = 2
    q = sym[i:]
    base = S.midi(root + "4") % 12
    return base, QUALITY[q]


def voicing(sym, center=60, n=None):
    """Close voicing of the chord around `center` (midi)."""
    base, iv = chord_pcs(sym)
    notes = []
    for k in iv:
        pc = (base + k) % 12
        m = center - 6 + ((pc - (center - 6)) % 12)
        notes.append(m)
    notes = sorted(notes)
    if n:
        while len(notes) < n:
            notes.append(notes[len(notes) - len(iv)] + 12)
    return notes


def root_midi(sym, octave=2):
    base, _ = chord_pcs(sym)
    return 12 * (octave + 1) + base


def fifth_midi(sym, octave=2):
    base, iv = chord_pcs(sym)
    return 12 * (octave + 1) + base + iv[2]


# ---------------------------------------------------------------- song builder

class Song:
    def __init__(self, name, bpm, bars, beats_per_bar=4, reverb=(2.4, 0.9, 0.5), master=0.85):
        self.name = name
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.bpb = beats_per_bar
        self.bars = bars
        self.n = int(round(bars * beats_per_bar * self.spb * SR))
        self.bus = S.Bus(self.n, loop=True)
        self.ir = S.reverb_ir(*reverb)
        self.master = master

    def at(self, beat):
        return beat * self.spb * SR

    def note(self, inst, beat, dur, pitch, vel=0.8, gain=1.0, pan=0.0, send=0.25, human=0.006, **kw):
        if pitch in ("-", None):
            return
        f = hz(pitch) if isinstance(pitch, str) else hz(int(pitch))
        v = float(np.clip(vel * RNG.uniform(0.92, 1.05), 0.05, 1.0))
        sig = inst(f, max(dur * self.spb, 0.02), v, **kw)
        self.bus.add(sig, self.at(beat) + RNG.uniform(-human, human) * SR, gain, pan, send)

    def melody(self, inst, text, start=0.0, transpose=0, **kw):
        """'E5:1 G5:0.5 -:1 C5+E5:2' (beats). Returns the end beat."""
        b = start
        for tok in text.split():
            p, d = tok.rsplit(":", 1)
            d = float(d)
            if p != "-":
                for q in p.split("+"):
                    self.note(inst, b, d * 0.95, S.midi(q) + transpose, **kw)
            b += d
        return b

    def chords(self, inst, prog, start=0.0, beats=4.0, center=60, hits=None, n=None, **kw):
        """Sustained (or rhythmic, via hits=[(offset, dur)]) chord voicings."""
        for i, c in enumerate(prog):
            b0 = start + i * beats
            vs = voicing(c, center, n)
            for off, d in (hits or [(0.0, beats)]):
                for m in vs:
                    self.note(inst, b0 + off, d, m, **kw)

    def arp(self, inst, prog, pattern, step=0.5, start=0.0, beats=4.0, center=60, **kw):
        """pattern: indices into the voicing (+ up an octave with values >= len)."""
        for i, c in enumerate(prog):
            vs = voicing(c, center, 4)
            k = 0
            b = 0.0
            while b < beats - 1e-6:
                idx = pattern[k % len(pattern)]
                if idx is not None:
                    m = vs[idx % len(vs)] + 12 * (idx // len(vs))
                    self.note(inst, start + i * beats + b, step * 0.9, m, **kw)
                b += step
                k += 1

    def bassline(self, inst, prog, rhythm, start=0.0, beats=4.0, octave=2, **kw):
        """rhythm: [(offset, dur, 'r'|'f'|'o'|'3')] per chord."""
        for i, c in enumerate(prog):
            base, iv = chord_pcs(c)
            r = 12 * (octave + 1) + base
            for off, d, w in rhythm:
                m = {"r": r, "f": r + iv[2], "o": r + 12, "3": r + iv[1], "-": None}[w]
                if m is not None:
                    self.note(inst, start + i * beats + off, d, m, **kw)

    def drums(self, lines, start=0.0, bars=None, step=0.25, gain=1.0, send=0.12, pans=None):
        """lines: {name: 'k...s...'} one char per step for one bar (repeated)."""
        bars = bars or self.bars
        pans = pans or {}
        for key, pat in lines.items():
            steps = len(pat)
            for bar in range(bars):
                for i, ch in enumerate(pat):
                    if ch == ".":
                        continue
                    vel = 1.0 if ch.isupper() and ch not in "KST" else 0.85
                    sig = S.DRUMS[ch](vel * RNG.uniform(0.85, 1.0))
                    beat = start + bar * self.bpb + i * (self.bpb / steps)
                    self.bus.add(sig, self.at(beat) + RNG.uniform(-0.003, 0.003) * SR, gain, pans.get(key, 0.0), send)

    def render(self):
        L, R = self.bus.render(self.ir, master=self.master)
        save_ogg(self.name, L, R)
        print(f"music: {self.name} {self.n / SR:.1f}s")


def save_ogg(name, L, R):
    os.makedirs(MUS_DIR, exist_ok=True)
    wav = os.path.join(MUS_DIR, f".{name}.tmp.wav")
    S.write_wav(wav, L, R)
    out = os.path.join(MUS_DIR, name + ".ogg")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    os.remove(wav)
    old = os.path.join(MUS_DIR, name + ".wav")
    if os.path.exists(old):
        os.remove(old)
        if os.path.exists(old + ".import"):
            os.remove(old + ".import")


# ---------------------------------------------------------------- themes

THEME_A = ("F#5:1 A5:0.5 B5:0.5 A5:1 F#5:1 E5:1 D5:0.5 E5:0.5 F#5:2 "
           "G5:1 B5:0.5 C#6:0.5 B5:1 G5:1 F#5:1 E5:1 D5:2 "
           "B4:1 D5:0.5 E5:0.5 F#5:1 A5:1 G5:1 F#5:0.5 E5:0.5 D5:2 "
           "E5:1 F#5:0.5 G5:0.5 A5:1 C#5:1 D5:3 -:1")
CHORDS_A = ["D", "G", "Bm", "A", "G", "D", "Em", "A"]
THEME_B = ("D6:1.5 C#6:0.5 B5:1 A5:1 B5:1 A5:0.5 G5:0.5 F#5:2 "
           "G5:1.5 F#5:0.5 E5:1 D5:1 E5:3 -:1 "
           "D6:1.5 C#6:0.5 B5:1 A5:1 B5:1 C#6:0.5 D6:0.5 E6:2 "
           "D6:1 C#6:1 B5:1 A5:0.5 G5:0.5 A5:4")
CHORDS_B = ["Bm", "G", "D", "A", "Bm", "E7", "G", "A"]


def title():
    s = Song("title", 92, 16, reverb=(3.0, 1.3, 0.55))
    prog = CHORDS_A + CHORDS_B
    s.chords(S.pad, prog, center=62, gain=0.16, send=0.5, pan=0.0)
    s.arp(S.epiano, prog, [0, 2, 4, 2, 1, 2, 4, 3], step=0.5, center=62, gain=0.22, send=0.35, pan=-0.25, vel=0.55)
    s.bassline(S.subbass, prog, [(0, 3.9, "r")], octave=2, gain=0.3, send=0.05)
    s.melody(S.musicbox, THEME_A, 0, gain=0.3, send=0.45, pan=0.2, vel=0.7)
    s.melody(S.flute, THEME_B, 32, gain=0.3, send=0.4, pan=0.15, vel=0.75)
    s.melody(S.bell, THEME_B, 32, transpose=-12, gain=0.08, send=0.6, pan=-0.3, vel=0.5)
    s.drums({"x": "..x...x...x...x."}, start=32, bars=8, gain=0.12, send=0.2, pans={"x": 0.4})
    s.render()


def map_():
    s = Song("map", 80, 16, reverb=(2.6, 1.1, 0.6))
    prog = ["G", "Em", "C", "D", "G", "Em", "Am7", "Dsus4", "C", "D", "Bm", "Em", "C", "Am7", "Dsus4", "D"]
    s.chords(S.pad, prog, center=60, gain=0.12, send=0.5)
    s.bassline(S.piano, prog, [(0, 2, "r"), (2, 2, "f")], octave=2, gain=0.35, send=0.25, vel=0.55)
    s.arp(S.piano, prog, [None, 1, 2, 1, None, 2, 3, 2], step=0.5, center=64, gain=0.22, send=0.3, vel=0.45, pan=0.1)
    mel = ("B5:1.5 A5:0.5 G5:1 D5:1 E5:2 B4:2 C5:1 E5:1 G5:1 A5:1 F#5:4 "
           "B5:1.5 A5:0.5 G5:1 D5:1 E5:1 F#5:1 G5:2 A5:1 G5:1 E5:1 C5:1 D5:4 "
           "E5:1.5 F#5:0.5 G5:1 C6:1 A5:2 F#5:2 D5:1 F#5:1 B5:1 A5:1 G5:4 "
           "E5:1 G5:1 C6:2 B5:1 A5:1 G5:1 E5:1 F#5:2 A5:2 D5:4")
    s.melody(S.piano, mel, 0, gain=0.34, send=0.35, vel=0.6, pan=0.15)
    s.render()


def two_pass(name, bpm, body, bars=16, bpb=4, reverb=(2.4, 0.9, 0.5), master=0.85):
    """A song whose second half replays the first with variation (v=True)."""
    s = Song(name, bpm, bars * 2, beats_per_bar=bpb, reverb=reverb, master=master)
    body(s, 0.0, False)
    body(s, float(bars * bpb), True)
    s.render()


def prologue():
    A = ["G", "C", "Am", "D", "G", "C", "D", "G"]
    B = ["Em", "C", "G", "D", "Em", "C", "G", "D"]
    mel_a = ("B4:1 D5:1 G5:1.5 F#5:0.5 E5:1 D5:1 B4:2 C5:1 E5:1 A5:1.5 G5:0.5 F#5:2 -:2 "
             "B4:1 D5:1 G5:1.5 A5:0.5 B5:1 A5:1 G5:2 E5:1 F#5:1 G5:1 A5:1 G5:3 -:1")
    mel_b = ("E5:1.5 F#5:0.5 G5:1 B5:1 A5:2 G5:1 E5:1 D5:1.5 E5:0.5 G5:1 A5:1 F#5:3 -:1 "
             "E5:1.5 F#5:0.5 G5:1 B5:1 C6:2 B5:1 A5:1 B5:1 A5:1 G5:1 F#5:1 A5:4")

    def body(s, o, v):
        prog = A + B
        s.arp(S.pluck, prog, [0, 2, 4, 2, 1, 2, 4, 2] if not v else [0, 2, 4, 5, 4, 2, 1, 2], step=0.5, start=o, center=57, gain=0.3, send=0.25, pan=-0.3, vel=0.6)
        s.bassline(S.bass, prog, [(0, 1.5, "r"), (1.5, 0.5, "f"), (2, 1, "o"), (3, 1, "f")], start=o, octave=2, gain=0.3, send=0.05, bright=700)
        s.chords(S.strings, prog, start=o, center=60, gain=0.07 if not v else 0.1, send=0.4)
        s.melody(S.flute if not v else S.epiano, mel_a, o, transpose=0 if not v else 12, gain=0.32 if not v else 0.22, send=0.3, pan=0.2)
        s.melody(S.flute, mel_b, o + 32, gain=0.32, send=0.3, pan=0.2)
        s.melody(S.pluck if not v else S.bell, mel_b, o + 32, transpose=-12 if not v else 0, gain=0.12 if not v else 0.06, send=0.3, pan=-0.1, vel=0.5)
        s.drums({"x": "x.x.x.x.x.x.x.x.", "k": "k.......k......."}, start=o, bars=16, gain=0.22, pans={"x": 0.35})
        s.drums({"b": "....b.......b..."}, start=o + 32, bars=8, gain=0.22)
        if v:
            s.drums({"b": "....b.......b..."}, start=o, bars=8, gain=0.16)
    two_pass("prologue", 100, body, reverb=(2.0, 0.8, 0.5))


def ch1():
    A = ["Am", "F", "C", "G", "Am", "F", "G", "Am"]
    B = ["F", "G", "Em", "Am", "Dm", "G", "C", "E"]
    mel_a = ("A4:0.5 C5:0.5 E5:1 D5:0.5 C5:0.5 B4:1 G4:1 A4:2 -:1 "
             "F4:0.5 A4:0.5 C5:1 B4:0.5 A4:0.5 G4:2 E4:2 -:1 "
             "A4:0.5 C5:0.5 E5:1 G5:1 F5:0.5 E5:0.5 D5:2 -:1 "
             "C5:0.5 D5:0.5 E5:1 D5:1 B4:1 A4:3 -:1")
    mel_b = ("C6:1 B5:0.5 A5:0.5 G5:1 E5:1 D5:1 E5:0.5 F5:0.5 G5:2 "
             "E5:1 D5:0.5 C5:0.5 B4:1 G4:1 A4:3 -:1 "
             "D5:1 E5:0.5 F5:0.5 A5:1 F5:1 G5:1 F5:0.5 E5:0.5 D5:2 "
             "E5:1 G5:1 C6:1 B5:0.5 A5:0.5 G#5:4")

    def body(s, o, v):
        prog = A + B
        s.arp(S.pluck, prog, [0, 1, 2, 3, 2, 1, 0, 1], step=0.5, start=o, center=60, gain=0.24, send=0.3, pan=-0.35, vel=0.55, bright=0.7)
        s.bassline(S.bass, prog, [(0, 1.5, "r"), (1.5, 0.5, "r"), (2, 1, "f"), (3, 0.5, "o"), (3.5, 0.5, "f")], start=o, octave=2, gain=0.3, send=0.05, bright=600)
        s.chords(S.pad, prog, start=o, center=60, gain=0.08, send=0.5)
        s.melody(S.musicbox, mel_a, o, transpose=12, gain=0.26, send=0.45, pan=0.25)
        s.melody(S.epiano if not v else S.flute, mel_a, o, gain=0.14 if not v else 0.2, send=0.3, pan=0.1, vel=0.5)
        s.melody(S.chip if not v else S.flute, mel_b, o + 32, gain=0.2, send=0.3, pan=0.2)
        s.melody(S.musicbox, mel_b, o + 32, gain=0.12, send=0.5, pan=-0.2)
        s.drums({"h": "h.h.h.h.h.h.h.hh", "b": "....b.......b..b", "k": "k.........k....."}, start=o, bars=16, gain=0.24, pans={"h": 0.3})
        if v:
            s.chords(S.strings, B, start=o + 32, center=64, gain=0.07, send=0.4)
    two_pass("ch1", 104, body, reverb=(2.6, 1.1, 0.55))


def ch2():
    A = ["Em", "B", "Em", "C", "Am", "B", "Em", "Em"]
    B = ["C", "D", "G", "Em", "Am", "B7", "Em", "Em"]
    mel_a = ("B5:1 G5:1 E5:1 F#5:2 D#5:1 E5:2 B4:1 C5:1 E5:1 G5:1 "
             "A5:1 F#5:1 D#5:1 E5:3 G5:1 F#5:1 E5:1 D#5:1 B4:1 E5:1")
    mel_b = ("E6:2 D6:1 C6:1 B5:1 A5:1 B5:2 G5:1 E5:3 "
             "A5:1 B5:1 C6:1 D#6:2 B5:1 E6:3 -:3")

    def body(s, o, v):
        prog = A + B
        s.bassline(S.pluck, prog, [(0, 1, "r")], start=o, beats=3, octave=2, gain=0.35, send=0.3, vel=0.6)
        s.chords(S.pluck, prog, start=o, beats=3, center=62, hits=[(1, 0.8), (2, 0.8)], gain=0.12, send=0.45, vel=0.45, pan=-0.2)
        s.chords(S.strings, prog, start=o, beats=3, center=64, gain=0.08, send=0.6)
        s.melody(S.musicbox if not v else S.bell, mel_a, o, transpose=0, gain=0.3 if not v else 0.24, send=0.55, pan=0.2)
        s.melody(S.bell if not v else S.choir, mel_a, o, transpose=-12, gain=0.06 if not v else 0.12, send=0.7, pan=-0.3, vel=0.4)
        s.melody(S.musicbox, mel_b, o + 24, gain=0.3, send=0.55, pan=0.2)
        s.chords(S.choir, B, start=o + 24, beats=3, center=64, gain=0.12, send=0.7)
    two_pass("ch2", 88, body, bpb=3, reverb=(4.0, 1.8, 0.4))


def ch3():
    A = ["C", "Am", "F", "G", "C", "A", "Dm", "G"]
    B = ["F", "C", "G", "C", "F", "C", "D7", "G"]
    mel_a = ("G4:0.5 G#4:0.5 A4:0.5 C5:0.5 E5:1 D5:1 C5:0.5 A4:0.5 G4:1 E4:2 "
             "F4:0.5 F#4:0.5 G4:0.5 A4:0.5 D5:1 C5:1 B4:0.5 G4:0.5 A4:1 B4:2 "
             "G4:0.5 G#4:0.5 A4:0.5 C5:0.5 E5:1 G5:1 F5:0.5 E5:0.5 D5:1 C5:2 "
             "D5:0.5 E5:0.5 F5:1 E5:1 D5:1 C5:3 -:1")
    mel_b = ("A5:1 G5:0.5 F5:0.5 E5:1 C5:1 G5:1.5 E5:0.5 C5:2 "
             "D5:0.5 E5:0.5 F5:0.5 G5:0.5 A5:1 B5:1 C6:2 G5:2 "
             "A5:1 G5:0.5 F5:0.5 E5:1 C5:1 G5:1.5 E5:0.5 C5:2 "
             "F#5:0.5 G5:0.5 A5:0.5 F#5:0.5 D5:1 C5:1 B4:2 G4:2")

    def body(s, o, v):
        prog = A + B
        s.bassline(S.tuba, prog, [(0, 0.9, "r"), (2, 0.9, "f")], start=o, octave=2, gain=0.4, send=0.1)
        s.chords(S.organ, prog, start=o, center=62, hits=[(1, 0.4), (3, 0.4)], gain=0.12, send=0.2, pan=-0.2)
        s.melody(S.calliope, mel_a, o, transpose=12, gain=0.2, send=0.25, pan=0.15)
        if v:
            s.melody(S.bell, mel_a, o, transpose=12, gain=0.06, send=0.4, pan=-0.3, vel=0.5)
        s.melody(S.calliope, mel_b, o + 32, transpose=0 if not v else 12, gain=0.22 if not v else 0.18, send=0.25, pan=0.15)
        s.melody(S.bell, mel_b, o + 32, transpose=12, gain=0.05, send=0.4, pan=-0.3, vel=0.5)
        s.drums({"s": "..s...s...s...s.", "k": "k.......k......."}, start=o, bars=16, gain=0.26, pans={"s": 0.1})
        s.drums({"c": "c..............."}, start=o, bars=1, gain=0.26)
        s.drums({"s": "..s...s...s.sss."}, start=o + 28, bars=1, gain=0.2)
        s.drums({"s": "..s...s...s.sss."}, start=o + 60, bars=1, gain=0.2)
    two_pass("ch3", 124, body, reverb=(1.6, 0.6, 0.5))


def ch4():
    A = ["F", "C", "Dm", "Bb", "F", "C", "Bb", "C"]
    B = ["Dm", "Bb", "F", "C", "Dm", "Bb", "C", "C"]
    mel_a = ("C5:0.5 F5:0.5 A5:1 G5:0.5 F5:0.5 E5:1 C5:1 D5:0.5 E5:0.5 F5:2 -:1 "
             "Bb4:0.5 D5:0.5 F5:1 E5:0.5 D5:0.5 C5:1 A4:1 G4:3 -:1 "
             "C5:0.5 F5:0.5 A5:1 C6:1 Bb5:0.5 A5:0.5 G5:2 -:1 "
             "F5:0.5 G5:0.5 A5:1 G5:1 E5:1 F5:3 -:1")
    mel_b = ("D6:1.5 C6:0.5 A5:1 F5:1 Bb5:2 A5:1 G5:1 A5:1.5 G5:0.5 F5:1 C5:1 G5:3 -:1 "
             "D6:1.5 C6:0.5 A5:1 F5:1 Bb5:1 C6:1 D6:1 F6:1 E6:2 D6:1 C6:1 C6:4")

    def body(s, o, v):
        prog = A + B
        s.arp(S.pluck, prog, [0, 1, 2, 4, 2, 1, 0, 1], step=0.25, start=o, center=60, gain=0.2, send=0.2, pan=-0.3, vel=0.5, bright=1.3)
        s.bassline(S.bass, prog, [(i * 0.5, 0.45, "r" if i % 4 != 3 else "o") for i in range(8)], start=o, octave=2, gain=0.3, send=0.03, bright=900)
        s.chords(S.strings, prog, start=o, center=62, gain=0.09, send=0.3)
        s.melody(S.flute, mel_a, o, gain=0.3, send=0.25, pan=0.2)
        s.melody(S.chip if not v else S.epiano, mel_a, o, transpose=-12 if not v else 0, gain=0.08 if not v else 0.12, send=0.2, pan=-0.2)
        s.melody(S.flute, mel_b, o + 32, gain=0.3, send=0.25, pan=0.2)
        s.melody(S.strings, mel_b, o + 32, transpose=-12, gain=0.12, send=0.3, pan=-0.2)
        s.drums({"k": "k.....k.k.......", "s": "....s.......s...", "h": "h.h.h.h.h.h.h.h." if not v else "hhhhhhhhhhhhhhhh"}, start=o, bars=16, gain=0.3, pans={"h": 0.3})
        s.drums({"c": "c..............."}, start=o, bars=1, gain=0.3)
        s.drums({"c": "c..............."}, start=o + 32, bars=1, gain=0.25)
    two_pass("ch4", 136, body, reverb=(1.8, 0.7, 0.5))


def ch5():
    A = ["Dm", "Bb", "Gm", "A", "F", "C", "Gm", "A"]
    B = ["Bb", "F", "Gm", "Dm", "Bb", "C", "A", "A"]
    mel_a = "D5:2 F5:2 A5:3 G5:1 F5:2 E5:2 D5:4 C5:2 E5:2 G5:3 F5:1 E5:2 C#5:2 D5:4"
    mel_b = "F5:2 A5:2 C6:3 Bb5:1 A5:2 G5:2 F5:4 D5:2 F5:2 E5:2 G5:2 A5:2 C#6:2 A5:4"
    s = Song("ch5", 70, 16, reverb=(5.0, 2.4, 0.45), master=0.8)
    prog = A + B
    s.chords(S.organ, prog, center=58, gain=0.16, send=0.55, drawbars=(0.8, 1.0, 0.6, 0.3, 0.3, 0.0, 0.1))
    s.bassline(S.organ, prog, [(0, 4, "r")], octave=2, gain=0.18, send=0.4, drawbars=(1.0, 0.8, 0.3, 0, 0, 0, 0))
    s.melody(S.bell, mel_a, 0, gain=0.22, send=0.7, pan=0.2)
    s.melody(S.choir, mel_b, 32, gain=0.2, send=0.7, pan=0.1)
    s.melody(S.bell, mel_b, 32, transpose=12, gain=0.07, send=0.8, pan=-0.3, vel=0.5)
    s.chords(S.choir, B, start=32, center=60, gain=0.1, send=0.8)
    s.render()


def ch6():
    A = ["Bm", "G", "D", "A", "Bm", "G", "Em", "F#m"]
    B = ["G", "D", "A", "F#m", "G", "Em", "F#", "F#"]
    mel_a = "F#5:2 D5:1 B4:1 C#5:2 A4:2 B4:3 -:1 G5:2 F#5:1 E5:1 D5:2 C#5:2 B4:4"
    mel_b = "D5:2 B4:1 G4:1 A4:2 F#4:2 E4:3 -:1 G4:2 B4:1 E5:1 A#4:4 C#5:4"
    s = Song("ch6", 76, 16, reverb=(4.5, 2.0, 0.7), master=0.8)
    prog = A + B
    s.chords(S.pad, prog, center=55, gain=0.2, send=0.6, bright=1600)
    s.bassline(S.subbass, prog, [(0, 4, "r")], octave=1, gain=0.2, send=0.05)
    s.melody(S.epiano, mel_a, 0, gain=0.24, send=0.55, pan=0.15, vel=0.55)
    s.melody(S.epiano, mel_a, 32, transpose=12, gain=0.12, send=0.65, pan=-0.2, vel=0.45)
    s.melody(S.epiano, mel_b, 32, transpose=12, gain=0.22, send=0.55, pan=0.15, vel=0.55)
    scale = [71, 73, 74, 76, 78, 79, 81, 83, 85, 86]
    for i in range(40):
        b = RNG.uniform(0, s.bars * 4)
        s.note(S.bell, b, 0.3, int(RNG.choice(scale)) + 12, vel=0.35, gain=0.06, send=0.8, pan=RNG.uniform(-0.8, 0.8))
    s.drums({"m": "m...............", "T": "..........T....."}, gain=0.12, send=0.5)
    s.render()


def ch7():
    def body(s, o, v):
        prog = CHORDS_A + CHORDS_B
        s.arp(S.epiano, prog, [0, 2, 4, 2, 1, 2, 4, 3], step=0.5 if not v else 0.25, start=o, center=62, gain=0.18 if not v else 0.14, send=0.25, pan=-0.3, vel=0.6)
        s.bassline(S.bass, prog, [(i * 0.5, 0.45, "r" if i % 4 != 2 else "f") for i in range(8)], start=o, octave=2, gain=0.3, send=0.03)
        s.chords(S.strings, prog, start=o, center=62, gain=0.11, send=0.35)
        s.melody(S.flute, THEME_A, o, gain=0.3, send=0.25, pan=0.2)
        s.melody(S.chip if not v else S.strings, THEME_A, o, transpose=-12, gain=0.09 if not v else 0.14, send=0.2, pan=-0.15)
        s.melody(S.strings if not v else S.flute, THEME_B, o + 32, transpose=0, gain=0.2 if not v else 0.3, send=0.35, pan=0.1)
        s.melody(S.bell, THEME_B, o + 32, gain=0.07, send=0.5, pan=-0.3, vel=0.5)
        s.drums({"k": "k.......k.k.....", "s": "....s.......s...", "h": "h.h.h.h.h.h.h.h." if not v else "h.hoh.h.h.hoh.h."}, start=o, bars=16, gain=0.3, pans={"h": 0.3})
        s.drums({"c": "c..............."}, start=o, bars=1, gain=0.3)
        s.drums({"c": "c..............."}, start=o + 32, bars=1, gain=0.3)
        s.drums({"t": "........t.t.T.Tm"}, start=o + 60, bars=1, gain=0.25)
    two_pass("ch7", 128, body, reverb=(2.4, 1.0, 0.5))


def chase():
    s = Song("chase", 150, 16, reverb=(1.4, 0.5, 0.5))
    prog = ["Em", "Em", "C", "B"] * 4
    mel = ("E5:0.5 E5:0.5 G5:0.5 E5:0.5 A5:0.5 G5:0.5 E5:0.5 D5:0.5 "
           "E5:0.5 E5:0.5 G5:0.5 E5:0.5 B5:1 A5:1 "
           "C6:0.5 B5:0.5 A5:0.5 G5:0.5 A5:0.5 G5:0.5 E5:0.5 D5:0.5 "
           "E5:0.5 G5:0.5 E5:0.5 D#5:0.5 E5:2")
    s.chords(S.strings, prog, center=60, hits=[(i * 0.5, 0.3) for i in range(8)], gain=0.1, send=0.15)
    s.bassline(S.bass, prog, [(i * 0.5, 0.4, "r") for i in range(8)], octave=2, gain=0.32, send=0.02, bright=1100)
    s.melody(S.chip, mel, 0, gain=0.22, send=0.2, pan=0.15)
    s.melody(S.chip, mel, 16, gain=0.22, send=0.2, pan=0.15)
    s.melody(S.flute, mel, 32, gain=0.26, send=0.2, pan=0.2)
    s.melody(S.flute, mel, 48, gain=0.26, send=0.2, pan=0.2)
    s.drums({"k": "k...k...k...k...", "s": "....s.......s...", "h": "h.hhh.hhh.hhh.hh", "t": "..............tT"}, gain=0.26, pans={"h": 0.3})
    s.render()


def epilogue():
    s = Song("epilogue", 88, 16, reverb=(2.6, 1.1, 0.5))
    prog = CHORDS_A + CHORDS_B
    s.arp(S.pluck, prog, [0, 2, 4, 2, 1, 2, 4, 2], step=0.5, center=57, gain=0.28, send=0.3, pan=-0.3, vel=0.55)
    s.bassline(S.bass, prog, [(0, 2, "r"), (2, 2, "f")], octave=2, gain=0.26, send=0.05, bright=600)
    s.chords(S.pad, prog, center=62, gain=0.08, send=0.5)
    s.melody(S.flute, THEME_A, 0, gain=0.3, send=0.35, pan=0.2)
    s.melody(S.piano, THEME_B, 32, gain=0.3, send=0.35, pan=0.1)
    s.drums({"x": "..x...x...x...x."}, gain=0.18, pans={"x": 0.35})
    s.render()


def credits():
    s = Song("credits", 96, 32, reverb=(2.6, 1.1, 0.5))
    prog = CHORDS_A + CHORDS_B + CHORDS_A + CHORDS_B
    s.arp(S.epiano, prog, [0, 2, 4, 2, 1, 2, 4, 3], step=0.5, center=62, gain=0.2, send=0.3, pan=-0.3, vel=0.55)
    s.bassline(S.bass, prog, [(0, 1.5, "r"), (1.5, 0.5, "f"), (2, 2, "o")], octave=2, gain=0.28, send=0.04, bright=700)
    s.chords(S.strings, prog, center=62, gain=0.09, send=0.4)
    s.melody(S.musicbox, THEME_A, 0, gain=0.28, send=0.45, pan=0.2)
    s.melody(S.flute, THEME_B, 32, gain=0.3, send=0.35, pan=0.2)
    s.melody(S.flute, THEME_A, 64, gain=0.3, send=0.35, pan=0.2)
    s.melody(S.bell, THEME_A, 64, gain=0.08, send=0.5, pan=-0.3, vel=0.5)
    s.melody(S.strings, THEME_B, 96, gain=0.2, send=0.4, pan=0.1)
    s.melody(S.piano, THEME_B, 96, transpose=12, gain=0.12, send=0.4, pan=-0.2)
    s.drums({"x": "..x...x...x...x.", "k": "k.......k......."}, start=32, bars=24, gain=0.22, pans={"x": 0.35})
    s.drums({"b": "....b.......b..."}, start=64, bars=32, gain=0.2)
    s.render()


# ---------------------------------------------------------------- ambience loops

def _amb_bus(seconds):
    return S.Bus(int(seconds * SR), loop=True)


def _loop_noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def _slow_lfo(n, rate, seed):
    """Smooth random modulation that loops (sum of sines with integer cycles)."""
    t = np.arange(n) / n
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    for k in range(1, 5):
        cycles = max(1, int(rate * n / SR * k / 2))
        out += np.sin(2 * np.pi * cycles * t + rng.uniform(0, 6.28)) / k
    return out / 2.0


def ambience():
    secs = 24.0
    n = int(secs * SR)
    ir = S.reverb_ir(2.5, 1.0, 0.5)

    def wind(gain=1.0, fc=500.0, seed=1):
        L = spectral(_loop_noise(n, seed), "band", fc * 0.4, 1, fc)
        R = spectral(_loop_noise(n, seed + 1), "band", fc * 0.4, 1, fc)
        m = 0.55 + 0.45 * _slow_lfo(n, 0.12, seed)
        return L * m * gain, R * (0.55 + 0.45 * _slow_lfo(n, 0.12, seed + 5)) * gain

    def save(name, L, R):
        peak = max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-9)
        save_ogg(name, L / peak * 0.7, R / peak * 0.7)
        print(f"ambience: {name}")

    # meadow dusk: soft wind + crickets
    L, R = wind(1.0, 700, 11)
    b = _amb_bus(secs)
    for i in range(70):
        t0 = RNG.uniform(0, secs)
        f = RNG.uniform(4200, 5200)
        chirp = np.zeros(int(0.25 * SR))
        tt = tarr(len(chirp))
        for p in range(3):
            seg = (tt > p * 0.07) & (tt < p * 0.07 + 0.035)
            chirp += np.sin(2 * np.pi * f * tt) * seg
        b.add(chirp * 0.05, t0 * SR, 1.0, RNG.uniform(-0.9, 0.9), 0.2)
    cl, cr = b.render(ir, master=1.0)
    save("amb_meadow", L * 0.6 + cl * 0.18, R * 0.6 + cr * 0.18)
    # night town: lower wind, distant chimes
    L, R = wind(1.0, 400, 21)
    b = _amb_bus(secs)
    for i in range(10):
        t0 = RNG.uniform(0, secs)
        b.add(S.bell(hz(int(RNG.choice([76, 79, 81, 83, 86]))), 0.2, 0.4) * 0.05, t0 * SR, 1.0, RNG.uniform(-0.8, 0.8), 0.6)
    cl, cr = b.render(ir, master=1.0)
    save("amb_night", L * 0.6 + cl * 0.25, R * 0.6 + cr * 0.25)
    # high wind for the ridge and summit
    L, R = wind(1.0, 900, 31)
    L2, R2 = wind(0.6, 2500, 33)
    save("amb_wind", L + L2, R + R2)
    # cave: rumble + drips
    L, R = wind(0.6, 160, 41)
    b = _amb_bus(secs)
    for i in range(36):
        t0 = RNG.uniform(0, secs)
        f = RNG.uniform(900, 2200)
        nn = int(0.12 * SR)
        tt = tarr(nn)
        drop = np.sin(2 * np.pi * (f + 1400 * np.exp(-tt / 0.01)) * tt) * np.exp(-tt / 0.03)
        b.add(drop * 0.15, t0 * SR, 1.0, RNG.uniform(-0.9, 0.9), 0.7)
    cl, cr = b.render(S.reverb_ir(4.0, 1.8, 0.6), master=1.0)
    save("amb_cave", L * 0.7 + cl * 0.35, R * 0.7 + cr * 0.35)
    # cathedral hall: airy room tone
    L, R = wind(0.5, 300, 51)
    hum = np.sin(2 * np.pi * 55 * tarr(n)) * 0.04
    save("amb_hall", L + hum, R + hum)
    # dream: glassy shimmer
    L, R = wind(0.35, 1500, 61)
    b = _amb_bus(secs)
    for i in range(30):
        t0 = RNG.uniform(0, secs)
        m = int(RNG.choice([76, 79, 83, 86, 88, 91]))
        b.add(S.musicbox(hz(m), 0.2, 0.3) * 0.05, t0 * SR, 1.0, RNG.uniform(-0.9, 0.9), 0.8)
    cl, cr = b.render(S.reverb_ir(4.0, 2.0, 0.4), master=1.0)
    save("amb_dream", L + cl * 0.4, R + cr * 0.4)
    # carnival: distant murmur
    L = spectral(_loop_noise(n, 71), "band", 250, 2, 1200) * (0.7 + 0.3 * _slow_lfo(n, 0.4, 71))
    R = spectral(_loop_noise(n, 72), "band", 250, 2, 1200) * (0.7 + 0.3 * _slow_lfo(n, 0.4, 72))
    save("amb_carnival", L, R)


# ---------------------------------------------------------------- sound effects

def sfx_out(name, x, tail_ir=None, gain=0.9, max_len=None):
    if max_len is not None and len(x) > int(max_len * SR):
        x = x[: int(max_len * SR)].copy()
        f = int(min(0.3, max_len / 3) * SR)
        x[-f:] *= np.linspace(1, 0, f) ** 2
    if tail_ir is not None:
        wet = S.convolve(x, tail_ir[0])
        x = np.concatenate([x, np.zeros(len(wet) - len(x))]) + wet * 0.25
        # trim the silent tail
        thr = np.max(np.abs(x)) * 0.002
        idx = np.nonzero(np.abs(x) > thr)[0]
        x = x[: (idx[-1] + 1 if len(idx) else len(x))]
        if max_len is not None and len(x) > int(max_len * SR * 1.5):
            x = x[: int(max_len * SR * 1.5)].copy()
            f = int(0.25 * SR)
            x[-f:] *= np.linspace(1, 0, f) ** 2
    fade = min(len(x), int(0.004 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    peak = max(np.max(np.abs(x)), 1e-9)
    os.makedirs(SFX_DIR, exist_ok=True)
    S.write_wav(os.path.join(SFX_DIR, name + ".wav"), x / peak * gain)


def noise(n, seed=1):
    return np.random.default_rng(seed).standard_normal(n)


def env_exp(n, tau, attack=0.002):
    t = tarr(n)
    return np.clip(t / max(attack, 1e-6), 0, 1) * np.exp(-t / tau)


def sweep_sine(f0, f1, dur, curve=1.0):
    n = int(dur * SR)
    k = (np.arange(n) / max(n - 1, 1)) ** curve
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def band_sweep(dur, f0, f1, seed=1, q=0.6, steps=12):
    """Noise whose band-pass centre sweeps from f0 to f1 (piecewise)."""
    n = int(dur * SR)
    src = noise(n, seed)
    out = np.zeros(n)
    edges = np.linspace(0, n, steps + 1).astype(int)
    win = np.hanning(2 * (n // steps) + 2)
    for i in range(steps):
        fc = f0 * (f1 / f0) ** (i / max(steps - 1, 1))
        band = spectral(src, "band", fc * (1 - q / 2), 2, fc * (1 + q / 2))
        a, b = max(edges[i] - n // steps // 2, 0), min(edges[i + 1] + n // steps // 2, n)
        w = np.hanning(b - a) if b - a > 1 else np.ones(b - a)
        out[a:b] += band[a:b] * w
    return out


def sfx():
    room = S.reverb_ir(0.9, 0.3, 0.5)
    hall = S.reverb_ir(2.2, 0.9, 0.5)
    # --- movement
    n = int(0.16 * SR)
    whoosh = band_sweep(0.16, 500, 1800, 3) * env_exp(n, 0.06, 0.01)
    blip = sweep_sine(420, 700, 0.07) * env_exp(int(0.07 * SR), 0.03)
    sfx_out("jump", np.concatenate([np.zeros(0), whoosh]) * 0.9 + np.pad(blip, (0, n - len(blip))) * 0.25)
    n = int(0.2 * SR)
    scuff = spectral(noise(n, 5), "band", 300, 2, 2200) * env_exp(n, 0.025)
    w2 = band_sweep(0.2, 600, 2200, 7) * env_exp(n, 0.07, 0.008)
    sfx_out("walljump", scuff * 0.8 + w2 + np.pad(blip, (0, n - len(blip))) * 0.2)
    n = int(0.14 * SR)
    thud = sweep_sine(110, 45, 0.14, 0.5) * env_exp(n, 0.04)
    grit = spectral(noise(n, 9), "band", 200, 2, 1500) * env_exp(n, 0.03)
    sfx_out("land", thud * 0.9 + grit * 0.6, gain=0.7)
    for i in range(4):
        n = int(0.06 * SR)
        tap = spectral(noise(n, 20 + i), "band", 400 + i * 120, 2, 2400 + i * 300) * env_exp(n, 0.012)
        body = sweep_sine(160 + i * 15, 70, 0.06) * env_exp(n, 0.015)
        sfx_out(f"step{i}", tap * 0.7 + body * 0.5, gain=0.5)
    n = int(0.12 * SR)
    sfx_out("slide", spectral(noise(n, 31), "band", 1500, 2, 6000) * np.hanning(n), gain=0.35)
    n = int(0.08 * SR)
    sfx_out("climb", spectral(noise(n, 33), "band", 600, 2, 3500) * np.hanning(n), gain=0.35)
    n = int(0.05 * SR)
    sfx_out("grab", spectral(noise(n, 35), "band", 500, 2, 3000) * env_exp(n, 0.012), gain=0.45)
    # --- dash: punchy whoosh with a sub thump and a bright tail
    n = int(0.32 * SR)
    w = band_sweep(0.32, 700, 4200, 41, q=0.8) * env_exp(n, 0.09, 0.004)
    sub = sweep_sine(150, 40, 0.18, 0.4) * env_exp(int(0.18 * SR), 0.05)
    air = spectral(noise(n, 43), "hp", 6000, 2) * env_exp(n, 0.05)
    sfx_out("dash", spectral(w, "lp", 6000, 1) + np.pad(sub, (0, n - len(sub))) * 1.1 + air * 0.12, room, max_len=0.6)
    # --- pickups and objects
    sfx_out("refill", S.bell(hz("E6"), 0.1, 0.8) * 0.6 + S.bell(hz("B6"), 0.1, 0.6) * 0.4, hall, max_len=0.9)
    n = int(0.5 * SR)
    shatter = spectral(noise(n, 51), "hp", 3000, 2) * env_exp(n, 0.06)
    chime = np.zeros(int(2.4 * SR))
    for k, m in enumerate(["E6", "G#6", "B6"]):
        x = S.bell(hz(m), 0.1, 0.8)
        o = int(k * 0.045 * SR)
        chime[o:o + len(x)] += x[: len(chime) - o] * 0.5
    sfx_out("gem", np.pad(shatter, (0, len(chime) - n)) * 0.18 + chime, hall, max_len=1.4)
    n = int(0.45 * SR)
    t = tarr(n)
    boing_f = 180 + 520 * (1 - np.exp(-t / 0.05)) + 40 * np.sin(2 * np.pi * 18 * t) * np.exp(-t / 0.15)
    boing = np.sin(2 * np.pi * np.cumsum(boing_f) / SR) * env_exp(n, 0.14)
    click = spectral(noise(n, 61), "band", 1000, 2, 5000) * env_exp(n, 0.008)
    sfx_out("spring", boing + click * 0.6, room)
    n = int(0.5 * SR)
    crackle = spectral(noise(n, 71), "band", 150, 2, 2500) * env_exp(n, 0.15)
    pops = np.zeros(n)
    for i in range(14):
        o = int(RNG.uniform(0, 0.4) * SR)
        m = int(0.015 * SR)
        pops[o:o + m] += spectral(noise(m, 72 + i), "band", 800, 2, 4000) * np.hanning(m) * RNG.uniform(0.3, 1)
    sfx_out("crumble", crackle * 0.8 + pops * 0.6, gain=0.75)
    n = int(0.7 * SR)
    impact = sweep_sine(120, 35, 0.3, 0.4) * env_exp(int(0.3 * SR), 0.08)
    debris = spectral(noise(n, 81), "band", 200, 2, 6000) * env_exp(n, 0.18)
    pops = np.zeros(n)
    for i in range(20):
        o = int(RNG.uniform(0.02, 0.55) * SR)
        m = int(0.012 * SR)
        pops[o:o + m] += spectral(noise(m, 90 + i), "band", 1500, 2, 7000) * np.hanning(m) * RNG.uniform(0.2, 0.8)
    sfx_out("break", np.pad(impact, (0, n - len(impact))) + debris * 0.7 + pops * 0.5, room)
    k1 = S.bell(hz("C6"), 0.08, 0.8)
    k2 = S.bell(hz("G6"), 0.1, 0.8)
    key = np.zeros(len(k2) + int(0.08 * SR))
    key[:len(k1)] += k1
    key[int(0.08 * SR):int(0.08 * SR) + len(k2)] += k2
    sfx_out("key", key, hall, max_len=1.6)
    n = int(0.9 * SR)
    t = tarr(n)
    clunk = sweep_sine(90, 50, 0.2) * env_exp(int(0.2 * SR), 0.06)
    ring = np.sin(2 * np.pi * 220 * t + 2.0 * np.sin(2 * np.pi * 311 * t) * np.exp(-t / 0.2)) * env_exp(n, 0.3)
    sfx_out("door", np.pad(clunk, (0, n - len(clunk))) + ring * 0.35 + spectral(noise(n, 95), "band", 200, 2, 2000) * env_exp(n, 0.05) * 0.6, room)
    n = int(0.22 * SR)
    swish = band_sweep(0.22, 2500, 700, 101) * env_exp(n, 0.07, 0.01)
    two = np.concatenate([sweep_sine(880, 880, 0.06) * env_exp(int(0.06 * SR), 0.03), sweep_sine(587, 587, 0.12) * env_exp(int(0.12 * SR), 0.05)])
    sfx_out("mask", swish * 0.6 + np.pad(two, (0, n - len(two))) * 0.35, room)
    n = int(0.25 * SR)
    pop = spectral(noise(n, 111), "band", 500, 2, 3000) * env_exp(n, 0.02)
    squeak = sweep_sine(500, 950, 0.18) * env_exp(int(0.18 * SR), 0.06)
    sfx_out("balloon", pop + np.pad(squeak, (0, n - len(squeak))) * 0.4, room)
    n = int(0.4 * SR)
    t = tarr(n)
    bump = np.sin(2 * np.pi * (300 + 300 * np.exp(-t / 0.04)) * t + 1.5 * np.sin(2 * np.pi * 450 * t) * np.exp(-t / 0.1)) * env_exp(n, 0.12)
    sfx_out("bumper", bump + spectral(noise(n, 121), "band", 800, 2, 4000) * env_exp(n, 0.01) * 0.5, room)
    n = int(0.3 * SR)
    t = tarr(n)
    whir = spectral(S.bl_saw(110, t, 30) * (1 + 0.5 * np.sin(2 * np.pi * 30 * t)), "lp", 1800) * np.clip(t / 0.2, 0, 1) * np.exp(-np.maximum(t - 0.2, 0) / 0.05)
    whir = spectral(np.sin(2 * np.pi * np.cumsum(120 + 500 * (t / 0.3) ** 2) / SR), "lp", 3000) * env_exp(n, 0.2, 0.02) * 0.5 + whir * 0.5
    sfx_out("zip_start", whir + spectral(noise(n, 131), "band", 2000, 2, 8000) * env_exp(n, 0.005) * 0.4, room)
    n = int(0.5 * SR)
    clank = sweep_sine(140, 60, 0.25) * env_exp(int(0.25 * SR), 0.07)
    metal = np.sin(2 * np.pi * 523 * tarr(n) + 3 * np.sin(2 * np.pi * 760 * tarr(n))) * env_exp(n, 0.12)
    sfx_out("zip_hit", np.pad(clank, (0, n - len(clank))) + metal * 0.3 + spectral(noise(n, 141), "band", 300, 2, 5000) * env_exp(n, 0.06) * 0.6, room)
    n = int(0.5 * SR)
    velvet = spectral(noise(n, 151), "band", 200, 2, 1500) * np.hanning(n)
    shimmer = np.zeros(n)
    for k, m in enumerate(["B6", "E7", "G#7"]):
        x = S.musicbox(hz(m), 0.05, 0.4)[:n - int(k * 0.05 * SR)]
        shimmer[int(k * 0.05 * SR):int(k * 0.05 * SR) + len(x)] += x * 0.3
    sfx_out("curtain", velvet + shimmer, hall, max_len=1.2)
    sfx_out("berry_touch", S.bell(hz("A6"), 0.05, 0.4), hall, gain=0.5, max_len=0.6)
    notes = ["C6", "E6", "G6", "C7"]
    ber = np.zeros(int(2.6 * SR))
    for k, m in enumerate(notes):
        x = S.bell(hz(m), 0.1, 0.9)
        o = int(k * 0.07 * SR)
        ber[o:o + len(x)] += x[: len(ber) - o] * (0.6 if k < 3 else 0.9)
    sfx_out("berry", ber, hall, max_len=2.2)
    n = int(0.5 * SR)
    t = tarr(n)
    flutter = spectral(noise(n, 161), "band", 400, 2, 3000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 22 * t))) * env_exp(n, 0.2, 0.01)
    sfx_out("flee", flutter * 0.7 + sweep_sine(900, 1800, 0.5) * env_exp(n, 0.2) * 0.25, room)
    # big bell: inharmonic partials
    n = int(4.0 * SR)
    t = tarr(n)
    bl = np.zeros(n)
    for ratio, amp, dec in [(0.5, 0.5, 2.5), (1.0, 1.0, 2.0), (1.19, 0.4, 1.6), (1.5, 0.35, 1.2), (2.0, 0.5, 1.0), (2.74, 0.3, 0.6), (3.76, 0.2, 0.4), (5.4, 0.12, 0.25)]:
        bl += amp * np.sin(2 * np.pi * 660 * ratio * t) * np.exp(-t / dec)
    bl *= np.clip(t / 0.002, 0, 1)
    sfx_out("bell", bl, hall)
    # death: a sharp pop, a falling tone and glassy fragments
    n = int(0.6 * SR)
    pop = spectral(noise(n, 171), "band", 300, 2, 5000) * env_exp(n, 0.03)
    fall = sweep_sine(700, 90, 0.35, 0.6) * env_exp(int(0.35 * SR), 0.12)
    frag = spectral(noise(n, 173), "hp", 4000, 2) * env_exp(n, 0.1) * (np.sin(2 * np.pi * 40 * tarr(n)) > 0)
    sfx_out("death", pop + np.pad(fall, (0, n - len(fall))) * 0.6 + frag * 0.25, room)
    # respawn: a rising reversed shimmer
    n = int(0.45 * SR)
    sh = np.zeros(n)
    for k, m in enumerate(["E5", "B5", "E6", "G#6"]):
        x = S.musicbox(hz(m), 0.05, 0.5)[:n]
        sh[:len(x)] += x * 0.3
    sfx_out("respawn", sh[::-1] * np.linspace(0, 1, n) ** 2 + band_sweep(0.45, 400, 3000, 181) * np.linspace(0, 1, n) * 0.3, room, gain=0.6)
    n = int(0.5 * SR)
    sfx_out("transition", band_sweep(0.5, 300, 1500, 191) * np.hanning(n), gain=0.35)
    # chapter complete fanfare
    fan = np.zeros(int(3.5 * SR))
    for k, m in enumerate(["G5", "C6", "E6", "G6"]):
        x = S.bell(hz(m), 0.3, 0.8) * 0.5
        o = int(k * 0.12 * SR)
        fan[o:o + len(x)] += x[: len(fan) - o]
    padc = sum(S.pad(hz(m), 1.4, 0.7, attack=0.05, release=1.2) for m in ["C5", "E5", "G5"])
    o = int(0.36 * SR)
    fan[o:o + len(padc)] += padc[: len(fan) - o] * 0.25
    sfx_out("complete", fan, hall)
    # UI
    n = int(0.05 * SR)
    t = tarr(n)
    tick = np.sin(2 * np.pi * 1500 * t) * env_exp(n, 0.008) + spectral(noise(n, 201), "band", 2000, 2, 6000) * env_exp(n, 0.003) * 0.3
    sfx_out("menu_move", tick, gain=0.35)
    m1 = S.pluck(hz("E6"), 0.04, 0.7)[:int(0.25 * SR)]
    m2 = S.pluck(hz("B6"), 0.06, 0.7)[:int(0.35 * SR)]
    sel = np.zeros(int(0.45 * SR))
    sel[:len(m1)] += m1
    sel[int(0.06 * SR):int(0.06 * SR) + len(m2)] += m2
    sfx_out("menu_select", sel, room, gain=0.5, max_len=0.5)
    sfx_out("text_next", S.pluck(hz("A6"), 0.03, 0.5)[:int(0.15 * SR)], gain=0.35)
    n = int(0.045 * SR)
    t = tarr(n)
    vb = (np.sin(2 * np.pi * 520 * t) + 0.3 * np.sin(2 * np.pi * 1040 * t)) * env_exp(n, 0.015, 0.003)
    sfx_out("blip", vb, gain=0.35)


JOBS = {
    "title": title, "map": map_, "prologue": prologue, "ch1": ch1, "ch2": ch2, "ch3": ch3, "ch4": ch4,
    "ch5": ch5, "ch6": ch6, "ch7": ch7, "chase": chase, "epilogue": epilogue, "credits": credits,
    "ambience": ambience, "sfx": sfx,
}

if __name__ == "__main__":
    names = sys.argv[1:] or list(JOBS.keys())
    for nm in names:
        JOBS[nm]()
