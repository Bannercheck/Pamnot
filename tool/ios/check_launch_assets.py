#!/usr/bin/env python3
"""Checks the iOS app icon, launch screen and widget privacy manifest.

Standard library only, so it runs on the Linux CI runner without Xcode:

1. Every file named in AppIcon.appiconset/Contents.json exists, is
   size x scale pixels, and is a PNG of colour type 2 (RGB, no alpha).
2. The marketing icon is not the Flutter template logo any more.
3. LaunchBackground.colorset has a light (#FAF7F2) and a dark (#1E1C24) colour.
4. LaunchScreen.storyboard is a plain LaunchBackground view: no image view,
   no constraints, no image resource.
5. LaunchImage.imageset is gone.
6. The widget's PrivacyInfo.xcprivacy declares only App Group user defaults
   (1C8F.1), no tracking and no collected data.
7. The widget's light-theme secondary text colour is #6A6478 (5.31:1).

Prints "launch assets ok" and exits 0 when everything holds; otherwise prints
one line per problem to stderr and exits 1.

Run from anywhere: python3 tool/ios/check_launch_assets.py
"""

import hashlib
import json
import plistlib
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "ios/Runner/Assets.xcassets"
APP_ICON = ASSETS / "AppIcon.appiconset"
LAUNCH_BACKGROUND = ASSETS / "LaunchBackground.colorset/Contents.json"
LAUNCH_IMAGE = ASSETS / "LaunchImage.imageset"
STORYBOARD = ROOT / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
WIDGET_PRIVACY = ROOT / "ios/PamnotWidget/PrivacyInfo.xcprivacy"
WIDGET_SWIFT = ROOT / "ios/PamnotWidget/PamnotTodayWidget.swift"

MARKETING_ICON = "Icon-App-1024x1024@1x.png"
# SHA-256 of the Flutter template icon (Icon-App-1024x1024@1x.png at 2c404ba).
FLUTTER_LOGO_SHA256 = "7770183009e914112de7d8ef1d235a6a30c5834424858e0d2f8253f6b8d31926"

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_COLOUR_TYPE_RGB = 2

LIGHT_BACKGROUND = (0xFA, 0xF7, 0xF2)
DARK_BACKGROUND = (0x1E, 0x1C, 0x24)


def png_header(path):
    """Returns (width, height, colour type) from the IHDR chunk."""
    with open(path, "rb") as f:
        head = f.read(26)
    if len(head) < 26 or head[:8] != PNG_SIGNATURE or head[12:16] != b"IHDR":
        raise ValueError("not a PNG file")
    width, height, _bit_depth, colour_type = struct.unpack(">IIBB", head[16:26])
    return width, height, colour_type


def expected_pixels(entry):
    """size "83.5x83.5" with scale "2x" -> (167, 167)."""
    factor = float(entry["scale"].rstrip("x"))
    sides = []
    for side in entry["size"].split("x"):
        pixels = float(side) * factor
        if pixels != int(pixels):
            raise ValueError(f"size {entry['size']} at {entry['scale']} is not whole pixels")
        sides.append(int(pixels))
    return tuple(sides)


def check_not_flutter_logo(errors):
    path = APP_ICON / MARKETING_ICON
    if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == FLUTTER_LOGO_SHA256:
        errors.append(f"{MARKETING_ICON}: still the Flutter template logo")


def check_app_icons(errors):
    images = json.loads((APP_ICON / "Contents.json").read_text())["images"]
    # iPhone and iPad entries share files; check each file once.
    wanted = {}
    for entry in images:
        name = entry.get("filename")
        if not name:
            errors.append(f"AppIcon {entry.get('idiom')} {entry.get('size')}@{entry.get('scale')}: no filename")
            continue
        try:
            pixels = expected_pixels(entry)
        except (KeyError, ValueError) as e:
            errors.append(f"{name}: bad size/scale in Contents.json ({e})")
            continue
        if wanted.setdefault(name, pixels) != pixels:
            errors.append(f"{name}: listed at {wanted[name]} and {pixels} pixels")
    for name, want in wanted.items():
        path = APP_ICON / name
        if not path.is_file():
            errors.append(f"{name}: missing")
            continue
        try:
            width, height, colour_type = png_header(path)
        except ValueError as e:
            errors.append(f"{name}: {e}")
            continue
        if (width, height) != want:
            errors.append(f"{name}: {width}x{height}, want {want[0]}x{want[1]}")
        if colour_type != PNG_COLOUR_TYPE_RGB:
            errors.append(f"{name}: PNG colour type {colour_type}, want 2 (RGB, no alpha)")
    # Pinned on its own so that an edited Contents.json cannot shrink it.
    if wanted.get(MARKETING_ICON) != (1024, 1024):
        errors.append(f"{MARKETING_ICON}: must be listed in Contents.json as 1024x1024 @1x")


