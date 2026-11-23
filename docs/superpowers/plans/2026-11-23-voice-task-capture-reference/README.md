# Reference material (not production code)

Throwaway prototypes and notes written during the design research for the voice task capture
feature. They are kept here so the plan can point at them; they are **not** part of the app and
are stored with a `.txt` suffix so `flutter analyze` ignores them.

| File | What it is |
| --- | --- |
| `research-notes.md` | The four research reports (speech plugin, App Intents in this app, spoken date parsing, app integration), with sources |
| `spoken_parse.dart.txt` | Reference parser that passes the original 145 vectors (re-implement test-first; do not copy blindly) |
| `vectors.dart.txt` | The original 145 vectors as Dart data |
| `speech_engine.dart.txt`, `fake_speech_engine.dart.txt`, `voice_harness_test.dart.txt` | Prototype speech engine interface, fake and a widget test that drove the full listen loop |
| `launch_actions.dart.txt` | Prototype Dart side of the native launch bridge |
| `deeplink_probe_test.dart.txt`, `app_dart.diff.txt` | Probe proving `pamnot://ses` pushes a second HomeShell today, and the `didPushRouteInformation` fix |
| `add_voice_files.rb.txt` | Idempotent `xcodeproj` gem script that adds the new iOS files to `Runner.xcodeproj` |
