#!/usr/bin/env python3
"""Checks the v3 Swift sources (and v3 Dart logging) without a Mac.

Standard library only. Swift rules run after comments are removed (string literals
are also blanked for the code-shape rules):

1. Every file in V3_SWIFT exists under ios/Runner.
2. No `try!`, `as!` or postfix force unwrap (`x!`, `f()!`, `a[0]!`).
3. No `print(`, `NSLog(` or `os_log(` (logs must not carry user text).
4. No `publicCloudDatabase` (only the private and shared CloudKit databases are used).
5. Every file that adopts FlutterPlugin answers unknown methods with
   FlutterMethodNotImplemented.
6. Every `FlutterError(code: "...")` uses one of the fixed codes in ERROR_CODES.
7. REQUIRED (file -> strings that must appear) and FORBIDDEN (file -> strings that
   must not appear) tables, filled in by the v3 Swift tasks.

Dart: no `debugPrint(` line in lib/features/**/*.dart interpolates a value whose
name contains title, body, text, payload or name.

Prints "v3 sources ok" and exits 0 when everything holds; otherwise prints one
"FAIL ..." line per problem and exits 1.

Run from anywhere: python3 tool/ios/check_v3_sources.py
"""

import re
import sys
from pathlib import Path

from check_ios_config import strip_swift_comments

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "ios" / "Runner"
FEATURES = ROOT / "lib" / "features"

# Later v3 Swift tasks append their file name here.
V3_SWIFT = []

# File name -> strings that must appear (after comments are removed).
REQUIRED = {}

# File name -> strings that must not appear (after comments are removed).
FORBIDDEN = {}

ERROR_CODES = {"bad_args", "unsupported", "no_account", "busy", "not_found", "failed"}

SWIFT_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
FORCE_UNWRAP = re.compile(r"[\w\)\]]!(?![=\w])")
BANNED_CALLS = ("print(", "NSLog(", "os_log(")
FLUTTER_ERROR_CODE = re.compile(r'FlutterError\(\s*code:\s*"((?:[^"\\]|\\.)*)"')
FLUTTER_ERROR_ANY = re.compile(r"FlutterError\(\s*code:")
ADOPTS_PLUGIN = re.compile(r"\b(?:class|extension)\s+\w+[^{]*:[^{]*\bFlutterPlugin\b")

DART_SENSITIVE = re.compile(r"title|body|text|payload|name", re.IGNORECASE)
DART_SIMPLE_INTERPOLATION = re.compile(r"\$([A-Za-z_]\w*)")
DART_BRACED_INTERPOLATION = re.compile(r"\$\{([^}]*)\}")

failures = []


def fail(message):
    failures.append(message)


def blank_strings(code):
    return SWIFT_STRING.sub('""', code)


def check_swift_file(name):
    path = RUNNER / name
    try:
        source = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"{name}: missing at {path.relative_to(ROOT)}")
        return
    except UnicodeDecodeError as error:
        fail(f"{name}: not UTF-8 ({error})")
        return

    code = strip_swift_comments(source)
    shape = blank_strings(code)

    if "try!" in shape:
        fail(f"{name}: try! must not be used")
    if "as!" in shape:
        fail(f"{name}: as! must not be used")
    for match in FORCE_UNWRAP.finditer(shape.replace("try!", "").replace("as!", "")):
        line = shape.count("\n", 0, match.start()) + 1
        fail(f"{name}:{line}: force unwrap must not be used")
    for call in BANNED_CALLS:
        if re.search(r"(?<![\w.])" + re.escape(call), shape):
            fail(f"{name}: {call} must not be used (no logging of user text)")
    if "publicCloudDatabase" in shape:
        fail(f"{name}: publicCloudDatabase must not be used")

    if ADOPTS_PLUGIN.search(shape) and "FlutterMethodNotImplemented" not in shape:
        fail(f"{name}: adopts FlutterPlugin but never returns FlutterMethodNotImplemented")

    coded = FLUTTER_ERROR_CODE.findall(code)
    if len(coded) != len(FLUTTER_ERROR_ANY.findall(code)):
        fail(f"{name}: every FlutterError(code:) must use a string literal code")
    for error_code in coded:
        if error_code not in ERROR_CODES:
            fail(f"{name}: FlutterError code {error_code!r} is not one of {sorted(ERROR_CODES)}")

    for needle in REQUIRED.get(name, ()):
        if needle not in code:
            fail(f"{name}: {needle!r} missing")
    for needle in FORBIDDEN.get(name, ()):
        if needle in code:
            fail(f"{name}: {needle!r} must not be used")


def check_tables():
    for table_name, table in (("REQUIRED", REQUIRED), ("FORBIDDEN", FORBIDDEN)):
        for name in table:
            if name not in V3_SWIFT:
                fail(f"{table_name}: {name} is not listed in V3_SWIFT")


def check_dart_logging():
    if not FEATURES.is_dir():
        return
    for path in sorted(FEATURES.rglob("*.dart")):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError as error:
            fail(f"{path.relative_to(ROOT)}: not UTF-8 ({error})")
            continue
        for number, line in enumerate(lines, start=1):
            if "debugPrint(" not in line:
                continue
            values = DART_SIMPLE_INTERPOLATION.findall(line) + DART_BRACED_INTERPOLATION.findall(line)
            if any(DART_SENSITIVE.search(value) for value in values):
                fail(f"{path.relative_to(ROOT)}:{number}: debugPrint must not interpolate user text")


def main():
    for name in V3_SWIFT:
        check_swift_file(name)
    check_tables()
    check_dart_logging()
    if failures:
        for message in failures:
            print(f"FAIL {message}")
        return 1
    print("v3 sources ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
