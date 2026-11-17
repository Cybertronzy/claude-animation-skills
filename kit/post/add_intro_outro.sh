#!/usr/bin/env bash
# Add a corner "channel bug" over the opening hook + a punchy FOLLOW outro card
# to a finished reel, without ever delaying the hook itself.
#
#   add_intro_outro.sh <input.mp4> <output.mp4> "<handle>" ["<cta line 2>"] ["<Q2 comment prompt>"]
#
#   Q2 is both spoken and shown: the narrator (same Kokoro voice as the reel
#   itself) asks it out loud plus a "comment below" invite, the outro card
#   holds long enough to fit that line, and the on-screen text pops in sized
#   to actually read at a glance, not as a small secondary caption.
#
# Why it's built this way (see the research notes it's based on):
#   - The first 3 seconds of a short decide most of its performance, so this
#     script never prepends a title card before the hook - that would bury
#     the exact moment viewers decide to stay. Instead the brand mark is a
#     small corner watermark (logo glyph + handle) that pops in fast over
#     the hook and then stays, dimmed slightly, for the rest of the video.
#   - Outro CTA retention is brutal (viewers bail in the first couple of
#     seconds of an end card), so the FOLLOW badge and text are fully visible
#     immediately - no slow fade-in - just a quick confident pop.
#   - The video->outro cut uses a 0.5s crossfade (the 0.4-0.8s sweet spot),
#     not a hard cut or a slow dissolve, with a synced audio sting so the
#     CTA lands with its own little punctuation mark.
#   - The HuhTronz Question Pair's Q2 (the pinned-comment prompt) is burned
#     into the outro card itself, under the FOLLOW CTA, so viewers who never
#     open the comments still see what to answer - the platform pinned
#     comment is still worth posting too, but the on-screen cue is what
#     actually drives taps from people scrolling with sound off.
set -euo pipefail

IN="${1:?usage: add_intro_outro.sh <input.mp4> <output.mp4> <handle> [cta2] [q2]}"
OUT="${2:?usage: add_intro_outro.sh <input.mp4> <output.mp4> <handle> [cta2] [q2]}"
HANDLE="${3:-@yourhandle}"
CTA2="${4:-FOR MORE}"
Q2_RAW="${5:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYBIN="${PYBIN:-python3}"
FONT="$HERE/assets/Poppins-Bold.ttf"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== probing $IN"
read -r W H FPS < <(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate -of csv=p=0 "$IN" | \
  awk -F',' '{split($3,f,"/"); printf "%s %s %.0f\n",$1,$2,(f[2]>0?f[1]/f[2]:30)}')
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")"
echo "   ${W}x${H} @ ${FPS}fps, ${DUR}s"

echo "== building overlays (watermark, follow badge, open+close stings)"
"$PYBIN" "$HERE/overlays.py" watermark "$WORK/bug.png"   "$HANDLE"
"$PYBIN" "$HERE/overlays.py" badge     "$WORK/badge.png" "FOLLOW" "$CTA2"
"$PYBIN" "$HERE/sting.py" open  "$WORK/sting_open.wav"
"$PYBIN" "$HERE/sting.py" close "$WORK/sting_close.wav"

TTS_PY="$PYBIN"
[ -x "$HERE/../.venv/bin/python" ] && TTS_PY="$HERE/../.venv/bin/python"

# Q2's spoken version: the same text, slashes read naturally ("Yes/No" ->
# "Yes or No"), plus a fixed invite to comment - generated once here so
# every reel's Q1/Q2 bank entry doesn't need its own comment-CTA wording.
Q2_VO_DUR=0
if [ -n "$Q2_RAW" ]; then
  echo "== synthesizing the spoken Q2 comment prompt"
  Q2_SPOKEN="$(printf '%s' "$Q2_RAW" | tr -d "\\\\:'" | sed 's#/# or #g')"
  Q2_SPOKEN="${Q2_SPOKEN} Let us know in the comments!"
  "$TTS_PY" "$HERE/tts_line.py" "$Q2_SPOKEN" "$WORK/q2_vo.wav"
  Q2_VO_DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/q2_vo.wav")"
fi

# Sign-off line, always spoken at the very end of the card, after Q2 (when
# there is one) - the last thing anyone hears before the video ends.
echo "== synthesizing the closing sign-off"
SIGNOFF="Follow HuhTronz for more! Let's meet again in our next video. Have a great time!"
"$TTS_PY" "$HERE/tts_line.py" "$SIGNOFF" "$WORK/signoff_vo.wav"
SIGNOFF_DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/signoff_vo.wav")"

