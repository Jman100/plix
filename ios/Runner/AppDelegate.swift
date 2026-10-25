import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var channel: FlutterMethodChannel?
  private var simulatedDuoPosture: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    setupAudioSession()

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    controller.isViewOpaque = false
    controller.view.backgroundColor = .clear

    let nativeChannel = FlutterMethodChannel(name: "com.plix.plix/native_player", binaryMessenger: controller.binaryMessenger)
    self.channel = nativeChannel

    nativeChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleMethodCall(call: call, result: result, controller: controller)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOrientationOrLayoutChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func handleOrientationOrLayoutChange() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let info = getDuoInfo(controller: controller)
    channel?.invokeMethod("onDuoPostureChanged", arguments: info)
  }

  private func setupAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AVAudioSession error: \(error)")
    }
  }

  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult, controller: FlutterViewController) {
    switch call.method {
    case "play", "pause", "resume", "seekTo", "stop", "setPlaybackSpeed", "setVideoBounds", "setSubtitleTrack", "setAudioTrack":
      result(true)

    case "enterPipMode":
      result(false)

    case "getState":
      result([
        "position": 0,
        "duration": 0,
        "isPlaying": false,
        "buffered": 0
      ])

    case "getDuoInfo":
      result(getDuoInfo(controller: controller))

    case "setDuoPosture":
      if let args = call.arguments as? [String: Any],
         let posture = args["posture"] as? String {
        self.simulatedDuoPosture = posture
        channel?.invokeMethod("onDuoPostureChanged", arguments: getDuoInfo(controller: controller))
        result(true)
      } else {
        self.simulatedDuoPosture = nil
        channel?.invokeMethod("onDuoPostureChanged", arguments: getDuoInfo(controller: controller))
        result(true)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - iPhone Duo Hardware & Posture Support
  private func getDeviceIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else { return identifier }
      return identifier + String(UnicodeScalar(UInt8(value)))
    }
    #if targetEnvironment(simulator)
    if let simId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return simId
    }
    #endif
    return identifier
  }

  private var isIphoneDuo: Bool {
    let id = getDeviceIdentifier()
    return id == "iPhone19,4"
  }

  private func getDuoInfo(controller: FlutterViewController) -> [String: Any] {
    guard isIphoneDuo else {
      return [
        "isDuo": false,
        "posture": "none",
        "angle": 0.0,
        "foldY": 0.0,
        "foldBand": 0.0
      ]
    }

    if let sim = simulatedDuoPosture {
      return [
        "isDuo": true,
        "posture": sim,
        "angle": sim == "tabletop" ? 1.57 : 0.0,
        "foldY": 475.5,
        "foldBand": 40.0
      ]
    }

    let bounds = controller.view.bounds
    let width = bounds.width
    let height = bounds.height
    let isLandscape = width > height

    // Inner display native portrait: 669 x 951 pt
    // Outer display native portrait: 466 x 678 pt
    let isInnerDisplay = max(width, height) > 800 || min(width, height) > 550

    var posture = "closed"
    var angle = 0.0
    var foldCoord = 475.5
    let foldBand = 40.0

    if !isInnerDisplay {
      posture = "closed"
    } else {
      #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        var hasDivision = false
        for region in controller.view.reservedRegions(of: .division) {
          if region.isActive {
            hasDivision = true
            break
          }
        }
        if hasDivision {
          posture = isLandscape ? "book" : "tabletop"
          angle = 1.57
        } else {
          posture = "fullyOpen"
        }
      } else {
        posture = "fullyOpen"
      }
      #else
      // Fallback on size class / aspect ratio
      posture = isLandscape ? "book" : "tabletop"
      angle = 1.57
      #endif
    }

    if isLandscape {
      foldCoord = width / 2.0
    } else {
      foldCoord = height / 2.0
    }

    return [
      "isDuo": true,
      "posture": posture,
      "angle": angle,
      "foldY": foldCoord,
      "foldBand": foldBand
    ]
  }
}
