import AVFoundation
import Foundation

internal final class FastVideoAppleRuntime {
  static let shared = FastVideoAppleRuntime()

  private let lock = NSLock()
  private var players: [AVPlayer] = []
  private var maxPooledPlayers = 2
  private var acquiredPlayers = 0
  private var recycledPlayers = 0

  private init() {}

  func acquirePlayer() -> AVPlayer {
    lock.lock()
    let player = players.popLast() ?? AVPlayer()
    acquiredPlayers += 1
    lock.unlock()
    resetForAcquisition(player)
    return player
  }

  func recycle(_ player: AVPlayer) {
    resetForPool(player)
    lock.lock()
    recycledPlayers += 1
    if players.count < maxPooledPlayers {
      players.append(player)
      lock.unlock()
      return
    }
    lock.unlock()
  }

  func configure(maxPooledPlayers value: Int?) -> [String: Any] {
    lock.lock()
    maxPooledPlayers = min(max(value ?? maxPooledPlayers, 0), 6)
    let excess = max(0, players.count - maxPooledPlayers)
    let discarded = excess > 0 ? Array(players.prefix(excess)) : []
    if excess > 0 { players.removeFirst(excess) }
    let result = statsLocked()
    lock.unlock()
    discarded.forEach(resetForPool)
    return result
  }

  func stats() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return statsLocked()
  }

  func clearTransientState() {
    lock.lock()
    let discarded = players
    players.removeAll(keepingCapacity: false)
    lock.unlock()
    discarded.forEach(resetForPool)
    FastVideoPreloader.shared.clear()
  }

  private func statsLocked() -> [String: Any] {
    [
      "pooledPlayers": players.count,
      "maxPooledPlayers": maxPooledPlayers,
      "acquiredPlayers": acquiredPlayers,
      "recycledPlayers": recycledPlayers,
      "warmedAssets": FastVideoPreloader.shared.count
    ]
  }

  private func resetForAcquisition(_ player: AVPlayer) {
    player.pause()
    player.replaceCurrentItem(with: nil)
    player.rate = 0
    player.defaultRate = 1
    player.volume = 1
    player.isMuted = false
    player.actionAtItemEnd = .pause
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    player.automaticallyWaitsToMinimizeStalling = true
  }

  private func resetForPool(_ player: AVPlayer) {
    player.pause()
    player.cancelPendingPrerolls()
    player.replaceCurrentItem(with: nil)
    player.rate = 0
    player.defaultRate = 1
    player.volume = 1
    player.isMuted = false
    player.actionAtItemEnd = .pause
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    player.automaticallyWaitsToMinimizeStalling = true
  }
}
