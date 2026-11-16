#!/usr/bin/env python3
"""
Procedural brand stings for the open and close of every reel, built the same
way the stick-figure skill builds its own SFX (numpy oscillators/noise
through butterworth filters) so neither needs an external sample and both
match the show's existing sound language. The open and close share the same
pop/chime vocabulary so they read as one audio signature, not two unrelated
sounds - "open" is a quick single confirming tick synced to the watermark's
pop-in; "close" is the fuller double-pop + chime synced to the outro cut.

Usage: python3 sting.py open <out.wav>
       python3 sting.py close <out.wav>
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


def _write(buf, total, out_path):
    buf = buf[:total]
    peak = np.max(np.abs(buf)) or 1.0
    buf = buf / peak * 0.92
    sf.write(out_path, buf.astype(np.float32), SR)


def build_close(out_path):
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

    _write(buf, total, out_path)


def build_open(out_path):
    # a lighter sibling of the close sting: one confirming tick plus a
    # quick rising two-note chirp, synced to the watermark's pop-in rather
    # than a full outro moment - same vocabulary (pop + chime), smaller scale
    total = int(0.42 * SR)
    buf = np.zeros(total)

    def place(x, at, g=1.0):
        i = int(at * SR)
        j = min(total, i + len(x))
        if i < total:
            buf[i:j] += x[: j - i] * g

    place(pop(760), 0.00, 0.85)
    place(chime([1108.7, 1760.0]), 0.03, 0.55)

    _write(buf, total, out_path)


if __name__ == "__main__":
    mode, out = (sys.argv[1], sys.argv[2]) if len(sys.argv) > 2 else ("close", sys.argv[1])
    (build_open if mode == "open" else build_close)(out)
