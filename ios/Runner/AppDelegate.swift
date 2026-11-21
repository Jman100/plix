import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var channel: FlutterMethodChannel?
  private weak var flutterController: FlutterViewController?
  private var pluginsRegistered = false
  private var geometryObservation: NSKeyValueObservation?
  private var simulatedDuoPosture: String?
  private var lastHingeStatusRaw: Int? // 0: closed, 1: partiallyOpen, 2: fullyOpen
  private var lastHingeAngle: Double = 0.0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    setupAudioSession()

    if let controller = window?.rootViewController as? FlutterViewController {
      configure(controller: controller)
    }

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOrientationOrLayoutChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func configure(controller: FlutterViewController) {
    if flutterController === controller {
      return
    }
    flutterController = controller

    if !pluginsRegistered {
      GeneratedPluginRegistrant.register(with: controller)
      pluginsRegistered = true
    }

    controller.isViewOpaque = false
    controller.view.backgroundColor = .clear

    let nativeChannel = FlutterMethodChannel(name: "com.plix.plix/native_player", binaryMessenger: controller.binaryMessenger)
    self.channel = nativeChannel

    nativeChannel.setMethodCallHandler { [weak self, weak controller] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self, let controller = controller else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handleMethodCall(call: call, result: result, controller: controller)
    }

    if let scene = controller.view.window?.windowScene ?? window?.windowScene {
      observeGeometry(of: scene)
    }

    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *), UIDevice.current.userInterfaceIdiom == .phone {
      let hingeInteraction = UIHingeInteraction { [weak self] _, update in
        Task { @MainActor in
          guard let self = self else { return }
          if let hinge = update.hinge {
            switch hinge.status {
            case .closed:
              self.lastHingeStatusRaw = 0
            case .partiallyOpen:
              self.lastHingeStatusRaw = 1
            case .fullyOpen:
              self.lastHingeStatusRaw = 2
            @unknown default:
              self.lastHingeStatusRaw = nil
            }
            self.lastHingeAngle = Double(hinge.angle)
          } else {
            self.lastHingeStatusRaw = nil
            self.lastHingeAngle = 0.0
          }
          self.handleOrientationOrLayoutChange()
        }
      }
      controller.view.addInteraction(hingeInteraction)
    }
    #endif
  }

  func observeGeometry(of windowScene: UIWindowScene) {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return }
    if #available(iOS 16.0, *) {
      geometryObservation = windowScene.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
        DispatchQueue.main.async {
          self?.handleOrientationOrLayoutChange()
        }
      }
    }
  }

  @objc private func handleOrientationOrLayoutChange() {
    guard let controller = flutterController ?? (window?.rootViewController as? FlutterViewController) else { return }
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
      return identifier + String(UnicodeScalar(UInt8(bitPattern: value)))
    }
    #if targetEnvironment(simulator)
    if let simId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
      return simId
    }
    #endif
    return identifier
  }

  private func isIphoneDuo(controller: FlutterViewController) -> Bool {
    guard UIDevice.current.userInterfaceIdiom == .phone else {
      return false
    }
    let id = getDeviceIdentifier()
    if id == "iPhone19,4" || id.lowercased().contains("duo") {
      return true
    }
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *) {
      if !controller.view.reservedRegions(kind: .division).isEmpty {
        return true
      }
    }
    #endif
    return false
  }

  private func getDuoInfo(controller: FlutterViewController) -> [String: Any] {
    let isDuoDevice = isIphoneDuo(controller: controller)
    guard isDuoDevice else {
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
    let width = Double(bounds.width)
    let height = Double(bounds.height)

    let windowScene = controller.view.window?.windowScene ?? (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let isLandscape: Bool
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *), let effectiveOrientation = windowScene?.effectiveGeometry.interfaceOrientation {
      isLandscape = effectiveOrientation.isLandscape
    } else if let orientation = windowScene?.interfaceOrientation {
      isLandscape = orientation.isLandscape
    } else {
      isLandscape = width > height
    }
    #else
    if let orientation = windowScene?.interfaceOrientation {
      isLandscape = orientation.isLandscape
    } else {
      isLandscape = width > height
    }
    #endif

    // Inner display native portrait: 669 x 951 pt
    // Outer display native portrait: 466 x 678 pt
    let isInnerDisplay = max(width, height) > 800 || min(width, height) > 550

    var posture = "closed"
    var angle = 0.0
    var foldCoord = isLandscape ? (width / 2.0) : (height / 2.0)
    var foldBand = 40.0

    if !isInnerDisplay {
      posture = "closed"
      angle = 0.0
    } else {
      #if canImport(UIKit, _version: 9127.0.85)
      if #available(iOS 27.1, *) {
        var activeDivisionFrame: CGRect?
        for region in controller.view.reservedRegions(kind: .division) {
          if region.isActive {
            activeDivisionFrame = region.frame
            break
          }
        }

        if let frame = activeDivisionFrame {
          foldBand = isLandscape ? Double(frame.width) : Double(frame.height)
          foldCoord = isLandscape ? Double(frame.midX) : Double(frame.midY)
        } else {
          foldCoord = isLandscape ? (width / 2.0) : 475.5
          foldBand = 40.0
        }

        if let statusRaw = lastHingeStatusRaw {
          switch statusRaw {
          case 0: // closed
            posture = "closed"
            angle = 0.0
          case 2: // fullyOpen
            posture = "fullyOpen"
            angle = lastHingeAngle > 0 ? lastHingeAngle : 3.14159
          case 1: // partiallyOpen
            posture = isLandscape ? "book" : "tabletop"
            angle = lastHingeAngle > 0 ? lastHingeAngle : 1.57
          default:
            posture = "fullyOpen"
          }
        } else if activeDivisionFrame != nil {
          posture = isLandscape ? "book" : "tabletop"
          angle = 1.57
        } else {
          posture = "fullyOpen"
        }
      } else {
        posture = "fullyOpen"
      }
      #else
      posture = "fullyOpen"
      #endif
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

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

    if window == nil {
      let storyboard = UIStoryboard(name: "Main", bundle: nil)
      let newWindow = UIWindow(windowScene: windowScene)
      newWindow.rootViewController = storyboard.instantiateInitialViewController()
      window = newWindow
      newWindow.makeKeyAndVisible()
    }

    if let sceneWindow = window {
      appDelegate.window = sceneWindow
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      appDelegate.configure(controller: controller)
    }

    appDelegate.observeGeometry(of: windowScene)
  }
}
