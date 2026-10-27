import '../models/ink.dart';
import 'handwriting_stub.dart' if (dart.library.io) 'handwriting_mlkit.dart' as platform;

/// Turns ink into text. Backed by on-device ML Kit on iOS, iPadOS and
/// Android; elsewhere [isSupported] is false and the UI hides the action.
abstract class HandwritingRecognizer {
  bool get isSupported;

  /// ML Kit language tag for the app language ("tr" or "en-US").
  static String modelFor(String lang) => lang == 'tr' ? 'tr' : 'en-US';

  Future<bool> isModelReady(String model);

  /// Downloads the model (about 20 MB) if needed. Returns false on failure.
  Future<bool> prepare(String model);

  /// Candidate readings, best first.
  Future<List<String>> recognize(
    List<InkStroke> strokes, {
    required String model,
    String preContext = '',
  });

  static HandwritingRecognizer platformDefault() => platform.createRecognizer();
}

class UnsupportedRecognizer implements HandwritingRecognizer {
  @override
  bool get isSupported => false;

  @override
  Future<bool> isModelReady(String model) async => false;

  @override
  Future<bool> prepare(String model) async => false;

  @override
  Future<List<String>> recognize(List<InkStroke> strokes,
          {required String model, String preContext = ''}) async =>
      const [];
}
