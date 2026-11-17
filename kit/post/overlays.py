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
BRAND_MARK_PATH = HERE / "assets" / "brand" / "mark_raw.png"
INK = (0x22, 0x1c, 0x22, 255)
WHITE = (255, 255, 255, 255)
ACCENT = (0xFF, 0x4B, 0x5C, 255)  # warm coral - pops against the cartoon palette
SS = 4  # supersample factor


def font(size):
    return ImageFont.truetype(FONT_PATH, size * SS)


def brand_mark(size_px):
    """The actual HuhTronz logo (coral orbit ring + cursive H), keyed from
    the user's own PNG to transparent and cached pre-trimmed at
    assets/brand/mark_raw.png - not redrawn from primitives, so it stays
    pixel-faithful to the approved design. Returns a square RGBA image."""
    m = Image.open(BRAND_MARK_PATH).convert("RGBA")
    # pad to square (the source isn't quite 1:1) before resizing, so the
    # ring itself doesn't get stretched
    s = max(m.size)
    square = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    square.paste(m, ((s - m.width) // 2, (s - m.height) // 2), m)
    return square.resize((size_px, size_px), Image.LANCZOS)


def stroked_text(draw, xy, text, size, fill=WHITE, stroke=INK, stroke_w=6, anchor="mm"):
    f = font(size)
    draw.text(xy, text, font=f, fill=fill, anchor=anchor,
              stroke_width=stroke_w * SS, stroke_fill=stroke)


def make_bug(out_path, handle, persistent=False):
    """Small rounded pill, top-right channel bug (logo glyph + handle text).
    Sized tightly around the icon + handle text (measured, not a fixed
    canvas) so the translucent pill just encases its content instead of
    trailing off into empty space. persistent=True dims it slightly since
    it now stays onscreen for the whole video rather than just the
    opening hook."""
    h = 164 * SS
    pad = 10 * SS
    r = 42 * SS                       # logo mark radius - this mark has finer detail
                                       # (a thin ring + cursive H) than the old play-glyph
                                       # and needs real size to still read this small
    gap = 14 * SS                     # icon -> text gap
    text_size = 40
    f = font(text_size)
    # measure the handle text at supersample res to size the pill tightly
    meas = Image.new("RGBA", (10, 10))
    tb = ImageDraw.Draw(meas).textbbox((0, 0), handle, font=f, stroke_width=5 * SS)
    text_w = tb[2] - tb[0]
    icon_d = 2 * r
    left_margin = 20 * SS
    right_margin = 30 * SS
    w = left_margin + icon_d + gap + text_w + right_margin
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pill_alpha = 104 if persistent else 178
    # translucent ink pill (same ink as the rest of the show's outline work) -
    # no outline stroke: the white ring around the pill competed visually
    # with the logo mark's own ring, so the pill is now just a soft fill.
    d.rounded_rectangle([pad, pad, w - pad, h - pad], radius=(h - 2 * pad) // 2,
                         fill=(0x22, 0x1c, 0x22, pill_alpha))
    # the real logo mark
    mark = brand_mark(icon_d)
    img.paste(mark, (left_margin, h // 2 - r), mark)
    cx = left_margin + r
    stroked_text(d, (cx + r + gap, h // 2), handle, text_size, stroke_w=5, anchor="lm")
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


def make_icon(out_path, size_px=1024):
    """Square profile icon for platform accounts: the approved HuhTronz
    logo (coral orbit ring + cursive H) on a plain white backing, exactly
    as it was designed and shown - so the icon on the profile grid is the
    same mark people see pop in on every video, not a separate logo. A
    solid backing (rather than leaving it transparent) keeps it looking
    the same everywhere, since platforms flatten a transparent PNG onto a
    white or black circle unpredictably."""
    s = size_px * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s, s], radius=int(s * 0.22), fill=WHITE)
    mark = brand_mark(int(s * 0.84))
    img.paste(mark, ((s - mark.width) // 2, (s - mark.height) // 2), mark)
    img = img.resize((size_px, size_px), Image.LANCZOS)
    img.save(out_path)


if __name__ == "__main__":
    kind = sys.argv[1]
    out = sys.argv[2]
    if kind == "bug":
        make_bug(out, sys.argv[3])
    elif kind == "watermark":
        make_bug(out, sys.argv[3], persistent=True)
    elif kind == "badge":
        make_badge(out, sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
    elif kind == "icon":
        make_icon(out, int(sys.argv[3]) if len(sys.argv) > 3 else 1024)
    else:
        sys.exit("usage: overlays.py bug|watermark|badge|icon <out.png> ...")
