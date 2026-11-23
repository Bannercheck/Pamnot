#!/usr/bin/env python3
"""Draws the Pamnot app icon and writes every size the iOS asset catalog lists.

The design: a white cloud centred on a diagonal pastel gradient, #C9BCF5 at the
top left to #FBC9B4 at the bottom right (the in-app logo colours,
lib/ui/home_shell.dart). No text, no emoji, square corners (iOS applies the
mask) and no alpha channel, as App Store Connect requires.

The 1024 x 1024 master is drawn at 4096 x 4096 and reduced with LANCZOS for
smooth edges; each file in AppIcon.appiconset/Contents.json is then reduced
from the master under its existing name, so Contents.json stays unchanged.

Needs Pillow. Run from anywhere: python3 tool/icons/make_app_icon.py
"""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
APP_ICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

MASTER = 1024
SUPERSAMPLE = 4

GRADIENT_START = (0xC9, 0xBC, 0xF5)  # top left
GRADIENT_END = (0xFB, 0xC9, 0xB4)  # bottom right
CLOUD = (0xFF, 0xFF, 0xFF)

# Cloud geometry in 1024-unit coordinates.
CLOUD_CIRCLES = ((392, 560, 140), (540, 470, 190), (680, 580, 130))  # centre x, y, radius
CLOUD_BASE = ((300, 560), (790, 700))  # top left, bottom right
CLOUD_BASE_RADIUS = 70


def diagonal_gradient(size):
    """RGB image fading from GRADIENT_START (top left) to GRADIENT_END (bottom right)."""
    ramp = Image.new("L", (size, 1))
    ramp.putdata([round(255 * x / (size - 1)) for x in range(size)])
    horizontal = ramp.resize((size, size), Image.Resampling.NEAREST)
    vertical = horizontal.transpose(Image.Transpose.TRANSPOSE)
    mask = ImageChops.add(horizontal, vertical, scale=2.0)  # (x + y) / 2
    start = Image.new("RGB", (size, size), GRADIENT_START)
    end = Image.new("RGB", (size, size), GRADIENT_END)
    return Image.composite(end, start, mask)


def draw_master():
    size = MASTER * SUPERSAMPLE
    image = diagonal_gradient(size)
    draw = ImageDraw.Draw(image)
    s = SUPERSAMPLE
    for x, y, r in CLOUD_CIRCLES:
        draw.ellipse(((x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s), fill=CLOUD)
    (left, top), (right, bottom) = CLOUD_BASE
    draw.rounded_rectangle((left * s, top * s, right * s, bottom * s), radius=CLOUD_BASE_RADIUS * s, fill=CLOUD)
    return image.resize((MASTER, MASTER), Image.Resampling.LANCZOS)


def icon_sizes():
    """Maps each file named in Contents.json to its pixel side (size x scale)."""
    images = json.loads((APP_ICON / "Contents.json").read_text())["images"]
    sizes = {}
    for entry in images:
        side = float(entry["size"].split("x")[0]) * float(entry["scale"].rstrip("x"))
        if side != int(side):
            raise SystemExit(f"{entry['filename']}: {entry['size']} @ {entry['scale']} is not whole pixels")
        if sizes.setdefault(entry["filename"], int(side)) != int(side):
            raise SystemExit(f"{entry['filename']}: listed with two different sizes")
    return sizes


def main():
    master = draw_master()
    sizes = icon_sizes()
    for name, side in sorted(sizes.items()):
        icon = master if side == MASTER else master.resize((side, side), Image.Resampling.LANCZOS)
        icon.convert("RGB").save(APP_ICON / name, format="PNG", optimize=True)
    print(f"wrote {len(sizes)} PNGs to {APP_ICON.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
