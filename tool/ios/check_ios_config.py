#!/usr/bin/env python3
"""Checks the iOS configuration of the voice-capture feature without a Mac.

Covers Info.plist, the privacy manifest, the en/tr .strings tables, the App Shortcut
phrases in VoiceTaskIntent.swift, the launch-bridge registration in AppDelegate.swift and
the bridge's two actions ("voice" from the App Intent only, "voice-link" for pamnot:// links),
the Reduce Transparency bridge (channel 'app.pamnot/a11y') and its registration, and the
AlarmKit bridge (channel 'app.pamnot/alarm'), its permission text, button titles and registration.
Standard library only. Prints every failure and exits 1; prints `ios config ok` on success.

Usage: python3 tool/ios/check_ios_config.py
"""

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "ios" / "Runner"
LANGS = ("en", "tr")
TABLES = ("InfoPlist", "AppShortcuts", "Localizable")

MIC_KEY = "NSMicrophoneUsageDescription"
SPEECH_KEY = "NSSpeechRecognitionUsageDescription"
ALARM_KEY = "NSAlarmKitUsageDescription"
INFO_KEYS = (MIC_KEY, SPEECH_KEY, ALARM_KEY)
PERMISSION_TEXT = {
    "en": {
        MIC_KEY: "Pamnot uses the microphone to hear what you say when you add a task by voice. "
        "No audio is saved.",
        SPEECH_KEY: "Pamnot uses speech recognition to turn the task you say into text. "
        "Your voice may be sent to Apple for this.",
        ALARM_KEY: "Pamnot rings an alarm at the time you set for a task or reminder.",
    },
    "tr": {
        MIC_KEY: "Pamnot, sesle görev eklerken söylediklerini duymak için mikrofonu kullanır. "
        "Ses kaydı saklanmaz.",
        SPEECH_KEY: "Pamnot, söylediğin görevi yazıya çevirmek için konuşma tanımayı kullanır. "
        "Sesin bunun için Apple'a gönderilebilir.",
        ALARM_KEY: "Pamnot, bir görev ya da hatırlatıcı için seçtiğin saatte alarm çalar.",
    },
}

FORBIDDEN_INFO_KEYS = (
    "NSSiriUsageDescription",
    "UIBackgroundModes",
    "NSUserActivityTypes",
    "NSUserNotificationsUsageDescription",
    "UIRequiresFullScreen",
)
EXPECTED_URL_TYPE = {
    "CFBundleTypeRole": "Editor",
    "CFBundleURLName": "app.pamnot.pamnot",
    "CFBundleURLSchemes": ["pamnot"],
}
EXPECTED_PRIVACY_APIS = {
    "UserDefaults": ["CA92.1", "1C8F.1"],
    "FileTimestamp": ["C617.1"],
}

APP_NAME_SWIFT = r"\(.applicationName)"
APP_NAME_STRINGS = "${applicationName}"
EXPECTED_TITLE = "Add Voice Task"
EXPECTED_PHRASE_COUNT = 4
# The alarm's button titles (PamnotAlarmPlugin.swift passes the keys to AlarmButton).
ALARM_BUTTONS = {
    "en": {"alarm.stop": "Stop", "alarm.snooze": "Snooze"},
    "tr": {"alarm.stop": "Kapat", "alarm.snooze": "Ertele"},
}

STRINGS_LINE = re.compile(r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$')
SWIFT_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')

failures = []


def fail(message):
    failures.append(message)


def load_plist(path):
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except FileNotFoundError:
        fail(f"{path.relative_to(ROOT)}: missing")
    except Exception as error:  # plistlib raises several types for malformed files
        fail(f"{path.relative_to(ROOT)}: not a valid plist ({error})")
    return None


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"{path.relative_to(ROOT)}: missing")
    except UnicodeDecodeError as error:
        fail(f"{path.relative_to(ROOT)}: not UTF-8 ({error})")
    return None


def unescape(value):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), value)


# 1. Info.plist ------------------------------------------------------------------------------

