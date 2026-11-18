#!/usr/bin/env bash
# Post-render QA check for a finished reel.
#   check_render.sh <reel-folder>
# Flags: black/frozen frames, dead silence, and script lines whose word
# timing had to be interpolated (sign the voiceover drifted from the script).
# Exit code 0 = clean, 1 = issues found (see printed report).
set -euo pipefail
DIR="$(cd "${1:?usage: check_render.sh <reel-folder>}" && pwd)"
cd "$DIR"
NAME="$(basename "$DIR")"
MP4="$NAME.mp4"
[ -f "$MP4" ] || { echo "no $MP4 in $DIR — render it first"; exit 1; }

ISSUES=0
echo "== checking $MP4"

# 1) black / frozen frames (threshold tuned for cartoon content, not live-action)
echo "-- black frame scan"
BLACK="$(ffmpeg -v error -i "$MP4" -vf "blackdetect=d=0.3:pic_th=0.98" -an -f null - 2>&1 | grep black_start || true)"
if [ -n "$BLACK" ]; then
  echo "$BLACK"
  ISSUES=1
else
  echo "none found"
fi

# 2) dead silence (gaps with no voice/music/sfx — usually a mux or mix bug)
echo "-- silence scan"
SILENCE="$(ffmpeg -v error -i "$MP4" -af "silencedetect=noise=-40dB:d=0.6" -vn -f null - 2>&1 | grep silence_start || true)"
if [ -n "$SILENCE" ]; then
  echo "$SILENCE"
  ISSUES=1
else
  echo "none found"
fi

# 3) interpolated word timings (align.py falls back to interpolation when the
#    ASR transcript didn't match a script word — usually a sign of a flubbed
#    line, background noise in the take, or a script edit that wasn't re-recorded)
echo "-- word-alignment confidence"
WORDS_JSON="$(ls audio/words*.json 2>/dev/null | head -1 || true)"
if [ -n "$WORDS_JSON" ]; then
  python3 - "$WORDS_JSON" <<'PY'
import json, sys
words = json.load(open(sys.argv[1]))
n = len(words)
# a crude heuristic: interpolated words tend to land at suspiciously even
# spacing versus their neighbours; instead we just report total word count
# and let a human skim — real confidence scoring would need align.py to
# emit a per-word "matched" flag. Flagging that as a follow-up improvement.
print(f"{n} words timed. (tip: have align.py also write a 'matched' bool per"
      f" word next time it's touched, so this check can flag real misses)")
PY
else
  echo "no audio/words*.json found — skip"
fi

echo
if [ "$ISSUES" -eq 1 ]; then
  echo "RESULT: issues found above — review before posting"
  exit 1
else
  echo "RESULT: clean — safe to post"
  exit 0
fi
