import AVFoundation

@MainActor
internal final class FastVideoAppleRuntime {
  static let shared = FastVideoAppleRuntime()

  private var pooledPlayers: [AVPlayer] = []
  private var maxPooledPlayers = 2

  private init() {}

  func configure(maxPooledPlayers: Int?) -> [String: Any] {
    if let maxPooledPlayers {
      self.maxPooledPlayers = min(max(maxPooledPlayers, 0), 6)
    }
    while pooledPlayers.count > self.maxPooledPlayers {
      pooledPlayers.removeLast()
    }
    return stats()
  }

  func acquirePlayer() -> AVPlayer {
    if let player = pooledPlayers.popLast() {
      return player
    }
    return AVPlayer()
  }

  func recycle(_ player: AVPlayer) {
    player.pause()
    player.replaceCurrentItem(with: nil)
    player.rate = 0
    player.defaultRate = 1
    player.volume = 1
    player.isMuted = false
    player.actionAtItemEnd = .pause
    player.allowsExternalPlayback = true
    guard maxPooledPlayers > 0, pooledPlayers.count < maxPooledPlayers else { return }
    pooledPlayers.append(player)
  }

  func stats() -> [String: Any] {
    [
      "pooledPlayers": pooledPlayers.count,
      "maxPooledPlayers": maxPooledPlayers,
      "warmedAssets": FastVideoPreloader.shared.count
    ]
  }

  func clearTransientState() {
    FastVideoPreloader.shared.clear()
  }
}