# ---------- 1) persistent top-right watermark (logo glyph + handle) over the whole
#              main clip, not just the opening hook - it pops in once, then stays.
#              A quick open sting is mixed in right as the bug pops in, so every
#              reel opens and closes on the same two-part audio signature ----------
echo "== compositing the persistent top-right watermark + open sting onto the main clip"
ffmpeg -v error -y -i "$IN" -loop 1 -t "$DUR" -i "$WORK/bug.png" -i "$WORK/sting_open.wav" -filter_complex "
  [1:v]format=rgba,
       fade=t=in:st=0:d=0.35:alpha=1[bug];
  [0:v][bug]overlay=
       x='W-w-36':
       y='if(lt(t,0.35),60-44*(1-t/0.35),60)':
       shortest=1[v];
  [2:a]adelay=40|40[stingopen];
  [0:a][stingopen]amix=inputs=2:duration=first:normalize=0,
       alimiter=limit=0.95:attack=2:release=60[a]
" -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p \
   -c:a aac -b:a 192k -ar 48000 "$WORK/main_with_bug.mp4"

# ---------- 2) outro clip: freeze last frame, slow zoom, instant CTA ----------
echo "== building the outro card"
ffmpeg -v error -y -sseof -0.1 -i "$IN" -frames:v 1 "$WORK/last.png"
# The card has to hold long enough for the spoken Q2 line (if any) plus
# the closing sign-off that always plays after it, with a beat before
# each and a tail pad before the cut - otherwise it's business as usual,
# 2.6s. LEAD_IN/GAP/TAIL below must match the delay math in step 3.
OUTRO_SEC="$(awk -v q="$Q2_VO_DUR" -v s="$SIGNOFF_DUR" 'BEGIN{
  lead=0.5; gap=(q>0)?0.4:0; tail=0.6
  need = lead + q + gap + s + tail
  out = (need>2.6) ? need : 2.6
  printf "%.2f", out
}')"
OUTRO_FRAMES="$(awk -v s="$OUTRO_SEC" -v f="$FPS" 'BEGIN{printf "%.0f", s*f}')"
[ "$OUTRO_FRAMES" -gt 0 ] 2>/dev/null || OUTRO_FRAMES=78

