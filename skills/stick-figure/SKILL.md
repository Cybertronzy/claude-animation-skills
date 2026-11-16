---
name: stick-figure
description: Makes a code-animated stick-figure explainer reel (9:16, 30 to 45 s) from a question or topic. A bright cartoon world with thick outlines, stick people with big white heads and faces, constant camera motion, whip transitions, 1 to 2 word captions, a playful underscore and cartoon sound effects, all generated in code and timed to the voiceover word by word. Use when the user runs /stick-figure or asks for a stick-figure, stickman or cartoon "what if" explainer.
---

# /stick-figure

```
┌──────────────────────┐
│   ☀      ☁           │  bright sky, sea, props drawn in code
│      ◯   ◯           │  stick people with big white heads, expressive faces
│     /|\ /|\          │
│     / \ / \  🛢       │
│     eye patch        │  1-2 word captions, lowercase, ~70% down
└──────────────────────┘
```

A worked example comes with it: `engine/template` is a finished 37 s reel, "What if pirate eye patches had nothing to do with missing eyes?"

## First use
This skill's folder is the "Base directory" Claude Code shows when it loads it.
```bash
SKILL_DIR="<base directory of this skill>"
ENGINE="$SKILL_DIR/engine"
KIT=$(python3 -c 'import os,sys;print(os.path.realpath(os.path.join(sys.argv[1],"..","..","kit")))' "$SKILL_DIR")
[ -x "$KIT/.venv/bin/python" ] && [ -d "$KIT/models" ] || bash "$KIT/setup.sh" --voice   # ~1 GB of voice models, once
PY="$KIT/.venv/bin/python"; export NODE_PATH="$KIT/node_modules"
```
Needs ffmpeg, Node and Python 3.9+. To see the example: `cp -r "$ENGINE/template" ~/reels/pirate && bash "$ENGINE/make.sh" ~/reels/pirate`.

## How it fits together
A reel is one folder:
- `script.json`: the voiceover, one sentence per entry.
- `captions.json`: optional text swaps for captions (`{"twenty five": "25"}`).
- `web/shots.js`: the shot list. Each shot is `SHOTS.push({start, end, tr, draw(ctx, lt, t)})` in seconds of the voiceover; `lt` is time inside the shot, `tr` is the transition out (`'whip'` or `'cut'`).
- `web/lib.js` (easing, keyframes `kf`, shapes, text), `web/chars.js` (the stick rig `drawStick`, hats, faces, arm IK, the eye patch), `web/env.js` (sky, clouds, sea, ships, deck, barrels, cannon, lantern, below deck), `web/main.js` (whip blur, vignette, grain, captions). Add new props to `env.js` or a new `env2.js` (list it in `web/index.html`).
- `audio.py`: music and SFX, all synthesised in code and placed in voiceover seconds.

`make.sh` makes the voice, aligns every word (`audio/words_new.json`), mixes the sound, renders the shots in parallel and writes `<folder>/<folder name>.mp4`.

**Timing:** `audio/words_ref.json` is the voice the shots were timed against. When the voice changes but the words don't, `make.sh` warps the shots onto the new take, so a new recording needs no edits. If the script changes, delete `audio/words_ref.json` (the next take becomes the reference) and re-time `shots.js`.

