import Flutter
import UIKit

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import SwiftUI
#endif

/// Alarms that ring like the Clock app's (AlarmKit, iOS 26+), for
/// lib/services/alarm_scheduler.dart (channel 'app.pamnot/alarm').
///
/// - `access` and `requestAccess` answer "unsupported" | "notDetermined" | "denied" | "authorized".
/// - `sync` takes `[{id: UUID string, title, at: epoch ms, repeat: none|daily|weekly|monthly|yearly}]`
///   and replaces the alarms the previous `sync` set. Snoozed alarms are not touched.
///
/// The class compiles with every SDK: without AlarmKit, or below iOS 26, it answers "unsupported"
/// and `sync` does nothing.
final class PamnotAlarmPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.pamnot/alarm", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PamnotAlarmPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      PamnotAlarms.handle(call, result: result)
      return
    }
    #endif
    switch call.method {
    case "access", "requestAccess":
      result("unsupported")
    case "sync":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

#if canImport(AlarmKit)

/// Pamnot's alarms carry no extra data.
@available(iOS 26.0, *)
struct PamnotAlarmMetadata: AlarmMetadata {}

/// The alarm's "Snooze" button: sets a new alarm with the same title nine minutes from now.
/// It is not in the synced id set, so the next `sync` leaves it alone.
@available(iOS 26.0, *)
struct PamnotSnoozeIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "alarm.snooze"
  static let isDiscoverable = false

  @Parameter(title: "alarm.snooze")
  var alarmTitle: String

  init() {}

  init(title: String) {
    alarmTitle = title
  }

  func perform() async throws -> some IntentResult {
    try await PamnotAlarms.schedule(
      id: UUID(),
      title: alarmTitle,
      schedule: .fixed(Date().addingTimeInterval(PamnotAlarms.snoozeInterval))
    )
    return .result()
  }
}

@available(iOS 26.0, *)
enum PamnotAlarms {
  /// The alarm ids the last `sync` set (snoozed alarms are never added).
  static let idsKey = "pamnot_alarm_ids"
  static let snoozeInterval: TimeInterval = 9 * 60

  /// The last `sync` started; the next one awaits it (see `handle`).
  @MainActor static var syncTail: Task<Void, Never>?

  static let everyDay: [Locale.Weekday] = [
    .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
  ]

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "access":
      result(name(of: AlarmManager.shared.authorizationState))
    case "requestAccess":
      Task { @MainActor in
        do {
          result(name(of: try await AlarmManager.shared.requestAuthorization()))
        } catch {
          result(name(of: AlarmManager.shared.authorizationState))
        }
      }
    case "sync":
      let items = call.arguments as? [[String: Any]] ?? []
      // Flutter calls handlers on the main thread, so the tail is read and replaced in call
      // order before anything suspends: each sync starts only after the previous one stored
      // its ids. Overlapping syncs would otherwise both cancel the same stored set, both
      // schedule, and leave the alarms of the earlier one in no stored set (never cancelled).
      MainActor.assumeIsolated {
        let previous = syncTail
        syncTail = Task { @MainActor in
          await previous?.value
          result(await sync(items))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func name(of state: AlarmManager.AuthorizationState) -> String {
    switch state {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .authorized: return "authorized"
    @unknown default: return "denied"
    }
  }

  /// Cancels the previously synced alarms, sets [items] and stores their ids.
  /// Answers nil, or a FlutterError naming how many alarms could not be set.
  @MainActor
  static func sync(_ items: [[String: Any]]) async -> Any? {
    let defaults = UserDefaults.standard
    for stored in defaults.stringArray(forKey: idsKey) ?? [] {
      if let id = UUID(uuidString: stored) {
        try? AlarmManager.shared.cancel(id: id)
      }
    }
    var ids: [String] = []
    var failed = 0
    for item in items {
      guard
        let idText = item["id"] as? String,
        let id = UUID(uuidString: idText),
        let title = item["title"] as? String,
        let at = (item["at"] as? NSNumber)?.doubleValue
      else {
        failed += 1
        continue
      }
      let date = Date(timeIntervalSince1970: at / 1000)
      do {
        try await schedule(id: id, title: title, schedule: schedule(at: date, rule: item["repeat"] as? String))
        ids.append(id.uuidString)
      } catch {
        failed += 1
      }
    }
    defaults.set(ids, forKey: idsKey)
    return failed == 0 ? nil : FlutterError(code: "sync", message: "\(failed) alarm(s) not set", details: nil)
  }

  /// [rule] is the Dart `repeat` name. none, monthly and yearly ring once at [date] (Dart sends
  /// the next occurrence and syncs again on every launch); daily and weekly repeat at [date]'s
  /// time of day.
  static func schedule(at date: Date, rule: String?) -> Alarm.Schedule {
    let calendar = Calendar.current
    let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
    let time = Alarm.Schedule.Relative.Time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    switch rule {
    case "daily":
      return .relative(.init(time: time, repeats: .weekly(everyDay)))
    case "weekly":
      // Calendar weekday: 1 = Sunday ... 7 = Saturday.
      let day = everyDay[((parts.weekday ?? 1) - 1 + 7) % 7]
      return .relative(.init(time: time, repeats: .weekly([day])))
    default:
      return .fixed(date)
    }
  }

  static func schedule(id: UUID, title: String, schedule: Alarm.Schedule) async throws {
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(String.LocalizationValue(escapedFormat(title))),
      stopButton: AlarmButton(text: "alarm.stop", textColor: .white, systemImageName: "stop.circle"),
      secondaryButton: AlarmButton(text: "alarm.snooze", textColor: .white, systemImageName: "zzz"),
      secondaryButtonBehavior: .custom
    )
    let attributes = AlarmAttributes<PamnotAlarmMetadata>(
      presentation: AlarmPresentation(alert: alert),
      metadata: PamnotAlarmMetadata(),
      tintColor: Color(red: 0.435, green: 0.361, blue: 0.749)
    )
    let configuration = AlarmManager.AlarmConfiguration.alarm(
      schedule: schedule,
      attributes: attributes,
      stopIntent: nil,
      secondaryIntent: PamnotSnoozeIntent(title: title)
    )
    _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
  }

  /// The user's title is not a localization key: a String.LocalizationValue built from a plain
  /// String is read as a format, so every "%" is doubled to show as itself.
  static func escapedFormat(_ title: String) -> String {
    title.replacingOccurrences(of: "%", with: "%%")
  }
}

#endif
