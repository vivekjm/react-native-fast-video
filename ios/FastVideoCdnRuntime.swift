import Foundation

@MainActor
internal final class FastVideoCdnRuntime {
  static let shared = FastVideoCdnRuntime()

  private struct Health {
    var successes = 0
    var failures = 0
    var consecutiveFailures = 0
    var averageTtffMs = 0.0
    var averageResponseMs = 0.0
  }

  private let core = RNFVFastCoreBridge()
  private var health: [String: Health] = [:]

  private init() {}

  func rank(_ uris: [String]) -> [String] {
    uris.enumerated().sorted { lhs, rhs in
      let l = score(uri: lhs.element)
      let r = score(uri: rhs.element)
      return l == r ? lhs.offset < rhs.offset : l > r
    }.map(\.element)
  }

  func recordFirstFrame(uri: String, ttffMs: Double, responseMs: Double? = nil) {
    let key = origin(uri)
    var item = health[key] ?? Health()
    item.successes += 1
    item.consecutiveFailures = 0
    if ttffMs.isFinite, ttffMs >= 0 { item.averageTtffMs = ema(previous: item.averageTtffMs, sample: ttffMs) }
    let response = responseMs ?? ttffMs
    if response.isFinite, response >= 0 { item.averageResponseMs = ema(previous: item.averageResponseMs, sample: response) }
    health[key] = item
  }

  func recordFailure(uri: String, responseMs: Double = 0) {
    let key = origin(uri)
    var item = health[key] ?? Health()
    item.failures += 1
    item.consecutiveFailures += 1
    if responseMs.isFinite, responseMs >= 0 { item.averageResponseMs = ema(previous: item.averageResponseMs, sample: responseMs) }
    health[key] = item
  }

  func diagnostics(uri: String) -> [String: Any] {
    let key = origin(uri)
    let item = health[key] ?? Health()
    return [
      "origin": key,
      "score": score(item),
      "successes": item.successes,
      "failures": item.failures,
      "consecutiveFailures": item.consecutiveFailures,
      "averageTtffMs": item.averageTtffMs,
      "averageResponseMs": item.averageResponseMs
    ]
  }

  func stats() -> [String: Any] {
    [
      "cdnOriginsTracked": health.count,
      "cdnHealth": health.keys.sorted().map { key -> [String: Any] in
        let item = health[key] ?? Health()
        return ["origin": key, "score": score(item), "failures": item.failures, "successes": item.successes]
      }
    ]
  }

  func clear() { health.removeAll(keepingCapacity: true) }

  private func score(uri: String) -> Double { score(health[origin(uri)] ?? Health()) }

  private func score(_ item: Health) -> Double {
    let total = item.successes + item.failures
    let successRate = total == 0 ? 1.0 : Double(item.successes) / Double(total)
    let errorRate = total == 0 ? 0.0 : Double(item.failures) / Double(total)
    let value = core.cdnHealth(
      withSuccessRate: successRate,
      errorRate: errorRate,
      medianTtffMs: item.averageTtffMs,
      medianResponseMs: item.averageResponseMs,
      consecutiveFailures: item.consecutiveFailures
    ) as? [String: Any] ?? [:]
    return (value["score"] as? NSNumber)?.doubleValue ?? 0
  }

  private func ema(previous: Double, sample: Double) -> Double {
    previous <= 0 ? sample : 0.25 * sample + 0.75 * previous
  }

  private func origin(_ value: String) -> String {
    guard let components = URLComponents(string: value), let scheme = components.scheme, let host = components.host else {
      return "local"
    }
    return "\(scheme.lowercased())://\(host.lowercased())\(components.port.map { ":\($0)" } ?? "")"
  }
}
