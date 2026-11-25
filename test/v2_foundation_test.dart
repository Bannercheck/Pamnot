import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/services/system_accessibility.dart';

void main() {
  test('K1 metinleri TR ve EN', () {
    expect(S.tr.unpinned, 'Sabitleme kaldırıldı');
    expect(S.en.unpinned, 'Unpinned');
    expect(S.tr.planAgendaTab, 'Takvim');
    expect(S.en.navAddTask, 'Add a task');
  });

  test('SystemAccessibility: köprü yokken false, start() hata vermez', () {
    SystemAccessibility.start();
    expect(SystemAccessibility.reduceTransparency.value, isFalse);
  });

  testWidgets('SystemAccessibility: iOS köprüsünün yanıtı ve "changed" çağrısı değeri günceller', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('app.pamnot/a11y');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async => c.method == 'reduceTransparency');
    SystemAccessibility.start();
    await tester.pump();
    expect(SystemAccessibility.reduceTransparency.value, isTrue);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.pamnot/a11y', const StandardMethodCodec().encodeMethodCall(const MethodCall('changed', false)), (_) {});
    expect(SystemAccessibility.reduceTransparency.value, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  test('pubspec derleme numarası 3', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.0.0+3'));
  });
}
