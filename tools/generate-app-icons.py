#!/usr/bin/env python3
"""Regenerate every app icon (the primary and the 11 alternates).

Why this exists (add-themes-and-layout design.md D10/R5, redrawn by
rebrand-to-jirkas-arc design.md D3): every icon is the same white glyph on a
full-bleed diagonal gradient, one gradient per theme. Keeping that as a script
(not hand-exported PNGs) means a theme's colours can change and its icon be
rebuilt in one command, every icon stays pixel-aligned with the others, and
the artwork is reviewable on Windows with no Mac, font or vector tool.

The glyph is Jirka's Arc's arc mark above the original "by Jirka" line:

- the ARC: a thick white arc with rounded caps, opening downwards, rising
  from the lower left to a shoulder right of centre (a season's build curve,
  a hill profile), stroke weight equal to the old "GF" stems;
- a solid white DOT riding the arc just past its peak ("you are here"),
  set off from the arc by a thin knocked-out ring;
- "BY JIRKA": the credit line of the original "GF / by Jirka" icon, kept
  exactly (same place, same size) from `tools/icon-src/by-jirka-mask.png`.

How: the arc and dot are drawn procedurally at 4096 px and downsampled to
1024 px, which anti-aliases them without a font or vector renderer. Glyph
coverage = max(arc mark, "by Jirka" mask). Each icon is
`lerp(gradient(t), white, coverage)`, where t is how far a pixel is along the
diagonal from the bottom-left corner (t = 0) to the top-right (t = 1) and the
gradient runs through three stops (bottom-left, top-left = halfway, top-right).
The primary is written at 1024 px; each alternate is downsampled to @2x
(120 px) and @3x (180 px), full-bleed and opaque as iOS requires.

The "by Jirka" mask was extracted ONCE (`--extract-mask`) from the pre-rebrand
primary icon: the white glyph's coverage, measured on the red channel (which
the teal gradient keeps lowest), below the "GF" letters. It is committed, so
regenerating never depends on the old artwork again.

The ArcMark SwiftUI shape (ios/GarminFood/DesignSystem/ArcMark.swift) draws
the same geometry as ARC_* / DOT_* below; change both together.

Usage (from the repo root; needs Pillow):
    python tools/generate-app-icons.py            # write the primary + 22 alternate PNGs
    python tools/generate-app-icons.py --check    # compare, write nothing; exit 1 if any differs
    python tools/generate-app-icons.py --contact-sheet out.png   # only a review sheet of all 12
    python tools/generate-app-icons.py --extract-mask            # one-time, see above

Depends on: tools/icon-src/by-jirka-mask.png.
Writes: ios/GarminFood/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
(the primary, "Teal" below) and ios/GarminFood/AppIcons/AppIcon-<Name>@2x.png /
@3x.png, which ios/project.yml lists under CFBundleAlternateIcons and
AppIconOption.swift names -- add a new icon in all three places. Names never
change: iOS remembers a chosen alternate by name.
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRIMARY = os.path.join(ROOT, "ios", "GarminFood", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
OUT_DIR = os.path.join(ROOT, "ios", "GarminFood", "AppIcons")
MASK = os.path.join(ROOT, "tools", "icon-src", "by-jirka-mask.png")

SIZE = 1024
SUPERSAMPLE = 4

# (bottom-left, top-left/bottom-right, top-right) gradient stops per icon:
# the colour at t = 0, 0.5 and 1. Keep in step with ThemeCatalog.swift's
# brand colours. "Teal" is the primary icon (the default "GF Teal" theme):
# its stops are the pre-rebrand primary's own corner colours.
PRIMARY_NAME = "Teal"
ICONS = {
    "Teal": ("#11456B", "#1D939F", "#24DEDE"),
    "Indigo": ("#322FC6", "#663BE2", "#A347F5"),
    "Sunset": ("#EA364B", "#F46B3D", "#FB9333"),
    "Forest": ("#03503B", "#047A52", "#03A165"),
    "Pastel": ("#A59CE5", "#DA9ED2", "#F2A6BD"),
    "Slate": ("#3C4557", "#687788", "#8EA3B3"),
    "Citrus": ("#8BD76E", "#CADD4E", "#F8E33A"),
    "Ocean": ("#14607B", "#1C95A1", "#1EC8C5"),
    "Coral": ("#F66364", "#F9816B", "#F9A170"),
    "Berry": ("#681D6E", "#942872", "#BF3375"),
    "Graphite": ("#090A0D", "#40444C", "#828893"),
    "Gold": ("#110D06", "#956D24", "#E9C15E"),
}

SIZES = {"@2x": 120, "@3x": 180}

# The arc mark, in 1024 px icon coordinates (y down). Angles are measured
# counter-clockwise from the +x axis as in maths (y up), so 90 is the top.
ARC_CENTER = (545.0, 700.0)
ARC_RADIUS = 380.0
ARC_STROKE = 84.0  # the old "GF" stems measured 82-84 px
ARC_START = 165.0  # lower left
ARC_END = 25.0  # the shoulder, right of centre
DOT_ANGLE = 65.0  # just past the peak
DOT_RADIUS = 62.0
DOT_GAP = 96.0  # radius of the ring knocked out of the arc around the dot

# Rows above this belong to the old "GF" letters; "by Jirka" starts at
# y = 731 in the pre-rebrand primary (the letters end at 665).
MASK_TOP = 700
# Coverage at or below this is noise in the old artwork, not glyph.
MASK_NOISE = 3

# `--check` fails when an icon's mean absolute difference exceeds this
# (0-255 per channel). A regenerated tree differs by 0; small Pillow version
# differences in resampling stay well below it.
CHECK_TOLERANCE = 1.0


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def diagonal_t(size):
    """t in [0, 255]: 0 at the bottom-left corner, 255 at the top-right."""
    t = Image.linear_gradient("L").resize((size, size))  # 0 top -> 255 bottom
    vertical = t.transpose(Image.Transpose.FLIP_TOP_BOTTOM)  # 0 bottom -> 255 top
    horizontal = t.transpose(Image.Transpose.ROTATE_90)  # 0 left -> 255 right
    return ImageChops.add(vertical, horizontal, scale=2.0)


def stop_value(v, s, m, e):
    """Channel value at t = v / 255 on the three-stop ramp s -> m -> e."""
    if v <= 127.5:
        return round(s + (m - s) * v / 127.5)
    return round(m + (e - m) * (v - 127.5) / 127.5)


def gradient(stops, t_img):
    """RGB gradient through `stops` (colours at t = 0, 0.5, 1)."""
    bands = []
    for s, m, e in zip(*stops):
        bands.append(t_img.point(lambda v, s=s, m=m, e=e: stop_value(v, s, m, e)))
    return Image.merge("RGB", bands)


def point_on_arc(angle_deg, radius=ARC_RADIUS):
    a = math.radians(angle_deg)
    return (ARC_CENTER[0] + radius * math.cos(a), ARC_CENTER[1] - radius * math.sin(a))


def disc(draw, center, radius, fill, k):
    x, y = center
    draw.ellipse([(x - radius) * k, (y - radius) * k, (x + radius) * k, (y + radius) * k], fill=fill)


def arc_mark_coverage():
    """The arc and dot, drawn at SUPERSAMPLE x and downsampled to SIZE."""
    k = SUPERSAMPLE
    big = Image.new("L", (SIZE * k, SIZE * k), 0)
    draw = ImageDraw.Draw(big)
    # The stroke as an annulus sector: outer edge forward, inner edge back.
    steps = 720
    outer = ARC_RADIUS + ARC_STROKE / 2
    inner = ARC_RADIUS - ARC_STROKE / 2
    angles = [ARC_START + (ARC_END - ARC_START) * i / steps for i in range(steps + 1)]
    polygon = [point_on_arc(a, outer) for a in angles] + [point_on_arc(a, inner) for a in reversed(angles)]
    draw.polygon([(x * k, y * k) for x, y in polygon], fill=255)
    # Rounded caps.
    for end in (ARC_START, ARC_END):
        disc(draw, point_on_arc(end), ARC_STROKE / 2, 255, k)
    # The "you are here" dot, set off by a knocked-out ring.
    dot = point_on_arc(DOT_ANGLE)
    disc(draw, dot, DOT_GAP, 0, k)
    disc(draw, dot, DOT_RADIUS, 255, k)
    return big.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def extract_mask():
    """One-time: the "by Jirka" coverage of the pre-rebrand primary."""
    primary = Image.open(PRIMARY).convert("RGB")
    if primary.size != (SIZE, SIZE):
        raise SystemExit(f"expected a {SIZE} px primary, got {primary.size}")
    t_img = diagonal_t(SIZE)
    # The primary's own stops, read from its corners (glyph-free).
    stops = (primary.getpixel((0, SIZE - 1)), primary.getpixel((0, 0)), primary.getpixel((SIZE - 1, 0)))
    red = primary.getchannel("R")
    base = gradient(stops, t_img).getchannel("R")
    # alpha = (red - base) / (255 - base), clamped to [0, 255]
    diff = ImageChops.subtract(red, base)
    headroom = base.point(lambda v: 255 - v)
    alpha = Image.new("L", primary.size)
    alpha.putdata([
        0 if h == 0 else min(255, round(255 * d / h))
        for d, h in zip(diff.tobytes(), headroom.tobytes())
    ])
    alpha = alpha.point(lambda v: 0 if v <= MASK_NOISE else v)
    # Keep only the credit line: blank every row above MASK_TOP.
    ImageDraw.Draw(alpha).rectangle([0, 0, SIZE - 1, MASK_TOP - 1], fill=0)
    os.makedirs(os.path.dirname(MASK), exist_ok=True)
    alpha.save(MASK, optimize=True)
    print(f"wrote {os.path.relpath(MASK, ROOT)} (stops of the source: {stops})")


def render_all():
    """{name: 1024 px RGB icon} for every entry in ICONS."""
    if not os.path.exists(MASK):
        raise SystemExit(f"missing {os.path.relpath(MASK, ROOT)}; see --extract-mask")
    mask = Image.open(MASK).convert("L")
    coverage = ImageChops.lighter(arc_mark_coverage(), mask)
    t_img = diagonal_t(SIZE)
    white = Image.new("RGB", (SIZE, SIZE), (255, 255, 255))
    return {
        name: Image.composite(white, gradient(tuple(hex_rgb(s) for s in stops), t_img), coverage)
        for name, stops in ICONS.items()
    }


def outputs(icons):
    """(path, image) for every file this script owns."""
    for name, full in icons.items():
        if name == PRIMARY_NAME:
            yield PRIMARY, full
            continue
        for suffix, px in SIZES.items():
            yield os.path.join(OUT_DIR, f"AppIcon-{name}{suffix}.png"), full.resize((px, px), Image.Resampling.LANCZOS)


def contact_sheet(icons, path):
    tile, gap, columns = 256, 24, 6
    rows = math.ceil(len(icons) / columns)
    sheet = Image.new("RGB", (columns * tile + (columns + 1) * gap, rows * tile + (rows + 1) * gap), (242, 242, 247))
    for i, full in enumerate(icons.values()):
        x = gap + (i % columns) * (tile + gap)
        y = gap + (i // columns) * (tile + gap)
        sheet.paste(full.resize((tile, tile), Image.Resampling.LANCZOS), (x, y))
    sheet.save(path, optimize=True)
    print(f"wrote {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="report the difference to the committed icons; write nothing")
    parser.add_argument("--contact-sheet", metavar="PNG", help="also write every icon side by side to PNG")
    parser.add_argument("--extract-mask", action="store_true", help="one-time: cut the 'by Jirka' mask from the current primary")
    args = parser.parse_args()

    if args.extract_mask:
        extract_mask()
        return 0

    icons = render_all()
    if args.contact_sheet:
        contact_sheet(icons, args.contact_sheet)

    worst = 0.0
    for path, icon in outputs(icons):
        rel = os.path.relpath(path, ROOT)
        if args.check:
            if not os.path.exists(path):
                print(f"{rel}: missing")
                worst = 255.0
                continue
            committed = Image.open(path).convert("RGB")
            if committed.size != icon.size:
                print(f"{rel}: size {committed.size}, expected {icon.size}")
                worst = 255.0
                continue
            mean = sum(ImageStat.Stat(ImageChops.difference(icon, committed)).mean) / 3
            worst = max(worst, mean)
            print(f"{rel}: mean abs difference {mean:.2f}")
        elif args.contact_sheet is None:
            icon.save(path, optimize=True)
            print(f"wrote {rel}")
    if args.check:
        print(f"worst mean difference: {worst:.2f} (tolerance {CHECK_TOLERANCE})")
        return 0 if worst <= CHECK_TOLERANCE else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
