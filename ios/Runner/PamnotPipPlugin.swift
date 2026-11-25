import AVFoundation
import AVKit
import Flutter
import UIKit

/// Plays a short, muted guide video in Picture in Picture so it keeps playing over the Settings
/// app (design §10), for lib/services/pip_player.dart (channel 'app.pamnot/pip').
///
/// - `isSupported` → Bool: whether the device can play in Picture in Picture.
/// - `prepare {asset}`: loads the bundled Flutter asset (e.g. 'assets/guide/action_button.mp4')
///   into a muted, looping player whose layer sits behind the Flutter view.
/// - `start` → Bool: plays and starts Picture in Picture; answers whether it started within
///   0.8 s. Dart only calls it from a user's tap: the app never starts Picture in Picture by itself.
/// - `stop`: stops Picture in Picture, removes the player and its layer and gives the audio
///   session back to other apps. Closing the Picture in Picture window does the same.
///
/// The video has no sound; the audio session (`.playback`, mixed with others) exists only because
/// Picture in Picture needs it, and never interrupts music that is already playing.
final class PamnotPipPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate {
  static let shared = PamnotPipPlugin()

  /// How long `start` waits for Picture in Picture to begin before answering false.
  private static let startTimeout: TimeInterval = 0.8
  private static let videoSize = CGSize(width: 160, height: 90)

  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var hostView: UIView?
  /// Held strongly: Picture in Picture ends when the controller is released.
  private var controller: AVPictureInPictureController?
  private var possibleObservation: NSKeyValueObservation?
  private var pendingStart: FlutterResult?
  private var startTimer: DispatchWorkItem?
  private var sessionActive = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.pamnot/pip", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "prepare":
      guard let arguments = call.arguments as? [String: Any], let asset = arguments["asset"] as? String else {
        result(FlutterError(code: "bad_arguments", message: "prepare needs {asset}", details: nil))
        return
      }
      prepare(asset: asset, result: result)
    case "start":
      start(result: result)
    case "stop":
      tearDown()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Channel methods

  private func prepare(asset: String, result: FlutterResult) {
    tearDown()
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      result(nil)
      return
    }
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      result(FlutterError(code: "missing_asset", message: "No bundled asset \(asset)", details: nil))
      return
    }
    guard let root = Self.rootViewController() else {
      result(FlutterError(code: "no_view", message: "No root view controller", details: nil))
      return
    }

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try session.setActive(true)
      sessionActive = true
    } catch {
      result(FlutterError(code: "audio_session", message: error.localizedDescription, details: nil))
      return
    }

    let player = AVQueuePlayer()
    player.isMuted = true
    let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: path)))

    // Picture in Picture needs the layer in the view hierarchy, neither hidden nor transparent.
    // The root view is the FlutterView itself: index 0 puts the host below the root view's other
    // subviews, but it may still draw over Flutter's own render layer (a small box at the top-left).
    // TESTING.md lists the device check for this.
    let host = UIView(frame: CGRect(origin: .zero, size: Self.videoSize))
    host.isUserInteractionEnabled = false
    let playerLayer = AVPlayerLayer(player: player)
    playerLayer.frame = host.bounds
    playerLayer.videoGravity = .resizeAspect
    host.layer.addSublayer(playerLayer)
    root.view.insertSubview(host, at: 0)

    self.player = player
    self.looper = looper
    self.hostView = host

    guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
      tearDown()
      result(FlutterError(code: "unsupported", message: "Picture in Picture is not available", details: nil))
      return
    }
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    controller.delegate = self
    self.controller = controller
    result(nil)
  }

  private func start(result: @escaping FlutterResult) {
    // A start that is still waiting answers false; only the latest tap counts.
    finishStart(false)
    guard let player = player, let controller = controller else {
      result(false)
      return
    }
    if controller.isPictureInPictureActive {
      result(true)
      return
    }
    pendingStart = result
    player.play()
    if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    } else {
      // Right after `prepare` the video may not be ready yet: start as soon as it is,
      // but only while this tap's wait lasts.
      possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] observed, _ in
        DispatchQueue.main.async {
          guard let self = self, self.pendingStart != nil, observed === self.controller,
                observed.isPictureInPicturePossible else { return }
          self.possibleObservation = nil
          observed.startPictureInPicture()
        }
      }
    }
    let timer = DispatchWorkItem { [weak self] in self?.finishStart(false) }
    startTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.startTimeout, execute: timer)
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pictureInPictureController === controller else { return }
    finishStart(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    guard pictureInPictureController === controller else { return }
    finishStart(false)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    guard pictureInPictureController === controller else { return }
    tearDown()
  }

  // MARK: - Helpers

  private func finishStart(_ started: Bool) {
    startTimer?.cancel()
    startTimer = nil
    possibleObservation = nil
    guard let result = pendingStart else { return }
    pendingStart = nil
    result(started)
  }

  /// Stops Picture in Picture and removes everything `prepare` created. Safe to call repeatedly.
  private func tearDown() {
    finishStart(false)
    if let controller = controller {
      controller.delegate = nil
      if controller.isPictureInPictureActive {
        controller.stopPictureInPicture()
      }
    }
    controller = nil
    looper?.disableLooping()
    looper = nil
    player?.pause()
    player?.removeAllItems()
    player = nil
    hostView?.removeFromSuperview()
    hostView = nil
    if sessionActive {
      sessionActive = false
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private static func rootViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
  }
}
