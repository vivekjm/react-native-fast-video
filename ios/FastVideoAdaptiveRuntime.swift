import Foundation
import Network

@MainActor
internal final class FastVideoAdaptiveRuntime {
  static let shared = FastVideoAdaptiveRuntime()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.vivekjm.fastvideo.network")
  private var networkClass = 0
  private var activePlayers = 0
  private(set) var mode = "balanced"

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let value: Int
      if path.status != .satisfied {
        value = 0
      } else if path.usesInterfaceType(.wiredEthernet) {
        value = 4
      } else if path.usesInterfaceType(.wifi) {
        value = 3
      } else if path.usesInterfaceType(.cellular) {
        value = 2
      } else {
        value = 1
      }
      Task { @MainActor in self?.networkClass = value }
    }
    monitor.start(queue: queue)
  }

  func configure(mode: String?) {
    switch mode {
    case "off", "conservative", "aggressive": self.mode = mode ?? "balanced"
    default: self.mode = "balanced"
    }
  }

  func acquiredPlayer() { activePlayers += 1 }
  func releasedPlayer() { activePlayers = max(0, activePlayers - 1) }

  func decision(
    core: RNFVFastCoreBridge,
    bandwidth: Double,
    rebufferRatio: Double,
    droppedFrameRatio: Double,
    width: Int,
    height: Int
  ) -> [String: Any] {
    guard mode != "off" else { return [:] }
    var base = core.adaptiveDecision(
      withBandwidth: max(0, bandwidth),
      rebufferRatio: max(0, rebufferRatio),
      droppedFrameRatio: max(0, droppedFrameRatio),
      activePlayers: max(1, activePlayers),
      width: max(0, width),
      height: max(0, height),
      networkClass: networkClass,
      thermalClass: thermalClass,
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
    ) as? [String: Any] ?? [:]
    if let bitrate = (base["maxBitrateBps"] as? NSNumber)?.doubleValue {
      let multiplier = mode == "conservative" ? 0.78 : mode == "aggressive" ? 1.12 : 1
      base["maxBitrateBps"] = Int64(bitrate * multiplier)
    }
    base["mode"] = mode
    return base
  }

  func stats() -> [String: Any] {
    [
      "adaptivePlaybackEnabled": mode != "off",
      "adaptiveMode": mode,
      "activePlayers": activePlayers,
      "networkClass": networkName,
      "thermalClass": thermalClass,
      "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled
    ]
  }

  private var networkName: String {
    switch networkClass {
    case 4: return "ethernet"
    case 3: return "wifi"
    case 2: return "cellular"
    case 1: return "constrained"
    default: return "offline"
    }
  }

  private var thermalClass: Int {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return 0
    case .fair: return 1
    case .serious: return 2
    case .critical: return 3
    @unknown default: return 1
    }
  }
}