## Steps
1. **Script.** About 110 to 120 words for 38 to 40 seconds, one idea per sentence: a "what if" hook, the common belief, a turn on "But", examples that build, one shot that shows the mechanism, **a second-layer discovery** before the payoff, and a payoff that resolves both the hook and that discovery. The second layer is whichever of these actually fits the topic - don't force a "but actually" twist where the honest answer is just satisfying on its own: an unexpected contradiction, a counterintuitive fact, a deeper mechanism, an important exception, or a surprising implication (for "why is the sky blue," it's a contradiction: "violet scatters even more than blue, so why isn't the sky violet?"). It must be factually defensible, not manufactured suspense. Show the script to the user before animating.
2. **Pair.** Lock the HuhTronz Question Pair before scripting goes further: Q1 is the hook question itself (what `drawHookTitle` in step 6 puts on screen); Q2 is a one-tap comment prompt, related to Q1 but never spoiling its answer, answerable by someone who only watched the first few seconds, in one word/letter/tap. Pick Q2's type to fit Q1 (speculative "what if" -> personal stake; "why do we" science -> self-check; "would you rather" -> twist; myth-check -> confession; number reveal -> prediction). Write both into the question bank sheet before animating, and write the payoff line of the script so it sets up Q2, not just Q1.
3. **Facts.** Check every claim with sources. Hedge theories ("scientists think"). Watch for the commonly-repeated oversimplified version of a fact and prefer the more precise one - it's usually the second-layer discovery from step 1 (not just "blue is the shortest wavelength we see" but "violet scatters even more than blue, yet the sun emits less of it and our eyes are less sensitive to it, so the sky reads as blue").
4. **Folder.** `cp -r "$ENGINE/template" <reel>`, then empty its `audio/` and replace `script.json` (and `captions.json`). The template's `PERSON` is a blue/white-striped sailor shirt (left over from the pirate example) - re-pick `PERSON.cols` from `PAL` (or add a new solid entry to `PAL` in `chars.js`) to fit the new topic's setting instead of leaving every reel in the same pirate stripes; a solid color (where `cols[0] === cols[1]`) reads as a plain shirt, a two-tone pair reads as stripes.
5. **Voice.** In the folder: `"$PY" "$ENGINE/tools/tts_kokoro.py"` (free) or the user's own recording, or ElevenLabs with `ELEVENLABS_API_KEY` (`"$PY" "$ENGINE/tools/tts_elevenlabs.py" audio/vo_el.mp3`). Put the take at `audio/vo.wav`, then `"$PY" "$ENGINE/tools/align.py" audio/vo.wav` and read the word times in `audio/words_new.json`.
6. **Shots.** Rewrite `web/shots.js`: about 10 to 12 setups, most 2 to 4 s, the explainer shot longer. A new idea gets a new setup. Start the hook in action on frame 1. Keep faces and key props out of the caption band (y about 1250 to 1420) and inside Instagram's safe area (x 100 to 980, y 220 to 1500). In shot A's `draw()`, also call `drawHookTitle(ctx, [lines of the hook question, ALL CAPS, 2 to 4 words a line], lt, {accentIndex: <the payoff line>})` so the hook question (Q1) is spelled out on screen from frame 1, not just spoken - this is what makes the first second scannable with the sound off.

   **Frame 1 is the thumbnail.** Instagram grabs the literal first frame of the exported file as the cover/thumbnail, so shot A must open on a zoomed-in "hero cover" composition, not the regular wide staging: a tight camera (roughly `cam.z` 1.4-1.6, panned to frame the character chest-up) on a confident, mildly challenging grin (not the wide-eyed puzzled look used for the rest of the shot), plus 1-2 topic-relevant prop teasers as screen-locked HUD stickers (e.g. a thumbs-up badge, a small preview of the payoff visual) that hint at the topic without spoiling it. Everything in this cover frame - character, title, stickers - must render at full scale/opacity from `lt=0` exactly: never drive a sticker's entrance with a pop-in that starts at scale 0 (`backOut` from 0, etc.), since the thumbnail is grabbed before any such animation has advanced; use a floor (e.g. `lerp(.65, 1, backOut(t))`) or skip the pop-in and use a subtle constant wobble instead. Around `lt` 0.5-1.0s, zoom out (and snap-cut the pose, don't try to IK-blend it) into the regular wide staging the rest of the shot uses, with the HUD stickers fading out over the same window. The hook title itself must be drawn screen-locked too - call `applyCam(ctx, cam, 0)` right before `drawHookTitle(...)` so the zoomed-in cover camera never pushes it off-canvas (depth-1 title placement only works when the camera stays near identity, which the cover shot violates).

   **Short title card, when there's no on-screen Q1 text otherwise.** If the shot doesn't already carry the full Q1 question via `drawHookTitle` (e.g. an older or simpler reel that only speaks the hook), give the cover frame a short, punchy 2-3 word title instead (e.g. "PIRATE'S EYE") - a label, not the full question. Render it screen-locked (`applyCam(ctx, cam, 0)`), at full scale and opacity from `lt=0` (same thumbnail-safety rule as above: no pop-in from zero). Hold it roughly 0.7-0.9s, then flick it away over about 0.3s - a small scale punch, a fade, a slight rise and rotation - clearing before the ordinary word-by-word captions take over. Pair it with a tiny landing tick at `lt=0` and a short whoosh on the flick-away, both well under the voice.
