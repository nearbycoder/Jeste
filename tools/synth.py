"""
Small offline synthesizer used by gen_audio.py (needs numpy).

Everything is rendered at 44.1 kHz in float64 and vectorised per note:
additive / FM / detuned-saw instruments, synthesized drums, zero-phase
spectral filters, and a stereo convolution reverb with a generated impulse
response. Music is rendered as seamless loops: note tails and the reverb
wrap around the end of the buffer (circular convolution), so the last
sample flows straight into the first.
"""
import math
import numpy as np

SR = 44100
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    n = NOTE_NAMES[name[0]]
    i = 1
    if len(name) > 2 and name[1] in "#b":
        n += 1 if name[1] == "#" else -1
        i = 2
    return 12 * (int(name[i:]) + 1) + n


def hz(m):
    if isinstance(m, str):
        m = midi(m)
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def tarr(n):
    return np.arange(n) / SR


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.1, gate=None):
    """Envelope of n samples; the note is held for `gate` seconds then released."""
    t = tarr(n)
    gate = (n / SR - r) if gate is None else gate
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip(1.0 - (t - gate) / max(r, 1e-6), 0.0, 1.0)
    return e * np.where(t > gate, rel, 1.0)


def spectral(x, kind="lp", fc=1000.0, order=2, fc2=None):
    """Zero-phase Butterworth-magnitude filter applied in the frequency domain."""
    if len(x) < 4:
        return x
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    f[0] = 1e-3
    if kind == "lp":
        H = 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    elif kind == "hp":
        H = 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))
    else:  # band
        H = (1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))) / np.sqrt(1.0 + (f / fc2) ** (2 * order))
    return np.fft.irfft(X * H, len(x))


def saw(phase):
    return 2.0 * (phase % 1.0) - 1.0


def bl_saw(f, t, max_h=40):
    """Band-limited saw by additive synthesis."""
    out = np.zeros_like(t)
    nh = int(min(max_h, (SR / 2.2) / max(f, 1.0)))
    for k in range(1, nh + 1):
        out += np.sin(2 * np.pi * f * k * t) / k
    return out * (2 / np.pi)


def bl_square(f, t, max_h=30):
    out = np.zeros_like(t)
    nh = int(min(max_h, (SR / 2.2) / max(f, 1.0)))
    for k in range(1, nh + 1, 2):
        out += np.sin(2 * np.pi * f * k * t) / k
    return out * (4 / np.pi)


# ---------------------------------------------------------------- instruments
# Each returns a mono array for one note: (freq, seconds held, velocity 0..1)

def epiano(f, dur, vel=0.8):
    tail = 1.2
    n = int((dur + tail) * SR)
    t = tarr(n)
    out = np.zeros(n)
    for k, (amp, dec) in enumerate([(1.0, 1.6), (0.45, 0.9), (0.22, 0.6), (0.12, 0.4), (0.06, 0.3)], start=1):
        fk = f * k * (1.0 + 0.0004 * k * k)
        out += amp * np.sin(2 * np.pi * fk * t) * np.exp(-t / (dec * (1.0 + 220.0 / f)))
    # tine "bark" that brightens with velocity
    out += 0.25 * vel * np.sin(2 * np.pi * f * 7.03 * t) * np.exp(-t / 0.05)
    env = adsr(n, 0.002, 2.0, 1.0, 0.25, gate=dur)
    return out * env * (0.35 + 0.65 * vel)


def piano(f, dur, vel=0.8):
    tail = 1.6
    n = int((dur + tail) * SR)
    t = tarr(n)
    out = np.zeros(n)
    B = 0.0002
    for k in range(1, 9):
        fk = f * k * math.sqrt(1 + B * k * k)
        if fk > SR / 2.3:
            break
        amp = (1.0 / k ** 1.3) * (0.6 + 0.4 * vel) ** (k * 0.4)
        dec = 2.4 / (1.0 + 0.35 * k) * (1.0 + 300.0 / f) * 0.5
        out += amp * np.sin(2 * np.pi * fk * t + k) * np.exp(-t / dec)
    hammer = np.random.default_rng(int(f)).standard_normal(n) * np.exp(-t / 0.004) * 0.08 * vel
    out += spectral(hammer, "lp", 3000)
    env = adsr(n, 0.001, 3.0, 1.0, 0.3, gate=dur)
    return out * env * (0.3 + 0.7 * vel)


def pluck(f, dur, vel=0.8, bright=1.0):
    tail = 0.6
    n = int((dur + tail) * SR)
    t = tarr(n)
    out = np.zeros(n)
    for k in range(1, 12):
        fk = f * k
        if fk > SR / 2.3:
            break
        amp = 1.0 / k ** (1.6 - 0.4 * bright)
        dec = 0.9 / (1.0 + 0.5 * k * k / bright) * (1.0 + 200.0 / f)
        out += amp * np.sin(2 * np.pi * fk * t) * np.exp(-t / dec)
    env = adsr(n, 0.001, 1.0, 1.0, 0.08, gate=dur + 0.25)
    return out * env * (0.3 + 0.7 * vel)


