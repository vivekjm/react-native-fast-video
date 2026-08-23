import AVFoundation
import Foundation

/// Retains AVURLAssets long enough for AVFoundation to reuse warmed manifests, metadata, DNS/TLS,
/// and URL cache state when the corresponding FastVideo view becomes active.
internal final class FastVideoPreloader {
  static let shared = FastVideoPreloader()

  private let lock = NSLock()
  private var assets: [String: AVURLAsset] = [:]
  private var order: [String] = []
  private var indexByKey: [String: Int] = [:]
  private let maxAssets = 12
  private let core = RNFVFastCoreBridge()
  private var previousFocusIndex = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return assets.count
  }

  private init() {}

  func preload(_ sources: [FastVideoSource], currentIndex: Int) -> Int {
    let ranked = sources.enumerated().sorted { lhs, rhs in
      abs((lhs.element.preloadIndex ?? lhs.offset) - currentIndex) <
        abs((rhs.element.preloadIndex ?? rhs.offset) - currentIndex)
    }

    var nextAssets: [String: AVURLAsset] = [:]
    var nextOrder: [String] = []
    var nextIndexByKey: [String: Int] = [:]

    for (fallbackIndex, source) in ranked.prefix(maxAssets) where !source.uri.isEmpty {
      guard let asset = makeAsset(source) else { continue }
      let key = cacheKey(source)
      let index = source.preloadIndex ?? fallbackIndex
      guard nextAssets[key] == nil else { continue }
      nextAssets[key] = asset
      nextIndexByKey[key] = index
      nextOrder.append(key)
      warm(asset, distance: abs(index - currentIndex))
    }

    lock.lock()
    assets = nextAssets
    order = nextOrder
    indexByKey = nextIndexByKey
    previousFocusIndex = currentIndex
    let accepted = assets.count
    lock.unlock()
    return accepted
  }

  func focus(_ currentIndex: Int, velocityItemsPerSecond: Double = 0) -> [String: Any] {
    lock.lock()
    let itemCount = max(currentIndex + 1, (indexByKey.values.max() ?? currentIndex) + 1)
    let previousIndex = previousFocusIndex
    lock.unlock()

    let rawIntent = core.viewportIntent(
      withCurrentIndex: currentIndex,
      previousIndex: previousIndex,
      itemCount: itemCount,
      velocityItemsPerSecond: velocityItemsPerSecond
    ) as? [String: Any] ?? [:]

    let predicted = min(
      max(0, (rawIntent["predictedIndex"] as? NSNumber)?.intValue ?? currentIndex),
      max(0, itemCount - 1)
    )
    let inferredDirection = (currentIndex - previousIndex).clamped(to: -1...1)
    let direction = ((rawIntent["direction"] as? NSNumber)?.intValue ?? inferredDirection)
      .clamped(to: -1...1)
    let forwardRadius = ((rawIntent["forwardRadius"] as? NSNumber)?.intValue ?? 4)
      .clamped(to: 1...12)
    let backwardRadius = ((rawIntent["backwardRadius"] as? NSNumber)?.intValue ?? 2)
      .clamped(to: 0...8)

    lock.lock()
    previousFocusIndex = currentIndex
    let evicted = order.filter { key in
      guard let index = indexByKey[key] else { return true }
      return !insideIntentWindow(
        index: index,
        center: predicted,
        direction: direction,
        forwardRadius: forwardRadius,
        backwardRadius: backwardRadius
      )
    }
    for key in evicted {
      assets.removeValue(forKey: key)
      indexByKey.removeValue(forKey: key)
    }
    order.removeAll { evicted.contains($0) }

    let retained = order.compactMap { key -> (AVURLAsset, Int)? in
      guard let asset = assets[key], let index = indexByKey[key] else { return nil }
      return (asset, index)
    }
    lock.unlock()

    // Upgrade the warm stage for the assets that are now closest to the predicted viewport.
    for (asset, index) in retained {
      warm(asset, distance: abs(index - predicted))
    }

    var result = rawIntent
    result["actualIndex"] = currentIndex
    result["appliedDirection"] = direction
    result["appliedForwardRadius"] = forwardRadius
    result["appliedBackwardRadius"] = backwardRadius
    result["retainedAssets"] = retained.count
    return result
  }

  func asset(for source: FastVideoSource) -> AVURLAsset? {
    lock.lock()
    defer { lock.unlock() }
    return assets[cacheKey(source)]
  }

  func clear() {
    lock.lock()
    assets.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
    indexByKey.removeAll(keepingCapacity: true)
    previousFocusIndex = 0
    lock.unlock()
  }

  private func insideIntentWindow(
    index: Int,
    center: Int,
    direction: Int,
    forwardRadius: Int,
    backwardRadius: Int
  ) -> Bool {
    let distance = index - center
    if distance == 0 { return true }
    if direction == 0 {
      return abs(distance) <= max(forwardRadius, backwardRadius)
    }
    let directedDistance = distance * direction
    return directedDistance > 0
      ? directedDistance <= forwardRadius
      : -directedDistance <= backwardRadius
  }

  private func warm(_ asset: AVURLAsset, distance: Int) {
    if distance <= 1 {
      asset.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) {}
    } else if distance == 2 {
      asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}
    }
  }

  private func makeAsset(_ source: FastVideoSource) -> AVURLAsset? {
    guard let url = URL(string: source.uri) else { return nil }
    let options: [String: Any] = source.headers.isEmpty
      ? [:]
      : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
    return AVURLAsset(url: url, options: options)
  }

  private func cacheKey(_ source: FastVideoSource) -> String {
    let headers = source.headers.keys.sorted().map {
      "\($0):\(source.headers[$0] ?? "")"
    }.joined(separator: "|")
    return "\(source.uri)#\(headers)"
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