7. **Stills.** From the folder: `node "$ENGINE/tools/render.js" stills 1.5,4.2,9.0` writes `stills/` (if the browser binary isn't where Playwright expects it, set `CHROME=/usr/bin/google-chrome` or similar before the render/make.sh commands - both accept it). Look at the busiest moments and fix them before a full render - especially any shot whose camera (`cam.x/y/z`) or prop/character coordinates were pushed well outside the normal world-space range used elsewhere (e.g. to imply extreme scale or distance): `applyCam`'s math is easy to get wrong in a way that pushes the subject half or fully off-frame while still looking fine in the code. Check a still from inside that exact shot, not just its neighbors.
8. **Sound.** Edit the cues in `audio.py` against the word times.
9. **Build.** `bash "$ENGINE/make.sh" <reel>` (keeps `audio/vo.wav`; pass `kokoro`, `elevenlabs` or a file to replace it). `WORKERS=8` on a machine with more cores. `AUDIO_ONLY=1` remixes the sound without re-rendering.
10. **Brand.** Every reel gets the channel bug and outro before handoff - never skip this step. From the kit: `bash "$KIT/post/add_intro_outro.sh" <reel>/<name>.mp4 <reel>/<name>_final.mp4 "@HuhTronz" "FOR MORE" "<Q2 text>"`. This bakes in the persistent top-right watermark (sized tight around the glyph + handle, not a trailing pill), a quick confirming open sting synced to the watermark's pop-in, and the FOLLOW outro card with its own closing sting (the open/close pair is the brand's audio signature, so both play on every reel). Q2 itself is both spoken and shown: the script synthesizes a short Kokoro VO line (same narrator voice) asking Q2 plus "Let us know in the comments!" and automatically extends the outro card to fit it, with the on-screen Q2 text popping in large, above the FOLLOW CTA (not a small secondary caption below it), right as the narrator starts asking. After Q2, the same narrator always signs off out loud too ("Follow HuhTronz for more! Let's meet again in our next video. Have a great time!" - this exact line is the hardcoded default in `add_intro_outro.sh`'s `SIGNOFF` variable, naming the channel directly rather than saying "our channel") - the card stretches further to fit that as well, so it is genuinely the last thing anyone hears. Q2 itself should be a genuine comment-prompting question, not dressed up as binary: don't tack on "Yes/No" (or any forced binary framing) to a question whose honest answer isn't actually yes-or-no - that reads as a mismatch and discourages the real, varied answers an open question invites.
11. **Hand over** `<reel>/<name>_final.mp4`, plus Q2 again as the ready-to-paste pinned comment for the moment it's uploaded (on-screen text and an actual pinned comment both matter - the overlay drives the tap, the pin gives it somewhere to land).

## Style
- Captions: Poppins Bold, white with a dark outline, 1 to 2 words, lowercase, no punctuation (`capText()` in `main.js` does it; digits and `%` stay). No em dashes anywhere on screen.
- Bright saturated palette, ink outlines (`#221c22`), soft contact shadows, slow push-ins with handheld drift, whip transitions with motion blur. An impact is a burst, a shake and a flash.
- SFX sit under the voice (gain about 0.38). The music is a quiet plucked underscore, ducked under the voice, never a loud loop at the start.
