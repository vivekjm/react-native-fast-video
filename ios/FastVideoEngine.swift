import AVFoundation
import Foundation

@MainActor
internal protocol FastVideoEngineListener: AnyObject {
  func emitLoadStart(uri: String)
  func emitReady(durationMs: Double, isLive: Bool)
  func emitState(_ state: String)
  func emitBuffering(_ buffering: Bool)
  func emitProgress(_ payload: [String: Any])
  func emitMetrics(_ payload: [String: Any])
  func emitAdaptiveDecision(_ payload: [String: Any])
  func emitTracksChanged(_ payload: [String: Any])
  func emitVideoSize(width: Int, height: Int, pixelRatio: Double)
  func emitEnded()
  func emitError(code: String, message: String, nativeCode: String?)
}

@MainActor
internal final class FastVideoEngine: NSObject {
  let player: AVPlayer

  weak var listener: FastVideoEngineListener?
  private let core = RNFVFastCoreBridge()
  private var source: FastVideoSource?
  private var baseSource: FastVideoSource?
  private var candidateUris: [String] = []
  private var candidateIndex = 0
  private var retryAttempt = 0
  private var autoplayRequested = false
  private var activeLatencyMode = "balanced"
  private var fairPlayLoader: FairPlayResourceLoader?
  private var timeObserver: Any?
  private var playerObservations: [NSKeyValueObservation] = []
  private var itemObservations: [NSKeyValueObservation] = []
  private var endObserver: NSObjectProtocol?
  private var accessLogObserver: NSObjectProtocol?
  private var released = false
  private var firstFrameRendered = false
  private var buffering = false
  private var selectedVolume: Float = 1
  private var selectedRate: Float = 1
  private var muted = false
  private var startupPath = "cold"
  private var configuredMaxBitrate: Double?
  private var latestBandwidthEstimate: Double = 0
  private var candidateLoadStartedAt = 0.0
  private var currentVideoWidth = 0
  private var currentVideoHeight = 0
  private var adaptiveDecision: [String: Any] = [:]

  init(listener: FastVideoEngineListener) {
    self.player = FastVideoAppleRuntime.shared.acquirePlayer()
    self.listener = listener
    super.init()
    player.automaticallyWaitsToMinimizeStalling = true
    FastVideoAdaptiveRuntime.shared.acquiredPlayer()
    observePlayer()
    installTimeObserver()
  }

  func load(_ source: FastVideoSource, autoplay: Bool, latencyMode: String) {
    baseSource = source
    candidateUris = ([source.uri] + source.fallbackUris).filter { !$0.isEmpty }
    candidateUris = Array(NSOrderedSet(array: candidateUris)) as? [String] ?? candidateUris
    candidateUris = FastVideoCdnRuntime.shared.rank(candidateUris)
    candidateIndex = 0
    retryAttempt = 0
    autoplayRequested = autoplay
    activeLatencyMode = latencyMode
    var candidate = source
    candidate.uri = candidateUris.first ?? source.uri
    loadCandidate(candidate, autoplay: autoplay, latencyMode: latencyMode)
  }

