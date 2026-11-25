import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The guide videos (Task 24): rendered by `tool/guide/make_videos.sh` from
/// the guide's own animation and bundled through `pubspec.yaml`.
void main() {
  const videos = ['shortcut', 'action_button', 'back_tap', 'outlook'];

  for (final name in videos) {
    test('assets/guide/$name.mp4 exists, is at most 600 KB and is an MP4', () {
      final file = File('assets/guide/$name.mp4');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final bytes = file.readAsBytesSync();
      expect(bytes.length, lessThanOrEqualTo(600 * 1024));
      // An ISO media file starts with a box size (4 bytes) and then `ftyp`.
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
    });
  }

  test('pubspec.yaml bundles assets/guide/', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('    - assets/guide/'));
  });
}
