import AVFoundation
import AVKit
import ExpoModulesCore
import UIKit

@MainActor
internal final class FastVideoView: ExpoView, FastVideoEngineListener, AVPictureInPictureControllerDelegate {
  let onLoadStart = EventDispatcher()
  let onReady = EventDispatcher()
  let onPlaybackStateChange = EventDispatcher()
  let onBuffer = EventDispatcher()
  let onFirstFrame = EventDispatcher()
  let onProgress = EventDispatcher()
  let onMetrics = EventDispatcher()
  let onAdaptiveDecision = EventDispatcher()
  let onTracksChanged = EventDispatcher()
  let onVideoSize = EventDispatcher()
  let onEnd = EventDispatcher()
  let onError = EventDispatcher()
  let onPictureInPictureChange = EventDispatcher()

  override class var layerClass: AnyClass { AVPlayerLayer.self }

  private lazy var engine = FastVideoEngine(listener: self)
  private var source: FastVideoSource?
  private var readyObservation: NSKeyValueObservation?
  private var pictureInPictureController: AVPictureInPictureController?
  private var autoplay = false
  private var paused = true
  private var latencyMode = "balanced"
  private var preferredAudioLanguage: String?
  private var preferredTextLanguage: String?
  private var maxBitrate: Double?
  private var released = false

  private var playerLayer: AVPlayerLayer {
    guard let layer = layer as? AVPlayerLayer else {
      preconditionFailure("FastVideoView must use AVPlayerLayer")
    }
    return layer
  }

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    playerLayer.videoGravity = .resizeAspect
    playerLayer.player = engine.player
    observeReadyForDisplay()
  }

  func setSource(_ value: FastVideoSource?) {
    guard !released else { return }
    source = value
    guard let value, !value.uri.isEmpty else {
      engine.player.replaceCurrentItem(with: nil)
      return
    }
    engine.load(value, autoplay: autoplay || !paused, latencyMode: latencyMode)
    engine.setMaxBitrate(maxBitrate)
  }

  func setAutoplay(_ value: Bool) {
    autoplay = value
    if value {
      paused = false
      engine.play()
    }
  }

  func setPaused(_ value: Bool) {
    paused = value
    value ? engine.pause() : engine.play()
  }

  func setMuted(_ value: Bool) { engine.setMuted(value) }
  func setVolume(_ value: Double) { engine.setVolume(Float(value)) }
  func setMaxBitrate(_ value: Double?) {
    maxBitrate = value?.isFinite == true && (value ?? 0) > 0 ? value : nil
    engine.setMaxBitrate(maxBitrate)
  }
  func setRate(_ value: Double) { engine.setRate(Float(value)) }
  func setRepeat(_ value: Bool) { engine.setRepeat(value) }
  func setAllowsExternalPlayback(_ value: Bool) { engine.setAllowsExternalPlayback(value) }

  func setLatencyMode(_ value: String) {
    let normalized = ["lowLatency", "balanced", "quality", "memorySaver"].contains(value)
      ? value
      : "balanced"
    guard latencyMode != normalized else { return }
    latencyMode = normalized
    if let source { engine.load(source, autoplay: autoplay || !paused, latencyMode: latencyMode) }
  }

  func setProgressInterval(_ value: Double) {
    guard value.isFinite else { return }
    engine.setProgressInterval(Int(value.rounded()).clamped(to: 100...2_000))
  }

  func setContentFit(_ value: String) {
    playerLayer.videoGravity = switch value {
    case "cover": .resizeAspectFill
    case "fill": .resize
    default: .resizeAspect
    }
  }

  func setPreferredAudioLanguage(_ value: String?) {
    preferredAudioLanguage = value
    engine.setPreferredLanguages(audio: preferredAudioLanguage, text: preferredTextLanguage)
  }

  func setPreferredTextLanguage(_ value: String?) {
    preferredTextLanguage = value
    engine.setPreferredLanguages(audio: preferredAudioLanguage, text: preferredTextLanguage)
  }

  func play() { engine.play() }
  func pause() { engine.pause() }
  func replay() { engine.replay() }
  func seekTo(_ milliseconds: Double) { engine.seek(to: milliseconds) }
  func seekBy(_ milliseconds: Double) { engine.seek(by: milliseconds) }
  func goToLive() { engine.goToLive() }
  func selectTrack(type: String, id: String?) { engine.selectTrack(type: type, id: id) }
  func snapshot() -> [String: Any] { engine.snapshot() }

  func enterPictureInPicture() -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return false }
    if pictureInPictureController == nil {
      let controller = AVPictureInPictureController(playerLayer: playerLayer)
      controller.delegate = self
      pictureInPictureController = controller
    }
    guard pictureInPictureController?.isPictureInPicturePossible == true else { return false }
    pictureInPictureController?.startPictureInPicture()
    return true
  }

  func stopPictureInPicture() {
    pictureInPictureController?.stopPictureInPicture()
  }

  func release() {
    guard !released else { return }
    released = true
    readyObservation = nil
    pictureInPictureController?.stopPictureInPicture()
    pictureInPictureController = nil
    playerLayer.player = nil
    engine.release(preserveForBackground: source?.mediaSession == true)
  }

  private func observeReadyForDisplay() {
    readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
      guard layer.isReadyForDisplay else { return }
      Task { @MainActor in
        guard let self else { return }
        self.engine.markFirstFrame()
        let snapshot = self.engine.snapshot()
        self.onFirstFrame([
          "timestampMs": Date().timeIntervalSince1970 * 1_000,
          "timeToFirstFrameMs": snapshot["timeToFirstFrameMs"] ?? -1,
          "startupPath": snapshot["startupPath"] ?? "cold"
        ])
      }
    }
  }

  func emitLoadStart(uri: String) { onLoadStart(["uri": uri]) }
  func emitReady(durationMs: Double, isLive: Bool) {
    onReady(["durationMs": durationMs, "isLive": isLive])
  }
  func emitState(_ state: String) { onPlaybackStateChange(["state": state]) }
  func emitBuffering(_ buffering: Bool) { onBuffer(["buffering": buffering]) }
  func emitProgress(_ payload: [String: Any]) { onProgress(payload) }
  func emitMetrics(_ payload: [String: Any]) { onMetrics(payload) }
  func emitAdaptiveDecision(_ payload: [String: Any]) { onAdaptiveDecision(payload) }
  func emitTracksChanged(_ payload: [String: Any]) { onTracksChanged(payload) }
  func emitVideoSize(width: Int, height: Int, pixelRatio: Double) {
    onVideoSize(["width": width, "height": height, "pixelRatio": pixelRatio])
  }
  func emitEnded() { onEnd([:]) }
  func emitError(code: String, message: String, nativeCode: String?) {
    var payload: [String: Any] = ["code": code, "message": message]
    if let nativeCode { payload["nativeCode"] = nativeCode }
    onError(payload)
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    onPictureInPictureChange(["active": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    onPictureInPictureChange(["active": false])
  }

  deinit {
    readyObservation = nil
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
