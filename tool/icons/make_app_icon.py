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

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
APP_ICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

MASTER = 1024
SUPERSAMPLE = 4

GRADIENT_START = (0xC9, 0xBC, 0xF5)  # top left
GRADIENT_END = (0xFB, 0xC9, 0xB4)  # bottom right
CLOUD = (0xFF, 0xFF, 0xFF)

# Cloud geometry in 1024-unit coordinates, relative to the cloud's own origin:
# y = 0 is the flat bottom edge. Each puff is (centre x, centre y, radius). The
# two side puffs rest exactly on the bottom edge, so their arcs run into it
# without a step; the middle puff lies wholly above it. A rectangle between the
# side puffs' centres fills in the flat bottom. Nothing reaches below y = 0.
CLOUD_PUFFS = ((0, -130, 130), (145, -230, 190), (320, -150, 150))
# The shape is 600 x 420 units (about 59 % of the icon's width, inside Apple's
# icon grid) and draw_master() centres its bounding box in the square.
# Gaussian blur (in 1024 units) applied before re-thresholding the cloud mask:
# it fills the two sharp notches where the puffs meet with a soft fillet and
# leaves the flat bottom and the outer arcs where they are.
CLOUD_SOFTEN = 8


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


def cloud_mask(size):
    """L mask, 255 inside the cloud, with the cloud's bounding box centred."""
    s = size / MASTER
    left = min(x - r for x, _, r in CLOUD_PUFFS)
    right = max(x + r for x, _, r in CLOUD_PUFFS)
    top = min(y - r for _, y, r in CLOUD_PUFFS)
    dx = MASTER / 2 - (left + right) / 2
    dy = MASTER / 2 - top / 2  # bottom edge is y = 0

    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    for x, y, r in CLOUD_PUFFS:
        draw.ellipse(((x - r + dx) * s, (y - r + dy) * s, (x + r + dx) * s, (y + r + dy) * s), fill=255)
    (first_x, first_y, _), (last_x, _, _) = CLOUD_PUFFS[0], CLOUD_PUFFS[-1]
    draw.rectangle(((first_x + dx) * s, (first_y + dy) * s, (last_x + dx) * s, dy * s), fill=255)

    soft = mask.filter(ImageFilter.GaussianBlur(CLOUD_SOFTEN * s))
    return soft.point(lambda v: 255 if v >= 128 else 0)


def draw_master():
    size = MASTER * SUPERSAMPLE
    image = diagonal_gradient(size)
    image.paste(CLOUD, mask=cloud_mask(size))
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
