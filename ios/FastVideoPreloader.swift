import AVFoundation

/// Retains AVURLAssets long enough for AVFoundation to reuse warmed manifests, metadata, DNS/TLS,
/// and URL cache state when the corresponding FastVideo view becomes active.
internal final class FastVideoPreloader {
  static let shared = FastVideoPreloader()

  private var assets: [String: AVURLAsset] = [:]
  private var order: [String] = []
  private var indexByKey: [String: Int] = [:]
  private let maxAssets = 12
  private let retentionDistance = 4
  private let core = RNFVFastCoreBridge()
  private var previousFocusIndex = 0

  var count: Int { assets.count }

  private init() {}

  func preload(_ sources: [FastVideoSource], currentIndex: Int) -> Int {
    clear()
    let ranked = sources.enumerated().sorted { lhs, rhs in
      abs((lhs.element.preloadIndex ?? lhs.offset) - currentIndex) <
        abs((rhs.element.preloadIndex ?? rhs.offset) - currentIndex)
    }

    var accepted = 0
    for (_, source) in ranked.prefix(maxAssets) where !source.uri.isEmpty {
      guard let asset = makeAsset(source) else { continue }
      let key = cacheKey(source)
      assets[key] = asset
      indexByKey[key] = source.preloadIndex ?? accepted
      order.append(key)
      accepted += 1

      // Stage the warming work by feed distance so we do not spend the same I/O/memory budget on
      // every retained asset. The nearest item gets full metadata/tracks, the second gets basic
      // playability, and farther retained assets are intentionally only constructed.
      let index = source.preloadIndex ?? accepted - 1
      let distance = abs(index - currentIndex)
      if distance <= 1 {
        asset.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) {}
      } else if distance == 2 {
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}
      }
    }
    return accepted
  }

  func focus(_ currentIndex: Int, velocityItemsPerSecond: Double = 0) -> [String: Any] {
    let itemCount = max(currentIndex + 1, (indexByKey.values.max() ?? currentIndex) + 1)
    let intent = core.viewportIntent(
      withCurrentIndex: currentIndex,
      previousIndex: previousFocusIndex,
      itemCount: itemCount,
      velocityItemsPerSecond: velocityItemsPerSecond
    ) as? [String: Any] ?? [:]
    let predicted = min(max(0, (intent["predictedIndex"] as? NSNumber)?.intValue ?? currentIndex), max(0, itemCount - 1))
    previousFocusIndex = currentIndex
    let evicted = order.filter { key in
      guard let index = indexByKey[key] else { return true }
      return abs(index - predicted) > retentionDistance
    }
    for key in evicted {
      assets.removeValue(forKey: key)
      indexByKey.removeValue(forKey: key)
    }
    order.removeAll { evicted.contains($0) }
    var result = intent
    result["actualIndex"] = currentIndex
    return result
  }

  func asset(for source: FastVideoSource) -> AVURLAsset? {
    assets[cacheKey(source)]
  }

  func clear() {
    assets.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
    indexByKey.removeAll(keepingCapacity: true)
    previousFocusIndex = 0
  }

  private func makeAsset(_ source: FastVideoSource) -> AVURLAsset? {
    guard let url = URL(string: source.uri) else { return nil }
    let options: [String: Any] = source.headers.isEmpty
      ? [:]
      : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
    return AVURLAsset(url: url, options: options)
  }

  private func cacheKey(_ source: FastVideoSource) -> String {
    let headers = source.headers.keys.sorted().map { "\($0):\(source.headers[$0] ?? "")" }.joined(separator: "|")
    return "\(source.uri)#\(headers)"
  }
}
