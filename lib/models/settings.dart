import 'package:flutter/material.dart' show ThemeMode;

enum AppLanguage { system, tr, en }

enum PredictionLanguage { auto, tr, en }

class AppSettings {
  const AppSettings({
    this.language = AppLanguage.system,
    this.themeMode = ThemeMode.system,
    this.prediction = true,
    this.predictionLanguage = PredictionLanguage.auto,
    this.stylusOnly = false,
    this.autoStylusOnly = true,
    this.mondayFirst = true,
    this.seeded = false,
  });

  final AppLanguage language;
  final ThemeMode themeMode;

  /// Word suggestions above the keyboard.
  final bool prediction;
  final PredictionLanguage predictionLanguage;

  /// Only a stylus draws; fingers scroll (palm rejection).
  final bool stylusOnly;

  /// Turn [stylusOnly] on the first time an Apple Pencil / stylus is seen.
  final bool autoStylusOnly;
  final bool mondayFirst;

  /// Sample content was created on first launch.
  final bool seeded;

  AppSettings copyWith({
    AppLanguage? language,
    ThemeMode? themeMode,
    bool? prediction,
    PredictionLanguage? predictionLanguage,
    bool? stylusOnly,
    bool? autoStylusOnly,
    bool? mondayFirst,
    bool? seeded,
  }) =>
      AppSettings(
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        prediction: prediction ?? this.prediction,
        predictionLanguage: predictionLanguage ?? this.predictionLanguage,
        stylusOnly: stylusOnly ?? this.stylusOnly,
        autoStylusOnly: autoStylusOnly ?? this.autoStylusOnly,
        mondayFirst: mondayFirst ?? this.mondayFirst,
        seeded: seeded ?? this.seeded,
      );

  Map<String, Object?> toJson() => {
        'language': language.name,
        'themeMode': themeMode.name,
        'prediction': prediction,
        'predictionLanguage': predictionLanguage.name,
        'stylusOnly': stylusOnly,
        'autoStylusOnly': autoStylusOnly,
        'mondayFirst': mondayFirst,
        'seeded': seeded,
      };

  factory AppSettings.fromJson(Map<String, Object?> j) => AppSettings(
        language: AppLanguage.values.firstWhere((v) => v.name == j['language'],
            orElse: () => AppLanguage.system),
        themeMode: ThemeMode.values.firstWhere((v) => v.name == j['themeMode'],
            orElse: () => ThemeMode.system),
        prediction: j['prediction'] != false,
        predictionLanguage: PredictionLanguage.values.firstWhere(
            (v) => v.name == j['predictionLanguage'],
            orElse: () => PredictionLanguage.auto),
        stylusOnly: j['stylusOnly'] == true,
        autoStylusOnly: j['autoStylusOnly'] != false,
        mondayFirst: j['mondayFirst'] != false,
        seeded: j['seeded'] == true,
      );
}