def musicbox(f, dur, vel=0.8):
    n = int((dur + 1.4) * SR)
    t = tarr(n)
    out = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.9)
    out += 0.4 * np.sin(2 * np.pi * f * 3.0 * t) * np.exp(-t / 0.35)
    out += 0.2 * np.sin(2 * np.pi * f * 5.98 * t) * np.exp(-t / 0.12)
    out += 0.12 * np.sin(2 * np.pi * f * 9.1 * t) * np.exp(-t / 0.05)
    return out * adsr(n, 0.001, 1.0, 1.0, 0.1) * (0.3 + 0.7 * vel)


def bell(f, dur, vel=0.8):
    """FM bell / celesta."""
    n = int((dur + 2.0) * SR)
    t = tarr(n)
    idx = 3.0 * np.exp(-t / 0.4) * vel + 0.4
    mod = np.sin(2 * np.pi * f * 3.5 * t) * idx
    out = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 1.1)
    out += 0.3 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / 0.5)
    return out * adsr(n, 0.001, 2.0, 1.0, 0.2) * (0.3 + 0.7 * vel)


def pad(f, dur, vel=0.8, voices=5, detune=0.012, attack=0.6, release=1.2, bright=2400.0):
    n = int((dur + release) * SR)
    t = tarr(n)
    rng = np.random.default_rng(int(f * 10) % 9973)
    out = np.zeros(n)
    for v in range(voices):
        d = 1.0 + detune * (v - (voices - 1) / 2.0) / max(voices - 1, 1) * 2.0
        ph = rng.random()
        out += bl_saw(f * d, t + ph / (f * d), max_h=24)
    out /= voices
    lfo = 1.0 + 0.004 * np.sin(2 * np.pi * 5.0 * t)
    out = spectral(out * lfo, "lp", bright, 2)
    return out * adsr(n, attack, 1.0, 1.0, release, gate=dur) * (0.4 + 0.6 * vel)


def strings(f, dur, vel=0.8):
    return pad(f, dur, vel, voices=6, detune=0.008, attack=0.25, release=0.5, bright=3200.0)


def choir(f, dur, vel=0.8):
    n = int((dur + 1.0) * SR)
    t = tarr(n)
    vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.6, 0, 1)
    ph = np.cumsum(f * vib) / SR
    src = np.zeros(n)
    for k in range(1, 16):
        if f * k > SR / 2.3:
            break
        src += np.sin(2 * np.pi * k * ph) / k
    # "aah" formants
    out = spectral(src, "band", 700, 2, 1150) + 0.5 * spectral(src, "band", 1100, 2, 1300) + 0.25 * spectral(src, "band", 2600, 2, 3000)
    return out * adsr(n, 0.4, 1.0, 1.0, 0.8, gate=dur) * (0.4 + 0.6 * vel) * 1.8


def organ(f, dur, vel=0.8, drawbars=(1.0, 0.8, 0.5, 0.0, 0.35, 0.0, 0.2)):
    n = int((dur + 0.25) * SR)
    t = tarr(n)
    ratios = [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 8.0]
    out = np.zeros(n)
    for r, a in zip(ratios, drawbars):
        if a > 0 and f * r < SR / 2.3:
            out += a * np.sin(2 * np.pi * f * r * t)
    trem = 1.0 + 0.08 * np.sin(2 * np.pi * 6.2 * t)
    return out * trem * adsr(n, 0.01, 1.0, 1.0, 0.12, gate=dur) * 0.4 * (0.5 + 0.5 * vel)


def calliope(f, dur, vel=0.8):
    """Breathy steam-organ whistle for the carnival."""
    n = int((dur + 0.15) * SR)
    t = tarr(n)
    vib = 1.0 + 0.008 * np.sin(2 * np.pi * 6.5 * t)
    ph = np.cumsum(f * vib) / SR
    out = np.sin(2 * np.pi * ph) + 0.35 * np.sin(4 * np.pi * ph) + 0.15 * np.sin(6 * np.pi * ph)
    breath = spectral(np.random.default_rng(3).standard_normal(n), "band", f * 0.8, 2, f * 2.5) * 0.25
    return (out + breath) * adsr(n, 0.02, 0.3, 0.85, 0.08, gate=dur) * (0.4 + 0.6 * vel)