  private func loadCandidate(_ candidate: FastVideoSource, autoplay: Bool, latencyMode: String) {
    guard !released else { return }
    self.source = candidate
    firstFrameRendered = false
    candidateLoadStartedAt = ProcessInfo.processInfo.systemUptime
    listener?.emitLoadStart(uri: candidate.uri)
    core.event(1, valueA: candidate.isLive ? 1 : 0, valueB: 0, valueC: 0)

    let resolvedURL: URL?
    if let offlineId = candidate.offlineId, !offlineId.isEmpty {
      resolvedURL = FastVideoOfflineRuntime.shared.playbackURL(id: offlineId)
      startupPath = "offline"
      if resolvedURL == nil {
        fail(code: "E_OFFLINE_NOT_READY", message: "Offline download is not completed: \(offlineId)", nativeCode: nil)
        return
      }
    } else {
      resolvedURL = URL(string: candidate.uri)
    }
    guard let url = resolvedURL else {
      retryOrFail(message: "Invalid video URI", nativeCode: nil)
      return
    }

    clearItemObservers()
    let asset: AVURLAsset
    if let warmed = FastVideoPreloader.shared.asset(for: candidate) {
      asset = warmed
      startupPath = "asset-warmed"
    } else {
      startupPath = "cold"
      let assetOptions: [String: Any] = candidate.headers.isEmpty
        ? [:]
        : ["AVURLAssetHTTPHeaderFieldsKey": candidate.headers]
      asset = AVURLAsset(url: url, options: assetOptions)
    }

    if let drm = candidate.drm, drm.type.lowercased() == "fairplay" {
      let loader = FairPlayResourceLoader(configuration: drm)
      fairPlayLoader = loader
      asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "com.vivekjm.fastvideo.fairplay"))
    } else {
      fairPlayLoader = nil
    }

    let item = AVPlayerItem(asset: asset)
    applyLatencyPolicy(item: item, source: candidate, mode: latencyMode)
    observe(item: item)
    player.replaceCurrentItem(with: item)
    if candidate.mediaSession {
      FastVideoNowPlayingRuntime.shared.attach(engine: self, source: candidate)
    }
    else { _ = FastVideoNowPlayingRuntime.shared.detach(engine: self) }
    applyAdaptiveDecision()

    if let start = candidate.startPositionMs, start.isFinite, start >= 0 {
      player.seek(to: CMTime(milliseconds: start))
    }
    if autoplay { play() }
  }

  private func retryOrFail(message: String, nativeCode: String?) {
    let responseMs = max(0, (ProcessInfo.processInfo.systemUptime - candidateLoadStartedAt) * 1_000)
    if let uri = source?.uri { FastVideoCdnRuntime.shared.recordFailure(uri: uri, responseMs: responseMs) }
    guard let base = baseSource, !released else {
      fail(code: "E_PLAYBACK", message: message, nativeCode: nativeCode)
      return
    }
    let maxRetries = min(max(base.maxRetryAttempts, 0), 8)
    if retryAttempt < maxRetries {
      let delayMs = min(max(base.retryBackoffMs, 50), 10_000) * pow(2, Double(min(retryAttempt, 4)))
      retryAttempt += 1
      scheduleRetry(afterMs: delayMs, base: base)
      return
    }
    if candidateIndex + 1 < candidateUris.count {
      candidateIndex += 1
      retryAttempt = 0
      scheduleRetry(afterMs: min(max(base.retryBackoffMs, 50), 10_000), base: base)
      return
    }
    fail(code: "E_PLAYBACK", message: message, nativeCode: nativeCode)
  }

  private func scheduleRetry(afterMs delayMs: Double, base: FastVideoSource) {
    let index = candidateIndex
    DispatchQueue.main.asyncAfter(deadline: .now() + delayMs / 1_000) { [weak self] in
      guard let self, !self.released, index < self.candidateUris.count else { return }
      var candidate = base
      candidate.uri = self.candidateUris[index]
      self.loadCandidate(candidate, autoplay: self.autoplayRequested, latencyMode: self.activeLatencyMode)
    }
  }

  func markFirstFrame() {
    guard !firstFrameRendered, !released else { return }
    firstFrameRendered = true
    core.event(7, valueA: 0, valueB: 0, valueC: 0)
    let snapshot = core.snapshot() as? [String: Any] ?? [:]
    let ttff = (snapshot["timeToFirstFrameMs"] as? NSNumber)?.doubleValue ?? -1
    let responseMs = max(0, (ProcessInfo.processInfo.systemUptime - candidateLoadStartedAt) * 1_000)
    if let uri = source?.uri { FastVideoCdnRuntime.shared.recordFirstFrame(uri: uri, ttffMs: ttff, responseMs: responseMs) }
  }

  func play() {
    guard !released else { return }
    core.event(3, valueA: 0, valueB: 0, valueC: 0)
    player.playImmediately(atRate: selectedRate)
  }

  func pause() {
    guard !released else { return }
    player.pause()
    core.event(4, valueA: 0, valueB: 0, valueC: 0)
  }

  func replay() {
    seek(to: 0)
    play()
  }

  func seek(to milliseconds: Double) {
    guard milliseconds.isFinite, !released else { return }
    core.event(8, valueA: 0, valueB: 0, valueC: 0)
    let target = CMTime(milliseconds: max(0, milliseconds))
    player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      guard let self else { return }
      self.core.event(9, valueA: 0, valueB: 0, valueC: 0)
    }
  }

  func seek(by milliseconds: Double) {
    let current = player.currentTime().finiteSeconds * 1000
    seek(to: current + milliseconds)
  }

  func goToLive() {
    guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
    core.event(8, valueA: 0, valueB: 0, valueC: 0)
    player.seek(to: CMTimeRangeGetEnd(range), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      guard let self else { return }
      self.core.event(9, valueA: 0, valueB: 0, valueC: 0)
      self.play()
    }
  }

  func setRate(_ value: Float) {
    guard value.isFinite else { return }
    let rate = min(max(value, 0.25), 4)
    selectedRate = rate
    player.defaultRate = rate
    if player.timeControlStatus == .playing { player.rate = rate }
  }

  func setVolume(_ value: Float) {
    guard value.isFinite else { return }
    selectedVolume = min(max(value, 0), 1)
    player.volume = muted ? 0 : selectedVolume
  }

  func setMuted(_ value: Bool) {
    muted = value
    player.isMuted = value
    player.volume = value ? 0 : selectedVolume
  }

  func setRepeat(_ value: Bool) {
    player.actionAtItemEnd = value ? .none : .pause
  }

  func setAllowsExternalPlayback(_ value: Bool) {
    player.allowsExternalPlayback = value
  }

  func setMaxBitrate(_ value: Double?) {
    configuredMaxBitrate = value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    applyAdaptiveDecision()
  }

  func setProgressInterval(_ milliseconds: Int) {
    core.setProgressIntervalMs(milliseconds)
  }

  func setPreferredLanguages(audio: String?, text: String?) {
    guard let item = player.currentItem else { return }
    if let audio, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
      let option = group.options.first { $0.locale?.identifier == audio || $0.extendedLanguageTag == audio }
      item.select(option, in: group)
    }
    if let text, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
      let option = group.options.first { $0.locale?.identifier == text || $0.extendedLanguageTag == text }
      item.select(option, in: group)
    }
    emitTracks()
  }

  func selectTrack(type: String, id: String?) {
    guard let item = player.currentItem else { return }
    let characteristic: AVMediaCharacteristic
    switch type.lowercased() {
    case "audio": characteristic = .audible
    case "text", "subtitle": characteristic = .legible
    default: return
    }
    guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return }
    guard let id else {
      item.select(nil, in: group)
      emitTracks()
      return
    }
    let index = id.split(separator: ":").last.flatMap { Int($0) }
    if let index, group.options.indices.contains(index) {
      item.select(group.options[index], in: group)
      emitTracks()
    }
  }

  func snapshot() -> [String: Any] {
    var value = core.snapshot() as? [String: Any] ?? [:]
    value["startupPath"] = startupPath
    value["adaptiveDecision"] = adaptiveDecision
    value["activePlayers"] = FastVideoAdaptiveRuntime.shared.stats()["activePlayers"] ?? 1
    value["cdn"] = source.map { FastVideoCdnRuntime.shared.diagnostics(uri: $0.uri) } ?? [:]
    return value
  }

  func release(preserveForBackground: Bool = false) {
    guard !released else { return }
    released = true
    if !preserveForBackground { player.pause() }
    clearItemObservers()
    playerObservations.removeAll()
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    let preserved = FastVideoNowPlayingRuntime.shared.detach(engine: self, keepAlive: preserveForBackground && source?.mediaSession == true)
    core.releaseSession()
    if !preserved { FastVideoAppleRuntime.shared.recycle(player) }
    FastVideoAdaptiveRuntime.shared.releasedPlayer()
  }

  private func observePlayer() {
    playerObservations.append(
      player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
        Task { @MainActor in self?.handleTimeControlStatus(player.timeControlStatus) }
      }
    )
  }

  private func observe(item: AVPlayerItem) {
    itemObservations.append(
      item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
        Task { @MainActor in self?.handleStatus(item) }
      }
    )
    itemObservations.append(
      item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.updateBufferingState() }
      }
    )
    itemObservations.append(
      item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
        Task { @MainActor in
          let size = item.presentationSize
          self?.currentVideoWidth = Int(size.width)
          self?.currentVideoHeight = Int(size.height)
          self?.applyAdaptiveDecision()
          self?.listener?.emitVideoSize(width: Int(size.width), height: Int(size.height), pixelRatio: 1)
        }
      }
    )

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.player.actionAtItemEnd == .none {
          self.player.seek(to: .zero)
          self.player.play()
        } else {
          self.core.event(14, valueA: 0, valueB: 0, valueC: 0)
          self.listener?.emitState("ended")
          self.listener?.emitEnded()
        }
      }
    }

    accessLogObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemNewAccessLogEntry,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.readAccessLog() }
    }
  }

  private func handleStatus(_ item: AVPlayerItem) {
    switch item.status {
    case .readyToPlay:
      core.event(2, valueA: 0, valueB: 0, valueC: 0)
      let durationMs = item.duration.finiteSeconds * 1000
      let live = isLive(item)
      listener?.emitReady(durationMs: durationMs, isLive: live)
      listener?.emitState(player.timeControlStatus == .playing ? "playing" : "ready")
      emitTracks()
    case .failed:
      retryOrFail(
        message: item.error?.localizedDescription ?? "AVPlayerItem failed",
        nativeCode: (item.error as NSError?)?.domain
      )
    default:
      break
    }
  }

  private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
    switch status {
    case .playing:
      setBuffering(false)
      core.event(3, valueA: 0, valueB: 0, valueC: 0)
      listener?.emitState("playing")
    case .waitingToPlayAtSpecifiedRate:
      setBuffering(true)
      listener?.emitState("buffering")
    case .paused:
      setBuffering(false)
      listener?.emitState(player.currentItem == nil ? "idle" : "paused")
    @unknown default:
      listener?.emitState("idle")
    }
  }

  private func updateBufferingState() {
    setBuffering(player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
  }

  private func setBuffering(_ value: Bool) {
    guard buffering != value else { return }
    buffering = value
    core.event(value ? 5 : 6, valueA: 0, valueB: 0, valueC: 0)
    listener?.emitBuffering(value)
  }

  private func installTimeObserver() {
    let interval = CMTime(value: 1, timescale: 20)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.updateProgress() }
    }
  }

  private func updateProgress() {
    guard let item = player.currentItem, !released else { return }
    let position = player.currentTime().finiteSeconds * 1000
    let duration = item.duration.finiteSeconds * 1000
    let buffered = item.loadedTimeRanges
      .map(\.timeRangeValue)
      .map { CMTimeRangeGetEnd($0) }
      .map(\.finiteSeconds)
      .max() ?? 0
    let bufferedMs = buffered * 1000
    core.event(12, valueA: position, valueB: duration, valueC: bufferedMs)

    var liveOffset: Double?
    if isLive(item), let range = item.seekableTimeRanges.last?.timeRangeValue {
      let edge = CMTimeRangeGetEnd(range).finiteSeconds * 1000
      let value = max(0, edge - position)
      liveOffset = value
      core.event(13, valueA: value, valueB: 0, valueC: 0)
    }

    guard core.shouldEmitProgress() else { return }
    var payload: [String: Any] = [
      "positionMs": position,
      "durationMs": duration,
      "bufferedPositionMs": bufferedMs,
      "isLive": isLive(item),
      "isPlaying": player.timeControlStatus == .playing,
      "playbackState": stateName()
    ]
    if let liveOffset { payload["liveOffsetMs"] = liveOffset }
    FastVideoNowPlayingRuntime.shared.updatePlayback(
      positionSeconds: position / 1000,
      durationSeconds: duration / 1000,
      rate: player.timeControlStatus == .playing ? selectedRate : 0
    )
    listener?.emitProgress(payload)
    listener?.emitMetrics(snapshot())
  }

  private func readAccessLog() {
    guard let event = player.currentItem?.accessLog()?.events.last else { return }
    let bitrate = event.observedBitrate.isFinite ? max(0, event.observedBitrate) : 0
    let bytes = event.numberOfBytesTransferred > 0 ? event.numberOfBytesTransferred : 0
    core.event(11, valueA: Double(bytes), valueB: bitrate, valueC: 0)
    latestBandwidthEstimate = bitrate

    let dropped = max(0, event.numberOfDroppedVideoFrames)
    if dropped > 0 {
      // AVPlayer access logs expose dropped frames but not a reliable rendered-frame
      // total. Preserve the dropped count without inventing a denominator.
      core.event(10, valueA: 0, valueB: Double(dropped), valueC: 0)
    }
    applyAdaptiveDecision()
  }

  private func applyAdaptiveDecision() {
    guard !released, let item = player.currentItem else { return }
    let metrics = core.snapshot() as? [String: Any] ?? [:]
    let rebuffer = (metrics["rebufferRatio"] as? NSNumber)?.doubleValue ?? 0
    let dropped = (metrics["droppedFrameRatio"] as? NSNumber)?.doubleValue ?? 0
    let predictedBandwidth = (metrics["predictedBandwidthBps"] as? NSNumber)?.doubleValue ?? 0
    let bandwidthConfidence = (metrics["bandwidthConfidence"] as? NSNumber)?.doubleValue ?? 0
    let decision = FastVideoAdaptiveRuntime.shared.decision(
      core: core,
      bandwidth: predictedBandwidth > 0 && bandwidthConfidence >= 0.35 ? predictedBandwidth : latestBandwidthEstimate,
      rebufferRatio: rebuffer,
      droppedFrameRatio: dropped,
      width: currentVideoWidth,
      height: currentVideoHeight
    )
    if decision.isEmpty {
      item.preferredPeakBitRate = configuredMaxBitrate ?? 0
      item.preferredMaximumResolution = .zero
      adaptiveDecision = [:]
      return
    }
    let adaptiveBitrate = (decision["maxBitrateBps"] as? NSNumber)?.doubleValue ?? 0
    let resolved: Double
    if let configuredMaxBitrate, configuredMaxBitrate > 0, adaptiveBitrate > 0 {
      resolved = min(configuredMaxBitrate, adaptiveBitrate)
    } else {
      resolved = configuredMaxBitrate ?? max(0, adaptiveBitrate)
    }
    item.preferredPeakBitRate = resolved
    let maxWidth = (decision["maxWidth"] as? NSNumber)?.doubleValue ?? 0
    let maxHeight = (decision["maxHeight"] as? NSNumber)?.doubleValue ?? 0
    item.preferredMaximumResolution = maxWidth > 0 && maxHeight > 0 ? CGSize(width: maxWidth, height: maxHeight) : .zero
    if let bufferMs = (decision["preferredForwardBufferMs"] as? NSNumber)?.doubleValue, bufferMs > 0 {
      let adaptiveSeconds = bufferMs / 1000
      switch activeLatencyMode {
      case "lowLatency": item.preferredForwardBufferDuration = min(2, adaptiveSeconds)
      case "quality": item.preferredForwardBufferDuration = max(15, adaptiveSeconds)
      case "memorySaver": item.preferredForwardBufferDuration = min(5, adaptiveSeconds)
      default: item.preferredForwardBufferDuration = adaptiveSeconds
      }
    }
    var next = decision
    next["resolvedMaxBitrateBps"] = resolved
    next["predictedBandwidthBps"] = predictedBandwidth
    next["bandwidthConfidence"] = bandwidthConfidence
    if !NSDictionary(dictionary: next).isEqual(NSDictionary(dictionary: adaptiveDecision)) {
      adaptiveDecision = next
      listener?.emitAdaptiveDecision(next)
    }
  }

  private func emitTracks() {
    guard let item = player.currentItem else { return }
    let audio = trackList(item: item, characteristic: .audible, prefix: "audio")
    let text = trackList(item: item, characteristic: .legible, prefix: "text")
    listener?.emitTracksChanged(["video": [], "audio": audio, "text": text])
  }

  private func trackList(
    item: AVPlayerItem,
    characteristic: AVMediaCharacteristic,
    prefix: String
  ) -> [[String: Any]] {
    guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return [] }
    let selected = item.currentMediaSelection.selectedMediaOption(in: group)
    return group.options.enumerated().map { index, option in
      var value: [String: Any] = [
        "id": "\(prefix):\(index)",
        "label": option.displayName,
        "selected": option == selected,
        "supported": true
      ]
      if let language = option.extendedLanguageTag ?? option.locale?.identifier {
        value["language"] = language
      }
      return value
    }
  }

  private func applyLatencyPolicy(item: AVPlayerItem, source: FastVideoSource, mode: String) {
    switch mode {
    case "lowLatency":
      item.preferredForwardBufferDuration = 1
      item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
      player.automaticallyWaitsToMinimizeStalling = false
    case "quality":
      item.preferredForwardBufferDuration = 30
      player.automaticallyWaitsToMinimizeStalling = true
    case "memorySaver":
      item.preferredForwardBufferDuration = 3
      player.automaticallyWaitsToMinimizeStalling = true
    default:
      item.preferredForwardBufferDuration = 10
      player.automaticallyWaitsToMinimizeStalling = true
    }
    _ = source.targetLiveOffsetMs // retained for telemetry and future OS-specific tuning
  }

  private func isLive(_ item: AVPlayerItem) -> Bool {
    source?.isLive == true || item.duration.isIndefinite || !item.seekableTimeRanges.isEmpty && item.duration.finiteSeconds == 0
  }

  private func stateName() -> String {
    if player.currentItem == nil { return "idle" }
    switch player.timeControlStatus {
    case .playing: return "playing"
    case .waitingToPlayAtSpecifiedRate: return "buffering"
    case .paused: return "paused"
    @unknown default: return "idle"
    }
  }

  private func fail(code: String, message: String, nativeCode: String?) {
    core.event(15, valueA: 0, valueB: 0, valueC: 0)
    listener?.emitError(code: code, message: message, nativeCode: nativeCode)
  }

  private func clearItemObservers() {
    itemObservations.removeAll()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    if let accessLogObserver { NotificationCenter.default.removeObserver(accessLogObserver) }
    endObserver = nil
    accessLogObserver = nil
  }
}

private extension CMTime {
  init(milliseconds: Double) {
    self.init(seconds: milliseconds / 1000, preferredTimescale: 1_000_000)
  }

  var finiteSeconds: Double {
    let value = seconds
    return value.isFinite && value >= 0 ? value : 0
  }
}
