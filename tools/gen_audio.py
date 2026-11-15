"""Synthesise the game's sound effects and chiptune music loops (no external assets needed).

Usage: python tools/gen_audio.py assets/audio      (requires numpy)
All files are 22.05 kHz mono 16-bit WAV. Loops are written so their ends join seamlessly.
"""
import sys, os, wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)

def t(sec): return np.arange(int(SR * sec)) / SR
def env(n, attack=0.005, release=0.1):
    e = np.ones(n)
    a = max(1, int(SR * attack)); r = max(1, int(SR * release))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e
def sq(freq, sec, duty=0.5):
    ph = (t(sec) * freq) % 1.0
    return np.where(ph < duty, 1.0, -1.0)
def tri(freq, sec):
    ph = (t(sec) * freq) % 1.0
    return 4 * np.abs(ph - 0.5) - 1
def noise(sec): return rng.uniform(-1, 1, int(SR * sec))
def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc); y[i] = acc
    return y
def note(n): return 440.0 * 2 ** ((n - 69) / 12)

def save(path, x, peak=0.8):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) or 1.0
    data = (x / m * peak * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

def seq(notes, step, wave_fn, gate=0.85, vol=1.0):
    """notes: list of midi numbers or None; returns signal of len(notes)*step seconds."""
    out = np.zeros(int(SR * step * len(notes)))
    for i, n in enumerate(notes):
        if n is None: continue
        seg = wave_fn(note(n), step * gate) * env(int(SR * step * gate), 0.004, step * gate * 0.5) * vol
        s = int(SR * step * i); seg = seg[:len(out) - s]; out[s:s + len(seg)] += seg
    return out

def effects(out):
    save(f"{out}/click.wav", sq(1100, 0.035, 0.25) * env(int(SR * 0.035), 0.001, 0.03), 0.45)
    save(f"{out}/toggle.wav", np.concatenate([sq(760, 0.03, 0.25), sq(1140, 0.04, 0.25)]) * env(int(SR * 0.07), 0.001, 0.04), 0.45)
    coin = np.concatenate([sq(note(83), 0.07, 0.25), sq(note(88), 0.22, 0.25)])
    save(f"{out}/coin.wav", coin * env(len(coin), 0.002, 0.18), 0.5)
    chime = sum(np.pad(tri(note(n), 0.5) * env(int(SR * 0.5), 0.003, 0.45), (int(SR * 0.09 * i), int(SR * 0.09 * (3 - i)))) for i, n in enumerate([72, 76, 79, 84]))
    save(f"{out}/research.wav", chime, 0.55)
    alert = np.concatenate([sq(880, 0.12, 0.5), np.zeros(int(SR * 0.06)), sq(880, 0.12, 0.5)])
    save(f"{out}/alert.wav", alert * env(len(alert), 0.002, 0.03), 0.4)
    # Engine rumble loop: low-passed noise plus a low hum, 2 s, ends cross-faded.
    n = lowpass(noise(2.2), 0.05) * 3 + 0.25 * np.sin(2 * np.pi * 55 * t(2.2))
    fade = int(SR * 0.2)
    loop = n[:int(SR * 2.0)].copy()
    loop[:fade] = loop[:fade] * np.linspace(0, 1, fade) + n[int(SR * 2.0):int(SR * 2.0) + fade] * np.linspace(1, 0, fade)
    save(f"{out}/engine_loop.wav", loop, 0.55)
    h = lowpass(noise(1.2), 0.35)
    hl = h[:int(SR * 1.0)].copy()
    hl[:fade] = hl[:fade] * np.linspace(0, 1, fade) + h[int(SR * 1.0):int(SR * 1.0) + fade] * np.linspace(1, 0, fade)
    save(f"{out}/thruster_loop.wav", hl, 0.35)
    thump = np.sin(2 * np.pi * 70 * t(0.35)) * np.exp(-t(0.35) * 12) + lowpass(noise(0.35), 0.2) * np.exp(-t(0.35) * 25)
    save(f"{out}/touchdown.wav", thump, 0.7)
    boom = lowpass(noise(1.4), 0.12) * np.exp(-t(1.4) * 3.2) * 2 + np.sin(2 * np.pi * 45 * t(1.4)) * np.exp(-t(1.4) * 4)
    save(f"{out}/crash.wav", boom, 0.8)
    win = seq([72, 76, 79, 84, None, 79, 84], 0.11, lambda f, s: sq(f, s, 0.25))
    save(f"{out}/success.wav", win, 0.5)
    lose = seq([67, 63, 60, 55], 0.18, lambda f, s: tri(f, s))
    save(f"{out}/fail.wav", lose, 0.5)

def music(out):
    # Calm base theme: Am–F–C–G arpeggios over a soft triangle bass. 8 bars of 4 beats at 96 BPM.
    beat = 60 / 96
    prog = [(57, [69, 72, 76]), (53, [65, 69, 72]), (48, [64, 67, 72]), (55, [62, 67, 71])] * 2
    arp, bass, lead = [], [], []
    melody = [76, None, 74, 72, 72, None, 69, None, 72, None, 74, 76, 74, None, None, None,
              76, None, 77, 79, 77, None, 76, 74, 72, None, 74, None, 71, None, None, None]
    for b, (root, chord) in enumerate(prog):
        for i in range(8): arp.append(chord[i % 3] + (12 if i >= 4 else 0))
        bass += [root - 12, None, root - 12, None]
    for m in melody: lead += [m, None]
    base = seq(arp, beat / 2, lambda f, s: sq(f, s, 0.125), vol=0.25) + seq(bass, beat, tri, vol=0.55) \
        + seq(lead, beat / 2, lambda f, s: sq(f, s, 0.5), gate=0.9, vol=0.22)
    save(f"{out}/music_base.wav", base, 0.5)
    # Flight theme: driving eighth-note bass and a brighter arpeggio, 124 BPM.
    beat = 60 / 124
    prog = [(45, [69, 72, 76]), (41, [69, 72, 77]), (43, [67, 71, 74]), (40, [68, 71, 76])] * 2
    arp, bass = [], []
    for root, chord in prog:
        for i in range(8): arp.append(chord[[0, 1, 2, 1][i % 4]] + 12 * (i // 4))
        bass += [root, root, root + 12, root] * 2
    flight = seq(arp, beat / 2, lambda f, s: sq(f, s, 0.25), vol=0.22) + seq(bass, beat / 2, tri, gate=0.7, vol=0.6)
    kick = np.zeros_like(flight)
    for i in range(int(len(prog) * 4)):
        s = int(SR * beat * i); k = np.sin(2 * np.pi * 60 * t(0.12)) * np.exp(-t(0.12) * 30)
        kick[s:s + len(k)] += k * 0.5
    save(f"{out}/music_flight.wav", flight + kick, 0.5)
    # Landing theme: tense pulse on one low note with slow suspended chords, 80 BPM.
    beat = 60 / 80
    pulse = seq([45, None, 45, None] * 16, beat / 2, tri, gate=0.5, vol=0.6)
    pads = seq([v for c in [64, 65, 62, 63] * 2 for v in [c] + [None] * 7], beat / 2, lambda f, s: sq(f, s, 0.5), gate=3.5, vol=0.12)
    pads = pads[:len(pulse)] if len(pads) >= len(pulse) else np.pad(pads, (0, len(pulse) - len(pads)))
    save(f"{out}/music_landing.wav", pulse + pads, 0.5)

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    effects(out)
    music(out)
    print("written to", out)
