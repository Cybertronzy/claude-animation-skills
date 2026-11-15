#!/usr/bin/env bash
# Add a corner "channel bug" over the opening hook + a punchy FOLLOW outro card
# to a finished reel, without ever delaying the hook itself.
#
#   add_intro_outro.sh <input.mp4> <output.mp4> "<handle>" ["<cta line 2>"]
#
# Why it's built this way (see the research notes it's based on):
#   - The first 3 seconds of a short decide most of its performance, so this
#     script never prepends a title card before the hook - that would bury
#     the exact moment viewers decide to stay. Instead the brand mark is a
#     small, fast-in/fast-out corner bug sitting over the hook, never on it.
#   - Outro CTA retention is brutal (viewers bail in the first couple of
#     seconds of an end card), so the FOLLOW badge and text are fully visible
#     immediately - no slow fade-in - just a quick confident pop.
#   - The video->outro cut uses a 0.5s crossfade (the 0.4-0.8s sweet spot),
#     not a hard cut or a slow dissolve, with a synced audio sting so the
#     CTA lands with its own little punctuation mark.
set -euo pipefail

IN="${1:?usage: add_intro_outro.sh <input.mp4> <output.mp4> <handle> [cta2]}"
OUT="${2:?usage: add_intro_outro.sh <input.mp4> <output.mp4> <handle> [cta2]}"
HANDLE="${3:-@yourhandle}"
CTA2="${4:-FOR MORE}"
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

echo "== building overlays (bug, follow badge, sting)"
"$PYBIN" "$HERE/overlays.py" bug   "$WORK/bug.png"   "$HANDLE"
"$PYBIN" "$HERE/overlays.py" badge "$WORK/badge.png" "FOLLOW" "$CTA2"
"$PYBIN" "$HERE/sting.py" "$WORK/sting.wav"

# ---------- 1) corner bug over the opening hook (first 4s, never earlier shots) ----------
echo "== compositing the corner bug onto the main clip"
ffmpeg -v error -y -i "$IN" -loop 1 -t "$DUR" -i "$WORK/bug.png" -filter_complex "
  [1:v]format=rgba,
       fade=t=in:st=0:d=0.35:alpha=1,
       fade=t=out:st=3.6:d=0.4:alpha=1[bug];
  [0:v][bug]overlay=
       x='W-w-36':
       y='if(lt(t,0.35),60-44*(1-t/0.35),60)':
       enable='between(t,0,4)':
       shortest=1[v]
" -map "[v]" -map 0:a -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p \
   -c:a copy "$WORK/main_with_bug.mp4"

# ---------- 2) outro clip: freeze last frame, slow zoom, instant CTA ----------
echo "== building the outro card"
ffmpeg -v error -y -sseof -0.1 -i "$IN" -frames:v 1 "$WORK/last.png"
OUTRO_SEC=2.6
OUTRO_FRAMES="$(awk -v s="$OUTRO_SEC" -v f="$FPS" 'BEGIN{printf "%.0f", s*f}')"
[ "$OUTRO_FRAMES" -gt 0 ] 2>/dev/null || OUTRO_FRAMES=78

# Build the big caption-matching CTA line from the handle's own CTA text (falls
# back to "FOR MORE" if none given) instead of a hardcoded phrase, and shrink
# the font a bit for a longer CTA so it never runs off the 1080px width.
CTA_LINE="$(printf '%s' "FOLLOW ${CTA2}" | tr -d "\\\\:'")"
CTA_FONTSIZE="$(awk -v n="${#CTA_LINE}" 'BEGIN{fs=78; if (n>16) fs=78*16/n; if (fs<44) fs=44; printf "%.0f", fs}')"

ffmpeg -v error -y -loop 1 -i "$WORK/last.png" -loop 1 -i "$WORK/badge.png" -filter_complex "
  [0:v]scale=${W}:${H},
       eq=brightness=-0.10:saturation=0.85,
       zoompan=z='min(zoom+0.0018,1.09)':d=${OUTRO_FRAMES}:s=${W}x${H}:fps=${FPS},
       format=yuv420p[bg];
  [1:v]format=rgba,
       scale=w='if(lt(t,0.15),560*(t/0.15),560+26*sin(2*PI*(t-0.15)*1.6))':h=-1:eval=frame[badge];
  [bg][badge]overlay=x=(W-w)/2:y=H*0.30-h/2:shortest=1[withbadge];
  [withbadge]drawtext=fontfile=$FONT:text='${CTA_LINE}':
       fontsize=${CTA_FONTSIZE}:fontcolor=white:bordercolor=0x221c22:borderw=8:
       x=(w-text_w)/2:y=H*0.74[v]
" -map "[v]" -frames:v "$OUTRO_FRAMES" -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p -an "$WORK/outro.mp4"

# ---------- 3) crossfade main (with bug) into outro, sting synced to the cut ----------
echo "== crossfading into the outro and syncing the sting"
XFD=0.5
MAIN_DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/main_with_bug.mp4")"
OFFSET="$(awk -v d="$MAIN_DUR" -v x="$XFD" 'BEGIN{printf "%.3f", d-x}')"
STING_MS="$(awk -v d="$MAIN_DUR" 'BEGIN{printf "%.0f", (d-0.08)*1000}')"

ffmpeg -v error -y -i "$WORK/main_with_bug.mp4" -i "$WORK/outro.mp4" -i "$WORK/sting.wav" -filter_complex "
  [0:v][1:v]xfade=transition=fade:duration=${XFD}:offset=${OFFSET}[v];
  [0:a]apad=pad_dur=${OUTRO_SEC}[a0];
  [2:a]adelay=${STING_MS}|${STING_MS}[sting];
  [a0][sting]amix=inputs=2:duration=first:normalize=0,
  alimiter=limit=0.9:attack=2:release=60[a]
" -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p \
   -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT.part.mp4"
mv "$OUT.part.mp4" "$OUT"
echo "done: $OUT"
