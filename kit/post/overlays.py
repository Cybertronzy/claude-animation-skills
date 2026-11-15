#!/usr/bin/env python3
"""
Generate the two PNG overlays used by add_intro_outro.sh:
  bug.png    - small corner "channel bug" shown during the opening hook
  badge.png  - big circular FOLLOW/subscribe badge shown in the outro

Both are drawn with the exact ink/white cartoon style the stick-figure
(and other animation) skills already use for captions: Poppins Bold,
pure white fill, a thick #221c22 (INK) stroke. Everything is drawn at
4x supersample and downsized, so edges stay crisp at 1080x1920.

Usage:
  python3 overlays.py bug   <out.png> "<handle text>"
  python3 overlays.py badge <out.png> "<cta line 1>" ["<cta line 2>"]
"""
import sys
from PIL import Image, ImageDraw, ImageFont

HERE = __import__("pathlib").Path(__file__).resolve().parent
FONT_PATH = str(HERE / "assets" / "Poppins-Bold.ttf")
INK = (0x22, 0x1c, 0x22, 255)
WHITE = (255, 255, 255, 255)
ACCENT = (0xFF, 0x4B, 0x5C, 255)  # warm coral - pops against the cartoon palette
SS = 4  # supersample factor


def font(size):
    return ImageFont.truetype(FONT_PATH, size * SS)


def stroked_text(draw, xy, text, size, fill=WHITE, stroke=INK, stroke_w=6, anchor="mm"):
    f = font(size)
    draw.text(xy, text, font=f, fill=fill, anchor=anchor,
              stroke_width=stroke_w * SS, stroke_fill=stroke)


def make_bug(out_path, handle):
    """Small rounded pill, bottom-left reads cleanly over the vignette-darkened
    corner the main renderer already paints, bottom-left or top-right of frame."""
    w, h = 560 * SS, 164 * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = 10 * SS
    # translucent ink pill (same ink as the rest of the show's outline work)
    d.rounded_rectangle([pad, pad, w - pad, h - pad], radius=(h - 2 * pad) // 2,
                         fill=(0x22, 0x1c, 0x22, 178), outline=WHITE, width=5 * SS)
    # small triangular "play" glyph
    cx, cy, r = pad + 56 * SS, h // 2, 26 * SS
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE, outline=INK, width=3 * SS)
    tri = [(cx - r * 0.35, cy - r * 0.5), (cx - r * 0.35, cy + r * 0.5), (cx + r * 0.55, cy)]
    d.polygon(tri, fill=ACCENT)
    stroked_text(d, (pad + 122 * SS, h // 2), handle, 40, stroke_w=5, anchor="lm")
    img = img.resize((w // SS, h // SS), Image.LANCZOS)
    img.save(out_path)


def make_badge(out_path, line1, line2=""):
    """Big circular FOLLOW badge: thick ink ring, a bell glyph, bold caption-matching
    text. Drawn once; add_intro_outro.sh pulses/pops it in with ffmpeg's scale filter."""
    size = 680 * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = size // 2
    r = size // 2 - 14 * SS
    # outer accent ring (slightly larger, coral) then the white disc with ink stroke
    d.ellipse([cx - r - 10 * SS, cy - r - 10 * SS, cx + r + 10 * SS, cy + r + 10 * SS],
               outline=ACCENT, width=10 * SS)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE, outline=INK, width=12 * SS)

    # bell glyph, upper half of the disc - hand-plotted silhouette (dome -> flare)
    bx, by = cx, cy - int(r * 0.28)
    bw, bh = int(r * 0.5), int(r * 0.42)
    outline_pts = [
        (0.00, -1.00), (0.38, -0.80), (0.55, -0.30), (0.62, 0.25),
        (0.78, 0.55), (0.97, 0.72), (-0.97, 0.72), (-0.78, 0.55),
        (-0.62, 0.25), (-0.55, -0.30), (-0.38, -0.80),
    ]
    d.polygon([(bx + u * bw, by + v * bh) for u, v in outline_pts], fill=INK)
    # top loop
    loop_r = int(bw * 0.14)
    d.ellipse([bx - loop_r, by - bh - loop_r * 0.6, bx + loop_r, by - bh + loop_r * 1.1],
               outline=INK, width=int(loop_r * 0.55))
    # clapper
    cr = int(bw * 0.12)
    d.ellipse([bx - cr, by + int(bh * 0.72) - cr, bx + cr, by + int(bh * 0.72) + cr], fill=INK)

    stroked_text(d, (cx, cy + int(r * 0.42)), line1, 66, stroke_w=7)
    if line2:
        stroked_text(d, (cx, cy + int(r * 0.74)), line2, 34, stroke=INK, stroke_w=5)

    img = img.resize((size // SS, size // SS), Image.LANCZOS)
    img.save(out_path)


if __name__ == "__main__":
    kind = sys.argv[1]
    out = sys.argv[2]
    if kind == "bug":
        make_bug(out, sys.argv[3])
    elif kind == "badge":
        make_badge(out, sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
    else:
        sys.exit("usage: overlays.py bug|badge <out.png> ...")