def check_info_plist():
    info = load_plist(RUNNER / "Info.plist")
    if info is None:
        return
    if info.get("CFBundleLocalizations") != ["en", "tr"]:
        fail(f"Info.plist: CFBundleLocalizations must be ['en', 'tr'], "
             f"found {info.get('CFBundleLocalizations')!r}")
    url_types = info.get("CFBundleURLTypes")
    if not isinstance(url_types, list) or not url_types or url_types[0] != EXPECTED_URL_TYPE:
        fail(f"Info.plist: CFBundleURLTypes[0] must be {EXPECTED_URL_TYPE!r}, found {url_types!r}")
    if info.get("FlutterDeepLinkingEnabled") is not False:
        fail("Info.plist: FlutterDeepLinkingEnabled must be false (otherwise pamnot://ses opens "
             "a second HomeShell)")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        fail("Info.plist: ITSAppUsesNonExemptEncryption must be false")
    for key in INFO_KEYS:
        if info.get(key) != PERMISSION_TEXT["en"][key]:
            fail(f"Info.plist: {key} must be the English permission text, found {info.get(key)!r}")
    for key in FORBIDDEN_INFO_KEYS:
        if key in info:
            fail(f"Info.plist: {key} must not be present")
    for key in info:
        if key.startswith("NSAppIntents"):
            fail(f"Info.plist: {key} must not be present (no NSAppIntents* keys)")


# 2. PrivacyInfo.xcprivacy -------------------------------------------------------------------

