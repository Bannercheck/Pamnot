import Flutter
import UIKit

/// Reports iOS accessibility settings Flutter does not expose to Dart
/// (lib/services/system_accessibility.dart, channel 'app.pamnot/a11y').
/// Today that is "Reduce Transparency": Dart asks with `reduceTransparency` (-> Bool),
/// and the bridge sends `changed(Bool)` whenever the user flips the setting.
final class PamnotAccessibilityBridge: NSObject, FlutterPlugin {
  static let shared = PamnotAccessibilityBridge()

  private var channel: FlutterMethodChannel?
  private var observer: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.pamnot/a11y", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
    if shared.observer == nil {
      shared.observer = NotificationCenter.default.addObserver(
        forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        object: nil,
        queue: .main
      ) { _ in
        // Delivered on the main queue: platform channels must be used on the main thread.
        PamnotAccessibilityBridge.shared.channel?.invokeMethod("changed", arguments: UIAccessibility.isReduceTransparencyEnabled)
      }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "reduceTransparency":
      result(UIAccessibility.isReduceTransparencyEnabled)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
