#!/usr/bin/env python3
"""Regenerate the alternate app icons from the primary icon.

Why this exists (add-themes-and-layout design.md D10/R5): every alternate is
the PR #37 primary -- white "GF / by Jirka" letterforms on a diagonal
gradient -- with only the gradient recoloured, one per theme. Keeping that as
a script (not hand-exported PNGs) means a theme's colours can change and its
icon be rebuilt in one command, and every alternate stays pixel-aligned with
the primary's glyphs.

How: the primary's gradient runs from its bottom-left corner to its top-right
corner. For each pixel we compute how far it is along that diagonal (t), the
primary's own gradient colour at t, and from that the white glyph's coverage
(alpha) -- measured on the red channel, which the teal gradient keeps lowest,
so the glyph/background separation is widest there. Each alternate is then
`lerp(gradient_alt(t), white, alpha)`, rendered at 1024 px and downsampled to
@2x (120 px) and @3x (180 px), full-bleed and opaque as iOS requires.

Stop colours are each icon's bottom-left corner, top-left corner (= the
colour halfway along the diagonal) and top-right corner; the theme's brand
colours in AppearanceKit's ThemeCatalog.swift are derived from these.

Usage (from the repo root; needs Pillow):
    python tools/generate-app-icons.py            # write all 11 alternates
    python tools/generate-app-icons.py --check    # compare, write nothing

Depends on: ios/GarminFood/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.
Writes: ios/GarminFood/AppIcons/AppIcon-<Name>@2x.png / @3x.png, which
ios/project.yml lists under CFBundleAlternateIcons and AppIconOption.swift
names -- add a new icon in all three places.
"""

import argparse
import os
import sys

from PIL import Image, ImageChops, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRIMARY = os.path.join(ROOT, "ios", "GarminFood", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
OUT_DIR = os.path.join(ROOT, "ios", "GarminFood", "AppIcons")

# (bottom-left, top-left/bottom-right, top-right) gradient stops per
# alternate: the colour at t = 0, 0.5 and 1. Keep in step with
# ThemeCatalog.swift's brand colours.
ICONS = {
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


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def diagonal_t(size):
    """t in [0, 1]: 0 at the bottom-left corner, 1 at the top-right."""
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


def glyph_alpha(primary, t_img, stops):
    """Coverage of the white glyphs, from the red channel."""
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
    return alpha


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="report the difference to the committed icons; write nothing")
    args = parser.parse_args()

    primary = Image.open(PRIMARY).convert("RGB")
    size = primary.size[0]
    t_img = diagonal_t(size)
    # The primary's own stops, read from its corners (glyph-free).
    p_stops = (primary.getpixel((0, size - 1)), primary.getpixel((0, 0)), primary.getpixel((size - 1, 0)))
    alpha = glyph_alpha(primary, t_img, p_stops)
    white = Image.new("RGB", primary.size, (255, 255, 255))

    worst = 0.0
    for name, stops in ICONS.items():
        background = gradient(tuple(hex_rgb(s) for s in stops), t_img)
        full = Image.composite(white, background, alpha)
        for suffix, px in SIZES.items():
            icon = full.resize((px, px), Image.Resampling.LANCZOS)
            path = os.path.join(OUT_DIR, f"AppIcon-{name}{suffix}.png")
            if args.check:
                if not os.path.exists(path):
                    print(f"{name}{suffix}: missing")
                    worst = 255.0
                    continue
                committed = Image.open(path).convert("RGB")
                mean = sum(ImageStat.Stat(ImageChops.difference(icon, committed)).mean) / 3
                worst = max(worst, mean)
                print(f"{name}{suffix}: mean abs difference {mean:.2f}")
            else:
                icon.save(path, optimize=True)
                print(f"wrote {os.path.relpath(path, ROOT)}")
    if args.check:
        print(f"worst mean difference: {worst:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
