import Flutter
import UIKit

/// Carries "open this screen" requests from iOS (App Intent, pamnot:// links) to Dart.
/// Holds one pending action; Dart pulls it with `takePendingAction`, so the request
/// survives whichever side is ready first.
final class PamnotLaunchBridge: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  /// The engine keeps scene delegates weakly, so the bridge must own itself.
  static let shared = PamnotLaunchBridge()

  private var channel: FlutterMethodChannel?
  private var pendingAction: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.pamnot/launch", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
    registrar.addSceneDelegate(shared)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePendingAction":
      let action = pendingAction
      pendingAction = nil
      result(action)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Call on the main thread.
  func request(_ action: String) {
    pendingAction = action
    channel?.invokeMethod("actionAvailable", arguments: nil)
  }

  /// Only pamnot://ses and pamnot://voice; home_widget's `?homeWidget` links are left alone.
  /// Any app or web page can open a link, so it asks for "voice-link": Dart opens the screen
  /// paused, and listening needs a tap inside Pamnot ("voice", from VoiceTaskIntent, listens).
  /// Nothing in the URL is ever saved as a task.
  private func claim(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "pamnot", let host = url.host?.lowercased(),
      host == "ses" || host == "voice"
    else { return false }
    request("voice-link")
    return true
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    var claimed = false
    for context in contexts where claim(context.url) { claimed = true }
    return claimed
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var claimed = false
    for context in URLContexts where claim(context.url) { claimed = true }
    return claimed
  }
}
