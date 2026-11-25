// Renders the frames of the guide videos from the guide's own animation.
//
// Run only through `tool/guide/make_videos.sh`, which sets GUIDE_FRAMES and
// turns the frames into `assets/guide/<name>.mp4`. It lives outside `test/`,
// so a plain `flutter test` never runs it, and it asserts nothing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/guide/phone_hand_animation.dart';

/// The video's file name (without `.mp4`) for each scene.
const names = {
  GuideScene.shortcut: 'shortcut',
  GuideScene.actionButton: 'action_button',
  GuideScene.backTap: 'back_tap',
  GuideScene.outlook: 'outlook',
};

/// 30 frames a second; a round of the animation is six seconds (180 frames)
/// and a video holds two rounds (12 seconds).
const roundFrames = 180;
const videoFrames = 2 * roundFrames;

void main() {
  final out = Platform.environment['GUIDE_FRAMES'];

  for (final scene in GuideScene.values) {
    testWidgets('frames of ${names[scene]}', (tester) async {
      if (out == null || out.isEmpty) {
        fail('Set GUIDE_FRAMES to the folder for the frames (tool/guide/make_videos.sh does).');
      }
      tester.view.physicalSize = const Size(540, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dir = Directory('$out/${names[scene]}')..createSync(recursive: true);
      final boundary = GlobalKey();
      final theme = PamnotTheme.light();

      for (var i = 0; i < videoFrames; i++) {
        await tester.pumpWidget(
          Theme(
            data: theme,
            child: RepaintBoundary(
              key: boundary,
              // The light theme's surface behind the phone; no text.
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: PhoneHandAnimation(scene: scene, progress: (i % roundFrames) / roundFrames),
              ),
            ),
          ),
        );
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final name = i.toString().padLeft(4, '0');
          await File('${dir.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
        });
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
