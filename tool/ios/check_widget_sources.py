#!/usr/bin/env python3
"""Checks the iOS list widget's sources without a Mac.

Standard library only:

1. PamnotListWidget.swift and PamnotListIntents.swift exist; the widget uses
   AppIntentConfiguration and Button(intent:), the intents file declares a
   WidgetConfigurationIntent, an AppEnum and PamnotCompleteTaskIntent with
   openAppWhenRun = false, and the widget opens pamnot://list/<id>.
2. The widget sources name "pamnot_lists", "pamnot_pending_done" and the App Group
   group.app.pamnot.shared, and none of them imports home_widget or Flutter (the
   extension links no pods).
3. The Swift constants equal the Dart ones in lib/services/widget_sync.dart:
   appGroupId, listsKey, pendingDoneKey, and iOSListName == listWidgetKind.
4. PamnotWidgetBundle lists both widgets.
5. en.lproj and tr.lproj Localizable.strings parse, have no duplicate keys, have the
   same keys, and carry the box titles (TR / EN) and "All" / "Tümü".

Prints "widget sources ok" and exits 0 when everything holds; otherwise prints one
line per problem to stderr and exits 1.

Run from anywhere: python3 tool/ios/check_widget_sources.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WIDGET = ROOT / "ios/PamnotWidget"
LIST_WIDGET = WIDGET / "PamnotListWidget.swift"
LIST_INTENTS = WIDGET / "PamnotListIntents.swift"
TODAY_WIDGET = WIDGET / "PamnotTodayWidget.swift"
BUNDLE = WIDGET / "PamnotWidgetBundle.swift"
DART_SYNC = ROOT / "lib/services/widget_sync.dart"
STRINGS = {lang: WIDGET / f"{lang}.lproj/Localizable.strings" for lang in ("en", "tr")}

# English key -> Turkish value the tr table must carry.
REQUIRED_STRINGS = {
    "All": "Tümü",
    "Important · Urgent": "Önemli · Acil",
    "Important · Planned": "Önemli · Planlı",
    "Urgent · Less important": "Acil · Önemsiz",
    "Later · Maybe": "Sonra · Belki",
    "List": "Liste",
    "Box": "Kutu",
    "Open Pamnot": "Pamnot'u aç",
}

# (Dart constant in WidgetSync, Swift constant in PamnotShared)
SHARED_CONSTANTS = (
    ("appGroupId", "appGroupId"),
    ("listsKey", "listsKey"),
    ("pendingDoneKey", "pendingDoneKey"),
    ("iOSListName", "listWidgetKind"),
)

STRINGS_LINE = re.compile(r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$')
FORBIDDEN_IMPORT = re.compile(r"^\s*import\s+(home_widget|Flutter)\b", re.MULTILINE)

problems = []


def fail(message):
    problems.append(message)


def rel(path):
    return path.relative_to(ROOT)


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        fail(f"{rel(path)}: cannot read ({error.strerror})")
        return None


def strip_comments(source):
    """Drops /* */ blocks and whole-line // comments so commented-out code does not count.
    (A trailing // is kept: it cannot be told apart from "pamnot://" without a Swift lexer.)"""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return re.sub(r"^[ \t]*//[^\n]*", "", source, flags=re.MULTILINE)


def check_sources():
    widget, intents = read(LIST_WIDGET), read(LIST_INTENTS)
    if widget is not None:
        code = strip_comments(widget)
        for token in ("AppIntentConfiguration", "Button(intent:", "pamnot://list/"):
            if token not in code:
                fail(f"{rel(LIST_WIDGET)}: missing {token}")
    if intents is not None:
        code = strip_comments(intents)
        for token in ("WidgetConfigurationIntent", "PamnotCompleteTaskIntent", "AppEnum"):
            if token not in code:
                fail(f"{rel(LIST_INTENTS)}: missing {token}")
        if not re.search(r"openAppWhenRun(\s*:\s*Bool)?\s*=\s*false", code):
            fail(f"{rel(LIST_INTENTS)}: PamnotCompleteTaskIntent must set openAppWhenRun = false")

    sources = sorted(WIDGET.glob("*.swift"))
    combined = ""
    for path in sources:
        text = read(path)
        if text is None:
            continue
        if FORBIDDEN_IMPORT.search(text):
            fail(f"{rel(path)}: imports home_widget or Flutter (the extension links no pods)")
        combined += strip_comments(text)
    for literal in ('"pamnot_lists"', '"pamnot_pending_done"', "group.app.pamnot.shared"):
        if literal not in combined:
            fail(f"ios/PamnotWidget/*.swift: missing {literal}")


def check_constants():
    dart, swift = read(DART_SYNC), read(TODAY_WIDGET)
    if dart is None or swift is None:
        return
    for dart_name, swift_name in SHARED_CONSTANTS:
        d = re.search(rf"static const {dart_name} = '([^']*)';", dart)
        s = re.search(rf'static let {swift_name} = "([^"]*)"', swift)
        if not d:
            fail(f"{rel(DART_SYNC)}: WidgetSync.{dart_name} not found")
        if not s:
            fail(f"{rel(TODAY_WIDGET)}: PamnotShared.{swift_name} not found")
        if d and s and d.group(1) != s.group(1):
            fail(f"WidgetSync.{dart_name} {d.group(1)!r} != PamnotShared.{swift_name} {s.group(1)!r}")


def check_bundle():
    text = read(BUNDLE)
    if text is None:
        return
    code = strip_comments(text)
    for widget in ("PamnotTodayWidget()", "PamnotListWidget()"):
        if widget not in code:
            fail(f"{rel(BUNDLE)}: missing {widget}")


def parse_strings(path):
    text = read(path)
    if text is None:
        return None
    entries = {}
    in_block = False
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if in_block:
            in_block = "*/" not in line
            continue
        if not line or line.startswith("//"):
            continue
        if line.startswith("/*"):
            in_block = "*/" not in line[2:]
            continue
        match = STRINGS_LINE.match(raw)
        if not match:
            fail(f"{rel(path)}:{number}: not a `\"key\" = \"value\";` line: {raw!r}")
            continue
        key, value = match.group(1), match.group(2)
        if key in entries:
            fail(f"{rel(path)}:{number}: duplicate key {key!r}")
        entries[key] = value
    return entries


def check_strings():
    tables = {lang: parse_strings(path) for lang, path in STRINGS.items()}
    en, tr = tables["en"], tables["tr"]
    if en is None or tr is None:
        return
    if set(en) != set(tr):
        only_en = sorted(set(en) - set(tr))
        only_tr = sorted(set(tr) - set(en))
        fail(f"Localizable.strings keys differ: only en {only_en}, only tr {only_tr}")
    for key, turkish in REQUIRED_STRINGS.items():
        if en.get(key) != key:
            fail(f"{rel(STRINGS['en'])}: {key!r} should map to itself")
        if tr.get(key) != turkish:
            fail(f"{rel(STRINGS['tr'])}: {key!r} should be {turkish!r}, got {tr.get(key)!r}")
    for key, value in tr.items():
        if not value.strip():
            fail(f"{rel(STRINGS['tr'])}: {key!r} is empty")


def main():
    for path in (LIST_WIDGET, LIST_INTENTS):
        if not path.is_file():
            fail(f"{rel(path)}: missing")
    check_sources()
    check_constants()
    check_bundle()
    check_strings()
    if problems:
        for message in problems:
            print(message, file=sys.stderr)
        return 1
    print("widget sources ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