def colour_components(colour):
    """Reads 8-bit hex components ("0xFA", Xcode's 0-255 form) and the alpha."""
    components = colour["color"]["components"]
    rgb = tuple(int(str(components[key]), 16) for key in ("red", "green", "blue"))
    return rgb, float(components["alpha"])


def check_launch_background(errors):
    if not LAUNCH_BACKGROUND.is_file():
        errors.append("LaunchBackground.colorset/Contents.json: missing")
        return
    colours = json.loads(LAUNCH_BACKGROUND.read_text()).get("colors", [])
    if len(colours) != 2:
        errors.append(f"LaunchBackground: {len(colours)} colours, want 2 (any + dark)")
        return
    any_appearance = [c for c in colours if "appearances" not in c]
    dark = [
        c
        for c in colours
        if c.get("appearances") == [{"appearance": "luminosity", "value": "dark"}]
    ]
    for label, found, want in (
        ("any-appearance", any_appearance, LIGHT_BACKGROUND),
        ("dark", dark, DARK_BACKGROUND),
    ):
        if len(found) != 1:
            errors.append(f"LaunchBackground: want exactly one {label} colour")
            continue
        try:
            rgb, alpha = colour_components(found[0])
        except (KeyError, ValueError) as e:
            errors.append(f"LaunchBackground {label}: unreadable components ({e})")
            continue
        if rgb != want or alpha != 1.0:
            errors.append(
                f"LaunchBackground {label}: #{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X} alpha {alpha}, "
                f"want #{want[0]:02X}{want[1]:02X}{want[2]:02X} alpha 1"
            )


def check_storyboard(errors):
    try:
        root = ET.parse(STORYBOARD).getroot()
    except ET.ParseError as e:
        errors.append(f"LaunchScreen.storyboard: not well-formed XML ({e})")
        return
    if root.find(".//imageView") is not None:
        errors.append("LaunchScreen.storyboard: has an imageView")
    if root.find(".//constraint") is not None:
        errors.append("LaunchScreen.storyboard: has constraints")
    if root.find("dependencies/capability[@name='Named colors']") is None:
        errors.append("LaunchScreen.storyboard: no 'Named colors' capability")
    view = root.find(".//view[@key='view']")
    if view is None or view.find("color[@key='backgroundColor'][@name='LaunchBackground']") is None:
        errors.append("LaunchScreen.storyboard: view background is not the LaunchBackground colour")
    if root.find("resources/namedColor[@name='LaunchBackground']") is None:
        errors.append("LaunchScreen.storyboard: no LaunchBackground namedColor resource")
    if root.find("resources/image") is not None:
        errors.append("LaunchScreen.storyboard: still has an image resource")


def check_launch_image_removed(errors):
    if LAUNCH_IMAGE.exists():
        errors.append("LaunchImage.imageset: still exists")


def check_widget_privacy(errors):
    if not WIDGET_PRIVACY.is_file():
        errors.append("ios/PamnotWidget/PrivacyInfo.xcprivacy: missing")
        return
    try:
        with open(WIDGET_PRIVACY, "rb") as f:
            manifest = plistlib.load(f)
    except plistlib.InvalidFileException as e:
        errors.append(f"widget PrivacyInfo: not a property list ({e})")
        return
    if not isinstance(manifest, dict):
        errors.append("widget PrivacyInfo: top level must be a dictionary")
        return
    if manifest.get("NSPrivacyTracking") is not False:
        errors.append("widget PrivacyInfo: NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        errors.append("widget PrivacyInfo: NSPrivacyTrackingDomains must be empty")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        errors.append("widget PrivacyInfo: NSPrivacyCollectedDataTypes must be empty")
    accessed = {
        api.get("NSPrivacyAccessedAPIType"): api.get("NSPrivacyAccessedAPITypeReasons")
        for api in manifest.get("NSPrivacyAccessedAPITypes", [])
    }
    want = {"NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1"]}
    if accessed != want or len(manifest.get("NSPrivacyAccessedAPITypes", [])) != 1:
        errors.append(f"widget PrivacyInfo: accessed APIs {accessed}, want {want}")


def check_widget_colours(errors):
    source = WIDGET_SWIFT.read_text()
    if "0x8C8698" in source:
        errors.append("PamnotTodayWidget.swift: low-contrast secondary 0x8C8698 still used")
    if "0x6A6478" not in source:
        errors.append("PamnotTodayWidget.swift: secondary 0x6A6478 missing")


def main():
    errors = []
    # The Flutter-logo check runs first: it is the App Review blocker.
    check_not_flutter_logo(errors)
    check_app_icons(errors)
    check_launch_background(errors)
    check_storyboard(errors)
    check_launch_image_removed(errors)
    check_widget_privacy(errors)
    check_widget_colours(errors)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("launch assets ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