def flute(f, dur, vel=0.8):
    n = int((dur + 0.3) * SR)
    t = tarr(n)
    vib_amt = np.clip((t - 0.25) / 0.4, 0, 1) * 0.007
    ph = np.cumsum(f * (1.0 + vib_amt * np.sin(2 * np.pi * 5.0 * t))) / SR
    out = np.sin(2 * np.pi * ph) + 0.18 * np.sin(4 * np.pi * ph) + 0.06 * np.sin(6 * np.pi * ph)
    breath = spectral(np.random.default_rng(int(f)).standard_normal(n), "band", f, 2, f * 3) * 0.12
    env = adsr(n, 0.04, 0.2, 0.85, 0.12, gate=dur)
    chiff = np.exp(-t / 0.03) * 0.3
    return (out * env + breath * (env + chiff)) * (0.4 + 0.6 * vel)


def chip(f, dur, vel=0.8, duty_harm=True):
    """Soft, filtered pulse - a nod to the old chiptune score."""
    n = int((dur + 0.1) * SR)
    t = tarr(n)
    out = bl_square(f, t, 12)
    out = spectral(out, "lp", 2600, 2)
    return out * adsr(n, 0.005, 0.15, 0.6, 0.06, gate=dur) * 0.5 * (0.4 + 0.6 * vel)


def bass(f, dur, vel=0.8, bright=900.0):
    n = int((dur + 0.15) * SR)
    t = tarr(n)
    out = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.25 * bl_saw(f, t, 10)
    out = np.tanh(out * 1.3)
    out = spectral(out, "lp", bright, 2)
    return out * adsr(n, 0.004, 0.3, 0.75, 0.08, gate=dur) * (0.4 + 0.6 * vel)


def subbass(f, dur, vel=0.8):
    n = int((dur + 0.3) * SR)
    t = tarr(n)
    out = np.sin(2 * np.pi * f * t) + 0.1 * np.sin(4 * np.pi * f * t)
    return out * adsr(n, 0.02, 1.0, 1.0, 0.25, gate=dur) * (0.4 + 0.6 * vel)


def tuba(f, dur, vel=0.8):
    n = int((dur + 0.12) * SR)
    t = tarr(n)
    out = bl_saw(f, t, 14)
    out = spectral(out, "lp", 650, 2)
    return np.tanh(out * 1.6) * adsr(n, 0.03, 0.2, 0.7, 0.08, gate=dur) * (0.4 + 0.6 * vel)


# ---------------------------------------------------------------- drums

def kick(vel=1.0, tone=1.0):
    n = int(0.45 * SR)
    t = tarr(n)
    f = 45 * tone + 110 * np.exp(-t / 0.035)
    ph = np.cumsum(f) / SR
    out = np.sin(2 * np.pi * ph) * np.exp(-t / 0.18)
    click = np.random.default_rng(1).standard_normal(n) * np.exp(-t / 0.002) * 0.3
    return np.tanh((out + spectral(click, "lp", 4000)) * 1.5) * vel


def snare(vel=1.0, brush=False):
    n = int(0.35 * SR)
    t = tarr(n)
    rng = np.random.default_rng(2)
    nz = spectral(rng.standard_normal(n), "band", 1500 if not brush else 2500, 1, 9000)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    dec = 0.12 if not brush else 0.09
    out = (nz * np.exp(-t / dec) * (0.8 if not brush else 0.5) + body * (0.6 if not brush else 0.15))
    if brush:
        out *= np.clip(t / 0.01, 0, 1)
    return out * vel


def hat(vel=1.0, open_=False):
    n = int((0.35 if open_ else 0.08) * SR)
    t = tarr(n)
    nz = spectral(np.random.default_rng(3).standard_normal(n), "hp", 7000, 2)
    return nz * np.exp(-t / (0.12 if open_ else 0.022)) * 0.6 * vel


def shaker(vel=1.0):
    n = int(0.09 * SR)
    t = tarr(n)
    nz = spectral(np.random.default_rng(4).standard_normal(n), "band", 5000, 2, 11000)
    env = np.clip(t / 0.02, 0, 1) * np.exp(-t / 0.03)
    return nz * env * 0.6 * vel


def tom(vel=1.0, pitch=110.0):
    n = int(0.5 * SR)
    t = tarr(n)
    f = pitch * (1.0 + 0.6 * np.exp(-t / 0.04))
    ph = np.cumsum(f) / SR
    return np.sin(2 * np.pi * ph) * np.exp(-t / 0.22) * vel


def cymbal(vel=1.0):
    n = int(2.0 * SR)
    t = tarr(n)
    nz = spectral(np.random.default_rng(5).standard_normal(n), "hp", 4000, 1)
    return nz * np.exp(-t / 0.7) * 0.4 * vel