def check_privacy_manifest():
    manifest = load_plist(RUNNER / "PrivacyInfo.xcprivacy")
    if manifest is None:
        return
    if manifest.get("NSPrivacyTracking") is not False:
        fail("PrivacyInfo.xcprivacy: NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        fail("PrivacyInfo.xcprivacy: NSPrivacyTrackingDomains must be an empty array")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        fail("PrivacyInfo.xcprivacy: NSPrivacyCollectedDataTypes must be an empty array")
    prefix = "NSPrivacyAccessedAPICategory"
    found = {}
    for entry in manifest.get("NSPrivacyAccessedAPITypes") or []:
        category = str(entry.get("NSPrivacyAccessedAPIType", ""))
        name = category[len(prefix):] if category.startswith(prefix) else category
        if name in found:
            fail(f"PrivacyInfo.xcprivacy: {category} is listed twice")
        found[name] = entry.get("NSPrivacyAccessedAPITypeReasons")
    if found != EXPECTED_PRIVACY_APIS:
        fail(f"PrivacyInfo.xcprivacy: accessed APIs must be exactly {EXPECTED_PRIVACY_APIS!r}, "
             f"found {found!r}")


# 3. .strings tables -------------------------------------------------------------------------

def parse_strings(path):
    """Returns {key: value} or None. Only `"key" = "value";` lines, comments and blank lines."""
    text = read_text(path)
    if text is None:
        return None
    entries = {}
    in_block_comment = False
    ok = True
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if in_block_comment:
            in_block_comment = "*/" not in line
            continue
        if not line or line.startswith("//"):
            continue
        if line.startswith("/*"):
            in_block_comment = "*/" not in line[2:]
            continue
        match = STRINGS_LINE.match(raw)
        if not match:
            fail(f"{path.relative_to(ROOT)}:{number}: not a `\"key\" = \"value\";` line: {raw!r}")
            ok = False
            continue
        key, value = unescape(match.group(1)), unescape(match.group(2))
        if key in entries:
            fail(f"{path.relative_to(ROOT)}:{number}: duplicate key {key!r}")
            ok = False
        entries[key] = value
    if in_block_comment:
        fail(f"{path.relative_to(ROOT)}: unterminated comment")
        ok = False
    return entries if ok else None


def check_strings_tables():
    tables = {}
    for table in TABLES:
        per_lang = {lang: parse_strings(RUNNER / f"{lang}.lproj" / f"{table}.strings")
                    for lang in LANGS}
        tables[table] = per_lang
        if all(per_lang[lang] is not None for lang in LANGS):
            if set(per_lang["en"]) != set(per_lang["tr"]):
                fail(f"{table}.strings: en and tr keys differ: "
                     f"only en {sorted(set(per_lang['en']) - set(per_lang['tr']))}, "
                     f"only tr {sorted(set(per_lang['tr']) - set(per_lang['en']))}")
    for lang in LANGS:
        info = tables["InfoPlist"][lang]
        if info is None:
            continue
        if set(info) != set(INFO_KEYS):
            fail(f"{lang}.lproj/InfoPlist.strings: keys must be exactly {', '.join(INFO_KEYS)}, "
                 f"found {sorted(info)}")
        for key in INFO_KEYS:
            if key in info and info[key] != PERMISSION_TEXT[lang][key]:
                fail(f"{lang}.lproj/InfoPlist.strings: {key} must be "
                     f"{PERMISSION_TEXT[lang][key]!r}, found {info[key]!r}")
    for lang in LANGS:
        localizable = tables["Localizable"][lang]
        if localizable is None:
            continue
        for key, value in ALARM_BUTTONS[lang].items():
            if localizable.get(key) != value:
                fail(f"{lang}.lproj/Localizable.strings: {key} must be {value!r}, "
                     f"found {localizable.get(key)!r}")
    return tables


# 4. VoiceTaskIntent.swift -------------------------------------------------------------------

def strip_swift_comments(source):
    """Removes // and /* */ comments, leaving string literals untouched."""
    out = []
    i, n = 0, len(source)
    in_string = False
    while i < n:
        char = source[i]
        if in_string:
            out.append(char)
            if char == "\\" and i + 1 < n:
                out.append(source[i + 1])
                i += 2
                continue
            if char == '"':
                in_string = False
            i += 1
        elif source.startswith("//", i):
            end = source.find("\n", i)
            i = n if end == -1 else end
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            i = n if end == -1 else end + 2
        else:
            if char == '"':
                in_string = True
            out.append(char)
            i += 1
    return "".join(out)


def bracketed(source, start, opening, closing):
    """Returns (body, end_index) of the bracket pair opening at or after `start`, or (None, -1)."""
    begin = source.find(opening, start)
    if begin == -1:
        return None, -1
    depth = 0
    for index in range(begin, len(source)):
        if source[index] == opening:
            depth += 1
        elif source[index] == closing:
            depth -= 1
            if depth == 0:
                return source[begin + 1:index], index
    return None, -1


def check_intent(tables):
    raw = read_text(RUNNER / "VoiceTaskIntent.swift")
    if raw is None:
        return
    source = strip_swift_comments(raw)
    if 'PamnotLaunchBridge.shared.request("voice")' not in source:
        fail('VoiceTaskIntent.swift: perform() must call PamnotLaunchBridge.shared.request("voice")')
    for word in ("shortTitle", "systemImageName", "#available"):
        if word in source:
            fail(f"VoiceTaskIntent.swift: {word} must not be used (iOS 16 AppShortcut initializer)")

    title = re.search(r'static\s+let\s+title\s*:\s*LocalizedStringResource\s*=\s*"([^"]*)"', source)
    found_title = title.group(1) if title else None
    if found_title != EXPECTED_TITLE:
        fail(f"VoiceTaskIntent.swift: title must be {EXPECTED_TITLE!r}, found {found_title!r}")
    if found_title and len(found_title.split()) > 3:
        fail(f"VoiceTaskIntent.swift: title {found_title!r} is longer than three words "
             "(HIG Action button)")
    description = re.search(r'IntentDescription\(\s*"((?:[^"\\]|\\.)*)"', source)

    for lang in LANGS:
        localizable = tables["Localizable"][lang]
        if localizable is None:
            continue
        if EXPECTED_TITLE not in localizable:
            fail(f"{lang}.lproj/Localizable.strings: missing the title key {EXPECTED_TITLE!r}")
        if description and unescape(description.group(1)) not in localizable:
            fail(f"{lang}.lproj/Localizable.strings: missing the description key "
                 f"{description.group(1)!r}")

    phrases_at = source.find("phrases:")
    body, _ = bracketed(source, phrases_at, "[", "]") if phrases_at != -1 else (None, -1)
    if body is None:
        fail("VoiceTaskIntent.swift: no `phrases: [...]` list found")
        return
    phrases = SWIFT_STRING.findall(body)
    if len(phrases) != EXPECTED_PHRASE_COUNT:
        fail(f"VoiceTaskIntent.swift: expected {EXPECTED_PHRASE_COUNT} phrases, found {len(phrases)}")
    for phrase in phrases:
        if APP_NAME_SWIFT not in phrase:
            fail(f"VoiceTaskIntent.swift: phrase {phrase!r} does not contain {APP_NAME_SWIFT}")
        if re.search(r"\bsiri\b", phrase, re.IGNORECASE):
            fail(f"VoiceTaskIntent.swift: phrase {phrase!r} contains 'Siri'")
    keys = {phrase.replace(APP_NAME_SWIFT, APP_NAME_STRINGS) for phrase in phrases}

    for lang in LANGS:
        shortcuts = tables["AppShortcuts"][lang]
        if shortcuts is None:
            continue
        if set(shortcuts) != keys:
            fail(f"{lang}.lproj/AppShortcuts.strings: keys must equal the Swift phrases: "
                 f"missing {sorted(keys - set(shortcuts))}, extra {sorted(set(shortcuts) - keys)}")
        for key, value in shortcuts.items():
            if APP_NAME_STRINGS not in value:
                fail(f"{lang}.lproj/AppShortcuts.strings: {value!r} does not contain "
                     f"{APP_NAME_STRINGS}")
            if re.search(r"\bsiri\b", value, re.IGNORECASE):
                fail(f"{lang}.lproj/AppShortcuts.strings: {value!r} contains 'Siri'")
            if lang == "tr" and re.search(re.escape(APP_NAME_STRINGS) + "['’]", value):
                fail(f"tr.lproj/AppShortcuts.strings: {value!r} adds a suffix to the app name "
                     "(it must stay bare: 'Pamnot ile ...')")


# 5. AppDelegate.swift -----------------------------------------------------------------------

# Bridges AppDelegate registers on the UI engine only, after the background-engine callback.
UI_ENGINE_BRIDGES = ("PamnotLaunchBridge", "PamnotAccessibilityBridge", "PamnotAlarmPlugin")


def check_app_delegate():
    raw = read_text(RUNNER / "AppDelegate.swift")
    if raw is None:
        return
    source = strip_swift_comments(raw)
    method = source.find("func didInitializeImplicitFlutterEngine")
    _, method_end = bracketed(source, method, "{", "}") if method != -1 else (None, -1)
    callback = source.find("setPluginRegistrantCallback {")
    if callback == -1:
        fail("AppDelegate.swift: setPluginRegistrantCallback { ... } block not found")
    _, callback_end = bracketed(source, callback, "{", "}") if callback != -1 else (None, -1)
    for bridge in UI_ENGINE_BRIDGES:
        registration = source.find(f'registrar(forPlugin: "{bridge}")')
        if registration == -1:
            fail(f'AppDelegate.swift: no `registrar(forPlugin: "{bridge}")` call')
            continue
        if f"{bridge}.register(with:" not in source[registration:]:
            fail(f"AppDelegate.swift: no `{bridge}.register(with:` call after its registrar lookup")
        if method == -1 or method_end == -1 or not method < registration < method_end:
            fail(f"AppDelegate.swift: {bridge} must be registered inside "
                 "didInitializeImplicitFlutterEngine")
        if callback != -1 and (callback_end == -1 or registration < callback_end):
            fail(f"AppDelegate.swift: {bridge} must be registered after the "
                 "setPluginRegistrantCallback block closes (never on the background engine)")


# 6. PamnotLaunchBridge.swift ----------------------------------------------------------------

def check_bridge():
    raw = read_text(RUNNER / "PamnotLaunchBridge.swift")
    if raw is None:
        return
    source = strip_swift_comments(raw)
    for needle in ('"app.pamnot/launch"', "takePendingAction", "actionAvailable",
                   "static let shared", '"ses"', '"voice"'):
        if needle not in source:
            fail(f"PamnotLaunchBridge.swift: {needle} not found")
    # A pamnot:// link can come from any app or page: it asks for "voice-link", which
    # Dart opens paused (no listening without a tap). Only the App Intent asks for "voice".
    if 'request("voice-link")' not in source:
        fail('PamnotLaunchBridge.swift: a claimed link must call request("voice-link")')
    if 'request("voice")' in source:
        fail('PamnotLaunchBridge.swift: request("voice") (listen at once) is for the App Intent only')


# 7. PamnotAccessibilityBridge.swift ---------------------------------------------------------

def check_accessibility_bridge():
    raw = read_text(RUNNER / "PamnotAccessibilityBridge.swift")
    if raw is None:
        return
    source = strip_swift_comments(raw)
    # The channel contract of lib/services/system_accessibility.dart.
    for needle in ('"app.pamnot/a11y"', '"reduceTransparency"', '"changed"', "static let shared",
                   "UIAccessibility.isReduceTransparencyEnabled",
                   "UIAccessibility.reduceTransparencyStatusDidChangeNotification"):
        if needle not in source:
            fail(f"PamnotAccessibilityBridge.swift: {needle} not found")


# 8. PamnotAlarmPlugin.swift -----------------------------------------------------------------

def check_alarm_plugin():
    raw = read_text(RUNNER / "PamnotAlarmPlugin.swift")
    if raw is None:
        return
    source = strip_swift_comments(raw)
    # The channel contract of lib/services/alarm_scheduler.dart.
    for needle in ('"app.pamnot/alarm"', '"access"', '"requestAccess"', '"sync"',
                   '"unsupported"', '"notDetermined"', '"denied"', '"authorized"',
                   "class PamnotAlarmPlugin: NSObject, FlutterPlugin",
                   "#if canImport(AlarmKit)", "#available(iOS 26.0, *)",
                   '"pamnot_alarm_ids"', '"alarm.stop"', '"alarm.snooze"',
                   "PamnotSnoozeIntent", "LiveActivityIntent", "PamnotAlarmMetadata"):
        if needle not in source:
            fail(f"PamnotAlarmPlugin.swift: {needle} not found")
    # AlarmKit is only in the iOS 26 SDK: importing it outside `#if canImport(AlarmKit)`
    # breaks the build on an older Xcode instead of answering "unsupported".
    guard = source.find("#if canImport(AlarmKit)")
    imported = source.find("import AlarmKit")
    if imported == -1:
        fail("PamnotAlarmPlugin.swift: import AlarmKit not found")
    elif guard == -1 or imported < guard:
        fail("PamnotAlarmPlugin.swift: import AlarmKit must be inside #if canImport(AlarmKit)")
    # `sync` cancels the stored ids, awaits each schedule and then stores the new ids: two
    # overlapping calls would orphan alarms no later sync cancels. Each call waits for the
    # previous one (`syncTail`), and the tail is swapped synchronously on the main thread.
    for needle in ("static var syncTail: Task<Void, Never>?", "let previous = syncTail",
                   "await previous?.value", "syncTail = Task", "MainActor.assumeIsolated"):
        if needle not in source:
            fail(f"PamnotAlarmPlugin.swift: sync must be serialized ({needle} not found)")


def main():
    check_info_plist()
    check_privacy_manifest()
    tables = check_strings_tables()
    check_intent(tables)
    check_app_delegate()
    check_bridge()
    check_accessibility_bridge()
    check_alarm_plugin()
    if failures:
        for message in failures:
            print(f"FAIL {message}")
        return 1
    print("ios config ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
