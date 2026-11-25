#!/usr/bin/env python3
"""Draws the Pamnot app icon and writes every size the iOS asset catalog lists.

The design: a white cloud on a diagonal pastel gradient, #C9BCF5 at the top
left to #FBC9B4 at the bottom right (the in-app logo colours,
lib/ui/home_shell.dart). A microphone held like a pen writes a signature-like
purple stroke on the cloud: voice notes that turn into written ones. No text, no emoji, square corners (iOS applies the
mask) and no alpha channel, as App Store Connect requires.

The 1024 x 1024 master is drawn at 4096 x 4096 and reduced with LANCZOS for
smooth edges; each file in AppIcon.appiconset/Contents.json is then reduced
from the master under its existing name, so Contents.json stays unchanged.

Needs Pillow. Run from anywhere: python3 tool/icons/make_app_icon.py
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
APP_ICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

MASTER = 1024
S = 4096  # supersampled canvas

GRADIENT_START = (0xC9, 0xBC, 0xF5)  # top left
GRADIENT_END = (0xFB, 0xC9, 0xB4)  # bottom right
INK = (0x6C, 0x5C, 0xBE)
DEEP = (0x4E, 0x40, 0x96)
GRILLE = (0x96, 0x88, 0xDC)
# The foreground (cloud, stroke, microphone) is fitted into this share of the
# square, centred, so iOS's rounded mask never cuts it.
FOREGROUND_SHARE = 0.74


def diagonal_gradient():
    g = Image.new("RGB", (256, 256))
    px = g.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(int(GRADIENT_START[i] + (GRADIENT_END[i] - GRADIENT_START[i]) * t) for i in range(3))
    return g.resize((S, S), Image.Resampling.BICUBIC)


def cloud(d, cx, cy, w, fill):
    r = w / 4
    d.ellipse([cx - w / 2, cy - r * 0.1, cx - w / 2 + r * 1.9, cy + r * 1.7], fill=fill)
    d.ellipse([cx - r * 1.2, cy - r * 1.5, cx + r * 1.1, cy + r * 0.8], fill=fill)
    d.ellipse([cx + w / 2 - r * 2.1, cy - r * 0.55, cx + w / 2, cy + r * 1.7], fill=fill)
    d.rounded_rectangle([cx - w / 2 + r * 0.6, cy + r * 0.3, cx + w / 2 - r * 0.6, cy + r * 1.7], radius=r * 0.7, fill=fill)


def bezier(p0, p1, p2, p3, n=200):
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(tuple((1 - t) ** 3 * p0[k] + 3 * (1 - t) ** 2 * t * p1[k] + 3 * (1 - t) * t * t * p2[k] + t ** 3 * p3[k] for k in range(2)))
    return pts


def foreground():
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("L", (S, S), 0)
    cloud(ImageDraw.Draw(shadow), S * 0.47, S * 0.40, S * 0.66, 120)
    g.paste((150, 120, 190, 255), (0, 140), shadow.filter(ImageFilter.GaussianBlur(100)))
    d = ImageDraw.Draw(g)
    cloud(d, S * 0.47, S * 0.40, S * 0.66, (255, 255, 255, 255))
    # The signature stroke.
    pts = bezier((S * .25, S * .62), (S * .30, S * .48), (S * .36, S * .70), (S * .42, S * .58))
    pts += bezier((S * .42, S * .58), (S * .46, S * .50), (S * .47, S * .70), (S * .53, S * .60))
    pts += bezier((S * .53, S * .60), (S * .57, S * .53), (S * .60, S * .64), (S * .64, S * .60))
    w = int(S * 0.022)
    for a, b in zip(pts, pts[1:]):
        d.line([a, b], fill=INK, width=w)
    for p in pts[::3]:
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=INK)
    tip = pts[-1]
    # The microphone, drawn upright and rotated so its nib meets the stroke.
    m_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = ImageDraw.Draw(m_img)
    cx, hw, hh, top = S / 2, S * 0.085, S * 0.21, S * 0.10
    m.rounded_rectangle([cx - hw, top, cx + hw, top + hh], radius=hw, fill=DEEP)
    for k in range(4):
        y = top + hh * 0.28 + k * hh * 0.15
        m.rounded_rectangle([cx - hw * 0.55, y, cx + hw * 0.55, y + S * 0.012], radius=S * 0.006, fill=GRILLE)
    m.rounded_rectangle([cx - hw * 1.15, top + hh * 0.92, cx + hw * 1.15, top + hh * 1.05], radius=S * 0.02, fill=INK)
    bt, bl = top + hh * 1.05, S * 0.20
    m.polygon([(cx - hw * .55, bt), (cx + hw * .55, bt), (cx + hw * .25, bt + bl), (cx - hw * .25, bt + bl)], fill=DEEP)
    m.polygon([(cx - hw * .25, bt + bl), (cx + hw * .25, bt + bl), (cx, bt + bl + S * 0.05)], fill=INK)
    nib = (cx, bt + bl + S * 0.05)
    mic = m_img.rotate(-38, center=nib, resample=Image.Resampling.BICUBIC)
    off = (int(tip[0] - nib[0]), int(tip[1] - nib[1]))
    mic_shadow = mic.split()[3].filter(ImageFilter.GaussianBlur(60)).point(lambda v: int(v * 0.35))
    g.paste((90, 70, 150, 255), (off[0] + 60, off[1] + 80), mic_shadow)
    g.paste(mic, off, mic)
    return g


def draw_master():
    bg = diagonal_gradient()
    fg = foreground()
    fg = fg.crop(fg.getbbox())
    k = S * FOREGROUND_SHARE / max(fg.size)
    fg = fg.resize((int(fg.size[0] * k), int(fg.size[1] * k)), Image.Resampling.LANCZOS)
    bg.paste(fg, ((S - fg.size[0]) // 2, (S - fg.size[1]) // 2), fg)
    return bg.convert("RGB").resize((MASTER, MASTER), Image.Resampling.LANCZOS)


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
