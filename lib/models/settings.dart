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
    this.keepVoiceLog = false,
    this.notificationsAsked = false,
    this.lastListId = '',
    this.voiceAutoSave = true,
    this.dailyMotivation = true,
    int motivationMinutes = defaultMotivationMinutes,
  }) : motivationMinutes = motivationMinutes < 0 ? 0 : (motivationMinutes > 1439 ? 1439 : motivationMinutes);

  /// 09:00.
  static const defaultMotivationMinutes = 540;

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

  /// Keep the last recognised voice transcripts on this device (off by default).
  final bool keepVoiceLog;

  /// The notification permission prompt has been shown once already.
  final bool notificationsAsked;

  /// The list used last; '' means the first list.
  final String lastListId;

  /// A voice task with no list picked saves by itself after 8 seconds.
  final bool voiceAutoSave;

  /// A short, gentle line as a notification every day.
  final bool dailyMotivation;

  /// When [dailyMotivation] arrives, in minutes after midnight (0..1439).
  final int motivationMinutes;

  AppSettings copyWith({
    AppLanguage? language,
    ThemeMode? themeMode,
    bool? prediction,
    PredictionLanguage? predictionLanguage,
    bool? stylusOnly,
    bool? autoStylusOnly,
    bool? mondayFirst,
    bool? seeded,
    bool? keepVoiceLog,
    bool? notificationsAsked,
    String? lastListId,
    bool? voiceAutoSave,
    bool? dailyMotivation,
    int? motivationMinutes,
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
        keepVoiceLog: keepVoiceLog ?? this.keepVoiceLog,
        notificationsAsked: notificationsAsked ?? this.notificationsAsked,
        lastListId: lastListId ?? this.lastListId,
        voiceAutoSave: voiceAutoSave ?? this.voiceAutoSave,
        dailyMotivation: dailyMotivation ?? this.dailyMotivation,
        motivationMinutes: motivationMinutes ?? this.motivationMinutes,
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
        'keepVoiceLog': keepVoiceLog,
        'notificationsAsked': notificationsAsked,
        'lastListId': lastListId,
        'voiceAutoSave': voiceAutoSave,
        'dailyMotivation': dailyMotivation,
        'motivationMinutes': motivationMinutes,
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
        keepVoiceLog: j['keepVoiceLog'] == true,
        notificationsAsked: j['notificationsAsked'] == true,
        lastListId: (j['lastListId'] as String?) ?? '',
        voiceAutoSave: j['voiceAutoSave'] != false,
        dailyMotivation: j['dailyMotivation'] != false,
        motivationMinutes: (j['motivationMinutes'] as num?)?.toInt() ?? defaultMotivationMinutes,
      );
}
