import Flutter
import UIKit
import AVFoundation
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, AVPictureInPictureControllerDelegate {
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var pipController: AVPictureInPictureController?
  private var videoContainerView: UIView?
  private var channel: FlutterMethodChannel?
  private var timeObserver: Any?
  private var statusObserver: NSKeyValueObservation?
  private var timeControlStatusObserver: NSKeyValueObservation?
  private var isBuffering = false
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
    case "play":
      guard let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString) else {
        result(FlutterError(code: "INVALID_ARGS", message: "url required", details: nil))
        return
      }
      let headers = args["headers"] as? [String: String]
      let positionMs = args["positionMs"] as? Int ?? 0
      playVideo(url: url, headers: headers, positionMs: positionMs, in: controller)
      result(true)

    case "pause":
      player?.pause()
      result(true)

    case "resume":
      player?.play()
      result(true)

    case "seekTo":
      guard let args = call.arguments as? [String: Any],
            let positionMs = args["positionMs"] as? Int else {
        result(false)
        return
      }
      let seekTime = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
      player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
      result(true)

    case "stop":
      stopPlayback()
      result(true)

    case "setPlaybackSpeed":
      if let args = call.arguments as? [String: Any],
         let speed = args["speed"] as? Double {
        player?.rate = Float(speed)
      }
      result(true)

    case "setVideoBounds":
      guard let args = call.arguments as? [String: Any] else {
        result(false)
        return
      }
      let x = args["x"] as? Int ?? 0
      let y = args["y"] as? Int ?? 0
      let width = args["width"] as? Int ?? -1
      let height = args["height"] as? Int ?? -1
      updateVideoBounds(x: x, y: y, width: width, height: height, in: controller)
      result(true)

    case "enterPipMode":
      if let pip = pipController, pip.isPictureInPicturePossible {
        pip.startPictureInPicture()
        result(true)
      } else {
        result(false)
      }

    case "getState":
      let pos = player != nil ? Int(CMTimeGetSeconds(player!.currentTime()) * 1000) : 0
      let dur = player?.currentItem != nil && !CMTimeGetSeconds(player!.currentItem!.duration).isNaN
        ? Int(CMTimeGetSeconds(player!.currentItem!.duration) * 1000) : 0
      let isPlaying = player?.timeControlStatus == .playing
      result([
        "position": pos,
        "duration": dur,
        "isPlaying": isPlaying,
        "buffered": 0
      ])

    case "setSubtitleTrack", "setAudioTrack":
      result(true)

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

  private func playVideo(url: URL, headers: [String: String]?, positionMs: Int, in controller: FlutterViewController) {
    stopPlayback()

    if videoContainerView == nil {
      let container = UIView(frame: controller.view.bounds)
      container.backgroundColor = .black
      container.isUserInteractionEnabled = false
      container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      controller.view.insertSubview(container, at: 0)
      controller.isViewOpaque = false
      controller.view.backgroundColor = .clear
      self.videoContainerView = container
    } else {
      videoContainerView?.isUserInteractionEnabled = false
      videoContainerView?.isHidden = false
      videoContainerView?.frame = controller.view.bounds
    }

    var assetOptions: [String: Any]? = nil
    if let headers = headers, !headers.isEmpty {
      assetOptions = ["AVURLAssetHTTPHeaderFieldsKey": headers]
    }

    let asset = AVURLAsset(url: url, options: assetOptions)
    let playerItem = AVPlayerItem(asset: asset)
    let avPlayer = AVPlayer(playerItem: playerItem)
    avPlayer.actionAtItemEnd = .pause
    self.player = avPlayer

    let layer = AVPlayerLayer(player: avPlayer)
    layer.videoGravity = .resizeAspect
    layer.frame = videoContainerView?.bounds ?? controller.view.bounds
    videoContainerView?.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    videoContainerView?.layer.addSublayer(layer)
    self.playerLayer = layer

    if AVPictureInPictureController.isPictureInPictureSupported() {
      pipController = AVPictureInPictureController(playerLayer: layer)
      pipController?.delegate = self
    }

    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      guard let self = self, let currentItem = self.player?.currentItem else { return }
      let pos = Int(CMTimeGetSeconds(time) * 1000)
      let durSec = CMTimeGetSeconds(currentItem.duration)
      let dur = durSec.isNaN ? 0 : Int(durSec * 1000)
      self.channel?.invokeMethod("onPositionUpdate", arguments: ["position": pos, "duration": dur])
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemDidReachEnd),
      name: .AVPlayerItemDidPlayToEndTime,
      object: playerItem
    )

    statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        if item.status == .readyToPlay {
          let durSec = CMTimeGetSeconds(item.duration)
          let dur = durSec.isNaN ? 0 : Int(durSec * 1000)
          self?.channel?.invokeMethod("onPlayerReady", arguments: ["duration": dur])
        } else if item.status == .failed {
          let errDesc = item.error?.localizedDescription ?? "Playback failed"
          self?.channel?.invokeMethod("onPlayerError", arguments: ["error": errDesc])
        }
      }
    }

    timeControlStatusObserver = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      DispatchQueue.main.async {
        let isPlaying = player.timeControlStatus == .playing
        let isBuff = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        self?.channel?.invokeMethod("onIsPlayingChanged", arguments: ["isPlaying": isPlaying])
        if self?.isBuffering != isBuff {
          self?.isBuffering = isBuff
          self?.channel?.invokeMethod("onBufferingChanged", arguments: ["isBuffering": isBuff])
        }
      }
    }

    if positionMs > 0 {
      let seekTime = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
      avPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    avPlayer.play()
  }

  private func updateVideoBounds(x: Int, y: Int, width: Int, height: Int, in controller: FlutterViewController) {
    guard let container = videoContainerView else { return }
    container.isUserInteractionEnabled = false
    let scale = UIScreen.main.scale
    if width <= 0 || height <= 0 {
      container.frame = controller.view.bounds
    } else {
      let xPts = CGFloat(x) / scale
      let yPts = CGFloat(y) / scale
      let wPts = CGFloat(width) / scale
      let hPts = CGFloat(height) / scale
      container.frame = CGRect(x: xPts, y: yPts, width: wPts, height: hPts)
    }
    playerLayer?.frame = container.bounds
  }

  private func stopPlayback() {
    if let obs = timeObserver {
      player?.removeTimeObserver(obs)
      timeObserver = nil
    }
    statusObserver?.invalidate()
    statusObserver = nil
    timeControlStatusObserver?.invalidate()
    timeControlStatusObserver = nil
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    player?.pause()
    player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    pipController = nil
    videoContainerView?.isHidden = true
  }

  @objc private func playerItemDidReachEnd() {
    channel?.invokeMethod("onPlayerEnded", arguments: nil)
  }

  // MARK: - AVPictureInPictureControllerDelegate
  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    channel?.invokeMethod("onPipModeChanged", arguments: ["isInPip": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    channel?.invokeMethod("onPipModeChanged", arguments: ["isInPip": false])
  }
}
