import AppIntents

/// "Sesle Görev Ekle": opens Pamnot on the listening screen. Shown in Shortcuts, Spotlight,
/// Siri and the Action button without any setup. Needs no entitlement.
struct VoiceTaskIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Voice Task"
  static let description = IntentDescription("Opens Pamnot and listens so you can add a task by voice.")

  @MainActor
  func perform() async throws -> some IntentResult {
    PamnotLaunchBridge.shared.request("voice")
    return .result()
  }
}

// openAppWhenRun is deprecated in the iOS 26 SDK (supportedModes replaces it, iOS 26+ only).
// Apple's documented way to keep supporting iOS 16 without the warning.
@available(*, deprecated)
extension VoiceTaskIntent {
  static var openAppWhenRun: Bool { true }
}

struct PamnotShortcuts: AppShortcutsProvider {
  // iOS 16 initializer on purpose: no shortTitle/systemImageName, no availability checks here.
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: VoiceTaskIntent(),
      phrases: [
        "Add a task in \(.applicationName)",
        "Add a \(.applicationName) task",
        "New task in \(.applicationName)",
        "Add a voice task in \(.applicationName)",
      ]
    )
  }
}