def clap(vel=1.0):
    n = int(0.3 * SR)
    t = tarr(n)
    nz = spectral(np.random.default_rng(6).standard_normal(n), "band", 1000, 2, 3000)
    env = np.zeros(n)
    for o in (0.0, 0.011, 0.022):
        tt = t - o
        env += np.where(tt >= 0, np.exp(-np.maximum(tt, 0) / 0.012), 0)
    env += np.exp(-np.maximum(t - 0.03, 0) / 0.08) * (t > 0.03)
    return nz * env * 0.5 * vel


DRUMS = {
    "k": lambda v: kick(v), "K": lambda v: kick(v * 1.2),
    "s": lambda v: snare(v), "S": lambda v: snare(v * 1.3),
    "b": lambda v: snare(v, brush=True),
    "h": lambda v: hat(v), "o": lambda v: hat(v, open_=True),
    "x": lambda v: shaker(v), "c": lambda v: cymbal(v), "p": lambda v: clap(v),
    "t": lambda v: tom(v, 140), "T": lambda v: tom(v, 95), "m": lambda v: tom(v, 70),
}


# ---------------------------------------------------------------- reverb

def reverb_ir(seconds=2.4, decay=0.9, damp=0.5, seed=7, predelay=0.012):
    n = int(seconds * SR)
    t = tarr(n)
    rng = np.random.default_rng(seed)
    out = []
    for ch in range(2):
        bright = rng.standard_normal(n)
        dark = spectral(rng.standard_normal(n), "lp", 2500 * (1.0 - damp) + 500, 1)
        env_b = np.exp(-t / (decay * 0.35))
        env_d = np.exp(-t / decay)
        ir = bright * env_b * 0.5 + dark * env_d
        ir *= np.clip(t / 0.01, 0, 1)
        pd = int(predelay * SR) + ch * 37
        ir = np.concatenate([np.zeros(pd), ir])[:n]
        out.append(ir / np.sqrt(np.sum(ir ** 2)))
    return out


def convolve(x, ir, circular=False):
    if circular:
        n = len(x)
        h = np.zeros(n)
        m = min(len(ir), n)
        h[:m] = ir[:m]
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)
    n = len(x) + len(ir) - 1
    nfft = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:n]


# ---------------------------------------------------------------- mixing helpers

class Bus:
    """Stereo mix bus of fixed length with a reverb send. If loop=True, writes
    wrap around the end so the result tiles seamlessly."""

    def __init__(self, n, loop=True):
        self.n = n
        self.loop = loop
        self.L = np.zeros(n)
        self.R = np.zeros(n)
        self.sL = np.zeros(n)
        self.sR = np.zeros(n)

    def add(self, sig, start, gain=1.0, pan=0.0, send=0.2):
        if len(sig) == 0:
            return
        start = int(start)
        lg = gain * math.cos((pan + 1) * math.pi / 4) * math.sqrt(2)
        rg = gain * math.sin((pan + 1) * math.pi / 4) * math.sqrt(2)
        if self.loop:
            idx = (np.arange(len(sig)) + start) % self.n
            np.add.at(self.L, idx, sig * lg)
            np.add.at(self.R, idx, sig * rg)
            if send > 0:
                np.add.at(self.sL, idx, sig * lg * send)
                np.add.at(self.sR, idx, sig * rg * send)
        else:
            end = min(self.n, start + len(sig))
            if end <= start:
                return
            s = sig[: end - start]
            self.L[start:end] += s * lg
            self.R[start:end] += s * rg
            if send > 0:
                self.sL[start:end] += s * lg * send
                self.sR[start:end] += s * rg * send

    def render(self, ir=None, master=0.85, lowcut=30.0, target_db=-16.0):
        L, R = self.L.copy(), self.R.copy()
        if ir is not None:
            L += convolve(self.sL, ir[0], circular=self.loop)[: self.n]
            R += convolve(self.sR, ir[1], circular=self.loop)[: self.n]
        L = spectral(L, "hp", lowcut, 1)
        R = spectral(R, "hp", lowcut, 1)
        peak = max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-9)
        # gentle glue: normalise into a soft-knee saturator
        L = np.tanh(L / peak * 1.25) / math.tanh(1.25)
        R = np.tanh(R / peak * 1.25) / math.tanh(1.25)
        # loudness: aim for target RMS, never let peaks pass 0.8 (codec headroom)
        rms = math.sqrt((np.mean(L ** 2) + np.mean(R ** 2)) / 2.0) + 1e-9
        g = (10 ** (target_db / 20.0)) / rms
        g = min(g, 0.8 / max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-9))
        return L * g * master / 0.85, R * g * master / 0.85


def write_wav(path, L, R=None):
    import wave
    import struct  # noqa: F401
    data = np.stack([L, R], axis=1) if R is not None else L[:, None]
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if R is not None else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
