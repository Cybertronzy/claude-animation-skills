#!/usr/bin/env python3
"""
Free single-line voiceover with Kokoro, for branding assets that don't
belong to a reel's own script.json/audio pipeline - specifically the
spoken Q2 comment-prompt line mixed into the outro card by
add_intro_outro.sh. Same model/voice as the main reel VO (tts_kokoro.py)
so it sounds like the same narrator, not a bolted-on text-to-speech clip.

Usage: tts_line.py "<text>" <out.wav> [voice] [speed]
  defaults: am_michael 1.12 (match the stick-figure engine's default)
"""
import sys, os, shutil, tempfile
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.realpath(__file__))
KIT = os.path.dirname(HERE)  # kit/post -> kit (voice models live in kit/models)

from kokoro_onnx import Kokoro, EspeakConfig
import espeakng_loader

# espeak-ng fails on a long data path (deep install folders), so use a copy
# at a short path when needed - same workaround as tts_kokoro.py
data = espeakng_loader.get_data_path()
if len(data) > 100:
    short = os.path.join(tempfile.gettempdir(), "kokoro-espeak-ng-data")
    if not os.path.exists(os.path.join(short, "phontab")):
        shutil.rmtree(short, ignore_errors=True)
        shutil.copytree(data, short)
    data = short
espeak = EspeakConfig(lib_path=espeakng_loader.get_library_path(), data_path=data)

text = sys.argv[1]
out_path = sys.argv[2]
voice = sys.argv[3] if len(sys.argv) > 3 else "am_michael"
speed = float(sys.argv[4]) if len(sys.argv) > 4 else 1.12

k = Kokoro(os.path.join(KIT, "models/kokoro-v1.0.onnx"), os.path.join(KIT, "models/voices-v1.0.bin"), espeak_config=espeak)
samples, sr = k.create(text, voice=voice, speed=speed, lang="en-us")
a = np.abs(samples)
idx = np.where(a > 0.01)[0]
samples = samples[max(0, idx[0] - int(0.02 * sr)): idx[-1] + int(0.05 * sr)]
sf.write(out_path, samples, sr)
print(f"{len(samples) / sr:.2f}s -> {out_path}")