# Build the big caption-matching CTA line from the handle's own CTA text (falls
# back to "FOR MORE" if none given) instead of a hardcoded phrase, and shrink
# the font a bit for a longer CTA so it never runs off the 1080px width.
CTA_LINE="$(printf '%s' "FOLLOW ${CTA2}" | tr -d "\\\\:'")"
CTA_FONTSIZE="$(awk -v n="${#CTA_LINE}" 'BEGIN{fs=78; if (n>16) fs=78*16/n; if (fs<44) fs=44; printf "%.0f", fs}')"

# Q2 (the pinned-comment prompt): clean it the same way as the CTA line, split
# it onto up to two lines at the first sentence break so a longer prompt still
# fits. It now sits ABOVE the FOLLOW CTA (it's the thing we actually want
# someone to act on) and bigger still than the last pass - a product cap of
# ~1450 (fontsize*chars) instead of ~1620, so it only scales down for a
# genuinely long prompt.
Q2_FILTER=""
CTA_Y="H*0.74"   # default (no-Q2) position - same as the original single-CTA layout
if [ -n "$Q2_RAW" ]; then
  Q2_CLEAN="$(printf '%s' "$Q2_RAW" | tr -d "\\\\:'")"
  # Wrap into 1-3 lines and pick a fontsize that is GUARANTEED to fit the
  # 1080px frame (checked against an actual measured glyph width via
  # PIL/the real font, not a fixed char-count floor) rather than assuming a
  # fixed minimum fontsize is always safe - a long single-sentence question
  # with punctuation only at the very end previously produced a 2-line split
  # whose min fontsize (44) still overflowed the frame on both edges. This
  # now balances across up to 3 lines and shrinks the font until it
  # genuinely fits, so any length of Q2 prompt renders fully on-screen.
  mapfile -t Q2_LINES < <("$PYBIN" -c "
import sys
try:
    from PIL import ImageFont
    font_path = sys.argv[2]
    have_pil = True
except Exception:
    have_pil = False

s = sys.argv[1]
safe_w = 980  # usable width inside the 1080px frame, with margin

def balanced_wrap(words, k):
    if k <= 1:
        return [' '.join(words)]
    target = len(' '.join(words)) / k
    lines, cur, cur_len = [], [], 0
    for w in words:
        add = len(w) + (1 if cur else 0)
        if cur and cur_len + add > target and len(lines) < k - 1:
            lines.append(' '.join(cur)); cur = [w]; cur_len = len(w)
        else:
            cur.append(w); cur_len += add
    lines.append(' '.join(cur))
    return lines

def text_width(line, fontsize):
    if have_pil:
        try:
            f = ImageFont.truetype(font_path, fontsize)
            b = f.getbbox(line)
            return b[2] - b[0]
        except Exception:
            pass
    return len(line) * fontsize * 0.58  # fallback estimate

words = s.split(' ')
best = None
for k in (1, 2, 3):
    lines = balanced_wrap(words, k)
    fs = 66
    while fs > 28:
        if max(text_width(l, fs) for l in lines) <= safe_w:
            break
        fs -= 2
    max_w = max(text_width(l, fs) for l in lines)
    score = (max_w > safe_w, -fs, k)  # prefer: fits, then biggest font, then fewest lines
    if best is None or score < best[0]:
        best = (score, lines, fs)
if best is None:
    best = ((False, -28, 1), [s], 28)
_, lines, fs = best
print(fs)
for l in lines:
    print(l)
" "$Q2_CLEAN" "$FONT")
  Q2_FONTSIZE="${Q2_LINES[0]}"
  Q2_LINE1="${Q2_LINES[1]:-}"
  Q2_LINE2="${Q2_LINES[2]:-}"
  Q2_LINE3="${Q2_LINES[3]:-}"
  CMT_FONTSIZE=38
  # Text pops in right as the narrator starts asking it (1s into the card,
  # same instant as the Q2 VO's adelay below), not sitting there the whole
  # time competing with the FOLLOW badge for attention.
  Q2_ALPHA="alpha='if(lt(t,1.0),0,1)'"
  Q2_Y0="H*0.70"
  Q2_Y1="(H*0.70+${Q2_FONTSIZE}*1.25)"
  Q2_Y2="(H*0.70+${Q2_FONTSIZE}*2.50)"
  if [ -n "$Q2_LINE3" ]; then
    Q2_Y_LAST="$Q2_Y2"
  elif [ -n "$Q2_LINE2" ]; then
    Q2_Y_LAST="$Q2_Y1"
  else
    Q2_Y_LAST="$Q2_Y0"
  fi
  CMT_Y="(${Q2_Y_LAST}+${Q2_FONTSIZE}*1.55)"
  CTA_Y="(${CMT_Y}+${CMT_FONTSIZE}*1.7)"
  Q2_FILTER=";[v1]drawtext=fontfile=$FONT:text='${Q2_LINE1}':
       fontsize=${Q2_FONTSIZE}:fontcolor=0xFFD166:bordercolor=0x221c22:borderw=7:${Q2_ALPHA}:
       x=(w-text_w)/2:y=${Q2_Y0}[v2]"
  if [ -n "$Q2_LINE2" ]; then
    Q2_FILTER="${Q2_FILTER};[v2]drawtext=fontfile=$FONT:text='${Q2_LINE2}':
       fontsize=${Q2_FONTSIZE}:fontcolor=0xFFD166:bordercolor=0x221c22:borderw=7:${Q2_ALPHA}:
       x=(w-text_w)/2:y=${Q2_Y1}[v2b]"
  else
    Q2_FILTER="${Q2_FILTER};[v2]null[v2b]"
  fi
  if [ -n "$Q2_LINE3" ]; then
    Q2_FILTER="${Q2_FILTER};[v2b]drawtext=fontfile=$FONT:text='${Q2_LINE3}':
       fontsize=${Q2_FONTSIZE}:fontcolor=0xFFD166:bordercolor=0x221c22:borderw=7:${Q2_ALPHA}:
       x=(w-text_w)/2:y=${Q2_Y2}[v3]"
  else
    Q2_FILTER="${Q2_FILTER};[v2b]null[v3]"
  fi
  Q2_FILTER="${Q2_FILTER};[v3]drawtext=fontfile=$FONT:text='COMMENT BELOW':
       fontsize=${CMT_FONTSIZE}:fontcolor=white:bordercolor=0x221c22:borderw=5:${Q2_ALPHA}:
       x=(w-text_w)/2:y=${CMT_Y}[v4]"
else
  Q2_FILTER=";[v1]null[v4]"
fi

ffmpeg -v error -y -loop 1 -i "$WORK/last.png" -loop 1 -i "$WORK/badge.png" -filter_complex "
  [0:v]scale=${W}:${H},
       eq=brightness=-0.10:saturation=0.85,
       zoompan=z='min(zoom+0.0018,1.09)':d=${OUTRO_FRAMES}:s=${W}x${H}:fps=${FPS},
       format=yuv420p[bg];
  [1:v]format=rgba,
       scale=w='if(lt(t,0.15),560*(t/0.15),560+26*sin(2*PI*(t-0.15)*1.6))':h=-1:eval=frame[badge];
  [bg][badge]overlay=x=(W-w)/2:y=H*0.30-h/2:shortest=1[withbadge];
  [withbadge]null[v1]${Q2_FILTER};
  [v4]drawtext=fontfile=$FONT:text='${CTA_LINE}':
       fontsize=${CTA_FONTSIZE}:fontcolor=white:bordercolor=0x221c22:borderw=8:
       x=(w-text_w)/2:y=${CTA_Y}[v]
" -map "[v]" -frames:v "$OUTRO_FRAMES" -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p -an "$WORK/outro.mp4"

# ---------- 3) crossfade main (with bug) into outro, sting synced to the cut ----------
echo "== crossfading into the outro and syncing the close sting"
XFD=0.5
MAIN_DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/main_with_bug.mp4")"
OFFSET="$(awk -v d="$MAIN_DUR" -v x="$XFD" 'BEGIN{printf "%.3f", d-x}')"
STING_MS="$(awk -v d="$MAIN_DUR" 'BEGIN{printf "%.0f", (d-0.08)*1000}')"
# Q2 VO starts 0.5s after the true cut (same instant, in the outro card's
# own clock, as the text popping in at t=1.0 there - OFFSET is 0.5s before
# MAIN_DUR, so outro-local t=1.0 lands exactly at MAIN_DUR+0.5 here). The
# sign-off follows it (or, with no Q2, starts at that same lead-in point).
Q2_VO_MS="$(awk -v d="$MAIN_DUR" 'BEGIN{printf "%.0f", (d+0.5)*1000}')"
SIGNOFF_MS="$(awk -v d="$MAIN_DUR" -v q="$Q2_VO_DUR" 'BEGIN{
  gap=(q>0)?0.4:0
  printf "%.0f", (d+0.5+q+gap)*1000
}')"

if [ -n "$Q2_RAW" ]; then
  ffmpeg -v error -y -i "$WORK/main_with_bug.mp4" -i "$WORK/outro.mp4" -i "$WORK/sting_close.wav" -i "$WORK/q2_vo.wav" -i "$WORK/signoff_vo.wav" -filter_complex "
    [0:v][1:v]xfade=transition=fade:duration=${XFD}:offset=${OFFSET}[v];
    [0:a]apad=pad_dur=${OUTRO_SEC}[a0];
    [2:a]adelay=${STING_MS}|${STING_MS}[sting];
    [3:a]adelay=${Q2_VO_MS}|${Q2_VO_MS}[q2vo];
    [4:a]adelay=${SIGNOFF_MS}|${SIGNOFF_MS}[signoff];
    [a0][sting][q2vo][signoff]amix=inputs=4:duration=first:normalize=0,
    alimiter=limit=0.9:attack=2:release=60[a]
  " -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p \
     -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT.part.mp4"
else
  ffmpeg -v error -y -i "$WORK/main_with_bug.mp4" -i "$WORK/outro.mp4" -i "$WORK/sting_close.wav" -i "$WORK/signoff_vo.wav" -filter_complex "
    [0:v][1:v]xfade=transition=fade:duration=${XFD}:offset=${OFFSET}[v];
    [0:a]apad=pad_dur=${OUTRO_SEC}[a0];
    [2:a]adelay=${STING_MS}|${STING_MS}[sting];
    [3:a]adelay=${SIGNOFF_MS}|${SIGNOFF_MS}[signoff];
    [a0][sting][signoff]amix=inputs=3:duration=first:normalize=0,
    alimiter=limit=0.9:attack=2:release=60[a]
  " -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p \
     -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT.part.mp4"
fi
mv "$OUT.part.mp4" "$OUT"
echo "done: $OUT"
