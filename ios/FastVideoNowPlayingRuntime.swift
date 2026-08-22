import AVFoundation
import Foundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

@MainActor
internal final class FastVideoNowPlayingRuntime {
  static let shared = FastVideoNowPlayingRuntime()

  private weak var engine: FastVideoEngine?
  private var backgroundPlayer: AVPlayer?
  private var commandsInstalled = false
  private var timer: Timer?

  private init() {}

  func attach(engine: FastVideoEngine, source: FastVideoSource) {
    if let backgroundPlayer, backgroundPlayer !== engine.player {
      backgroundPlayer.pause()
      backgroundPlayer.replaceCurrentItem(with: nil)
      self.backgroundPlayer = nil
      FastVideoAdaptiveRuntime.shared.releasedPlayer()
    }
    self.engine = engine
    #if os(iOS)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
      try session.setActive(true)
    } catch {}
    #endif
    installCommandsIfNeeded()
    updateMetadata(source: source)
    startTimerIfNeeded()
  }

  func detach(engine: FastVideoEngine, keepAlive: Bool = false) -> Bool {
    guard self.engine === engine else { return false }
    if keepAlive && engine.player.timeControlStatus == .playing {
      if backgroundPlayer !== engine.player { FastVideoAdaptiveRuntime.shared.acquiredPlayer() }
      backgroundPlayer = engine.player
      self.engine = nil
      startTimerIfNeeded()
      return true
    }
    self.engine = nil
    if backgroundPlayer == nil { clearNowPlaying() }
    return false
  }

  func stopBackgroundPlayback() {
    backgroundPlayer?.pause()
    backgroundPlayer?.replaceCurrentItem(with: nil)
    if backgroundPlayer != nil { FastVideoAdaptiveRuntime.shared.releasedPlayer() }
    backgroundPlayer = nil
    if engine == nil { clearNowPlaying() }
  }

  func updatePlayback(positionSeconds: Double, durationSeconds: Double, rate: Float) {
    #if canImport(MediaPlayer)
    guard engine != nil || backgroundPlayer != nil else { return }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, positionSeconds)
    if durationSeconds.isFinite && durationSeconds > 0 { info[MPMediaItemPropertyPlaybackDuration] = durationSeconds }
    info[MPNowPlayingInfoPropertyPlaybackRate] = rate
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    #endif
  }

  private func updateMetadata(source: FastVideoSource) {
    #if canImport(MediaPlayer)
    var info: [String: Any] = [:]
    if let title = source.metadata?.title { info[MPMediaItemPropertyTitle] = title }
    if let artist = source.metadata?.artist { info[MPMediaItemPropertyArtist] = artist }
    if let album = source.metadata?.albumTitle { info[MPMediaItemPropertyAlbumTitle] = album }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    #endif
  }

  private func activePlayer() -> AVPlayer? { engine?.player ?? backgroundPlayer }

  private func startTimerIfNeeded() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let player = self.activePlayer() else {
          self?.timer?.invalidate(); self?.timer = nil; return
        }
        let duration = player.currentItem?.duration.seconds ?? 0
        self.updatePlayback(positionSeconds: player.currentTime().seconds, durationSeconds: duration.isFinite ? duration : 0, rate: player.rate)
      }
    }
  }

  private func installCommandsIfNeeded() {
    #if canImport(MediaPlayer)
    guard !commandsInstalled else { return }
    commandsInstalled = true
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.activePlayer()?.play() }; return .success }
    center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.activePlayer()?.pause() }; return .success }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let player = self?.activePlayer() else { return }
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
      }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      Task { @MainActor in self?.activePlayer()?.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600)) }
      return .success
    }
    #endif
  }

  private func clearNowPlaying() {
    timer?.invalidate(); timer = nil
    #if canImport(MediaPlayer)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    #endif
  }
}
