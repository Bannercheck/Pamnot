import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../models/ink.dart';
import 'handwriting.dart';

HandwritingRecognizer createRecognizer() =>
    (Platform.isIOS || Platform.isAndroid) ? _MlKitRecognizer() : UnsupportedRecognizer();

class _MlKitRecognizer implements HandwritingRecognizer {
  final _models = mlkit.DigitalInkRecognizerModelManager();
  final _recognizers = <String, mlkit.DigitalInkRecognizer>{};

  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelReady(String model) async {
    try {
      return await _models.isModelDownloaded(model);
    } catch (e) {
      debugPrint('Model check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> prepare(String model) async {
    if (await isModelReady(model)) return true;
    try {
      return await _models.downloadModel(model, isWifiRequired: false);
    } catch (e) {
      debugPrint('Model download failed: $e');
      return false;
    }
  }

  @override
  Future<List<String>> recognize(List<InkStroke> strokes,
      {required String model, String preContext = ''}) async {
    if (strokes.isEmpty || !await prepare(model)) return const [];
    final ink = mlkit.Ink();
    for (final s in strokes) {
      final stroke = mlkit.Stroke();
      for (var i = 0; i < s.length; i++) {
        stroke.points.add(mlkit.StrokePoint(x: s.x(i), y: s.y(i), t: s.startedAt + s.t(i)));
      }
      ink.strokes.add(stroke);
    }
    final recognizer = _recognizers.putIfAbsent(model, () => mlkit.DigitalInkRecognizer(languageCode: model));
    final bounds = strokes.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
    try {
      final result = await recognizer.recognize(
        ink,
        context: mlkit.DigitalInkRecognitionContext(
          preContext: preContext.length > 20 ? preContext.substring(preContext.length - 20) : preContext,
          writingArea: mlkit.WritingArea(width: bounds.width, height: bounds.height),
        ),
      );
      return [for (final c in result) c.text];
    } catch (e) {
      debugPrint('Recognition failed: $e');
      return const [];
    }
  }
}
