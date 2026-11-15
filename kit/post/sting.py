#!/usr/bin/env python3
"""
Procedural "follow" sting for the outro: a quick confirming pop + a bright
upward chime, built the same way the stick-figure skill builds its own SFX
(numpy oscillators/noise through butterworth filters) so the outro doesn't
need any external sample and matches the show's existing sound language.

Usage: python3 sting.py <out.wav>
"""
import sys
import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100


def T(n):
    return np.arange(n) / SR


def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def pop(f=700, dur=0.09):
    n = int(dur * SR)
    t = T(n)
    x = np.sin(2 * np.pi * f * (1 + 4 * np.exp(-t * 40)) * t)
    return x * np.exp(-t * 28)


def chime(freqs, dur=0.65):
    n = int(dur * SR)
    t = T(n)
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        x += (1 - i * 0.15) * np.sin(2 * np.pi * f * t)
    env = np.exp(-t * 4.2) * np.minimum(1, t / 0.004)
    return x * env * 0.5


def whoosh_tail(dur=0.25):
    n = int(dur * SR)
    rng = np.random.default_rng(7)
    x = rng.standard_normal(n)
    x = hp(lp(x, 5000), 1200)
    e = np.exp(-T(n) * 14)
    return x * e * 0.35


def build(out_path):
    total = int(1.1 * SR)
    buf = np.zeros(total)

    def place(x, at, g=1.0):
        i = int(at * SR)
        j = min(total, i + len(x))
        if i < total:
            buf[i:j] += x[: j - i] * g

    # confirming double-pop, then a bright major-chord chime ringing out
    place(pop(620), 0.00, 0.9)
    place(pop(900), 0.07, 0.8)
    place(chime([880.0, 1108.7, 1318.5, 1760.0]), 0.10, 0.9)
    place(whoosh_tail(), 0.02, 0.5)

    peak = np.max(np.abs(buf)) or 1.0
    buf = buf / peak * 0.92
    sf.write(out_path, buf.astype(np.float32), SR)


if __name__ == "__main__":
    build(sys.argv[1])
