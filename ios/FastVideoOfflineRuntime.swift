import AVFoundation
import Foundation

internal final class FastVideoOfflineRuntime: NSObject, AVAssetDownloadDelegate {
  static let shared = FastVideoOfflineRuntime()
  static let backgroundSessionIdentifier = "com.vivekjm.fastvideo.offline"

  private struct Entry: Codable {
    var id: String
    var uri: String
    var state: String
    var progress: Double
    var localUri: String?
    var error: String?
    var title: String?
    var headersPersisted: Bool
    var updatedAt: TimeInterval
  }

  private let lock = NSLock()
  private let defaultsKey = "react-native-fast-video.offline.v2"
  private let legacyDefaultsKey = "react-native-fast-video.offline.v1"
  private var entries: [String: Entry] = [:]
  private var observations: [Int: NSKeyValueObservation] = [:]
  private var backgroundCompletionHandler: (() -> Void)?
  private lazy var session: AVAssetDownloadURLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.backgroundSessionIdentifier
    )
    configuration.allowsCellularAccess = true
    configuration.sessionSendsLaunchEvents = true
    return AVAssetDownloadURLSession(
      configuration: configuration,
      assetDownloadDelegate: self,
      delegateQueue: nil
    )
  }()

  private override init() {
    super.init()
    restore()
    reconcileBackgroundTasks()
  }

  func handleBackgroundEvents(completionHandler: @escaping () -> Void) {
    lock.lock()
    backgroundCompletionHandler = completionHandler
    lock.unlock()
    _ = session
  }

  func enqueue(
    source: FastVideoSource,
    id requestedId: String?,
    title: String?
  ) throws -> [String: Any] {
    guard !source.isLive else { throw OfflineError.liveUnsupported }
    guard source.drm == nil else { throw OfflineError.drmUnsupported }
    guard let url = URL(string: source.uri) else { throw OfflineError.invalidUri }
    let sourceType = source.type.lowercased()
    guard sourceType == "hls" || sourceType == "auto" && source.uri.lowercased().contains(".m3u8") else {
      throw OfflineError.hlsRequired
    }

    let id = requestedId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? requestedId!.trimmingCharacters(in: .whitespacesAndNewlines)
      : (source.customCacheKey ?? stableId(source.uri))

    lock.lock()
    if let existing = entries[id] {
      let reusable = existing.state == "completed" && localPackageExists(existing.localUri)
      let active = ["queued", "downloading", "stopped"].contains(existing.state)
      if reusable {
        let result = Self.dictionary(existing)
        lock.unlock()
        return result
      }
      if active {
        lock.unlock()
        throw OfflineError.duplicateId(id)
      }
    }
    lock.unlock()

    let options: [String: Any] = source.headers.isEmpty
      ? [:]
      : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
    let asset = AVURLAsset(url: url, options: options)
    let resolvedTitle = title ?? source.metadata?.title ?? id
    let configuration = AVAssetDownloadConfiguration(asset: asset, title: resolvedTitle)
    let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
    task.taskDescription = id

    mutate {
      entries[id] = Entry(
        id: id,
        uri: source.uri,
        state: "queued",
        progress: 0,
        localUri: nil,
        error: nil,
        title: resolvedTitle,
        headersPersisted: !source.headers.isEmpty,
        updatedAt: Date().timeIntervalSince1970
      )
    }
    observe(task: task, id: id)
    task.resume()
    mutate {
      guard var entry = entries[id] else { return }
      entry.state = "downloading"
      entry.updatedAt = Date().timeIntervalSince1970
      entries[id] = entry
    }
    return describe(id: id)
  }

  func playbackURL(id: String) -> URL? {
    lock.lock()
    defer { lock.unlock() }
    guard
      let entry = entries[id],
      entry.state == "completed",
      let local = entry.localUri,
      localPackageExists(local)
    else { return nil }
    return URL(string: local)
  }

  func remove(id: String) -> [String: Any] {
    let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return ["id": id, "state": "invalid"] }
    mutate {
      if var entry = entries[normalized] {
        entry.state = "removing"
        entry.updatedAt = Date().timeIntervalSince1970
        entries[normalized] = entry
      }
    }
    session.getAllTasks { [weak self] tasks in
      tasks.filter { $0.taskDescription == normalized }.forEach { $0.cancel() }
      self?.removeStored(id: normalized)
    }
    return ["id": normalized, "state": "removing"]
  }

  func pauseAll() {
    session.getAllTasks { tasks in tasks.forEach { $0.suspend() } }
    mutate {
      for key in Array(entries.keys) where entries[key]?.state == "downloading" {
        entries[key]?.state = "stopped"
        entries[key]?.updatedAt = Date().timeIntervalSince1970
      }
    }
  }

  func resumeAll() {
    session.getAllTasks { tasks in tasks.forEach { $0.resume() } }
    mutate {
      for key in Array(entries.keys) where entries[key]?.state == "stopped" {
        entries[key]?.state = "downloading"
        entries[key]?.updatedAt = Date().timeIntervalSince1970
      }
    }
  }

  func list() -> [[String: Any]] {
    validateCompletedPackages()
    lock.lock()
    defer { lock.unlock() }
    return entries.values.sorted { $0.id < $1.id }.map(Self.dictionary)
  }

  func stats() -> [String: Any] {
    let values = list()
    return [
      "offlineDownloads": values.count,
      "offlineCompleted": values.filter { ($0["state"] as? String) == "completed" }.count,
      "offlineActive": values.filter {
        ["queued", "downloading", "stopped"].contains(($0["state"] as? String) ?? "")
      }.count
    ]
  }

  func urlSession(
    _ session: URLSession,
    assetDownloadTask: AVAssetDownloadTask,
    willDownloadTo location: URL
  ) {
    guard let id = assetDownloadTask.taskDescription else { return }
    mutate {
      guard var entry = entries[id] else { return }
      entry.localUri = location.absoluteString
      entry.updatedAt = Date().timeIntervalSince1970
      entries[id] = entry
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    lock.lock()
    let completion = backgroundCompletionHandler
    backgroundCompletionHandler = nil
    lock.unlock()
    DispatchQueue.main.async { completion?() }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let id = task.taskDescription else { return }
    mutate {
      guard var entry = entries[id] else { return }
      if let error = error as NSError?, error.code != NSURLErrorCancelled {
        entry.state = "failed"
        entry.error = error.localizedDescription
      } else if error == nil {
        if localPackageExists(entry.localUri) {
          entry.state = "completed"
          entry.progress = 1
          entry.error = nil
        } else {
          entry.state = "failed"
          entry.error = "AVFoundation completed without a readable local asset package."
        }
      }
      entry.updatedAt = Date().timeIntervalSince1970
      entries[id] = entry
    }
    lock.lock()
    observations[task.taskIdentifier] = nil
    lock.unlock()
  }

  private func observe(task: AVAssetDownloadTask, id: String) {
    let observation = task.progress.observe(\.fractionCompleted, options: [.new]) {
      [weak self, weak task] progress, _ in
      guard let self, let task else { return }
      self.mutate {
        guard var entry = self.entries[id] else { return }
        entry.progress = max(0, min(1, progress.fractionCompleted))
        entry.state = task.state == .running ? "downloading" : entry.state
        entry.updatedAt = Date().timeIntervalSince1970
        self.entries[id] = entry
      }
    }
    lock.lock()
    observations[task.taskIdentifier] = observation
    lock.unlock()
  }

  private func reconcileBackgroundTasks() {
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      let ids = Set(tasks.compactMap(\.taskDescription))
      for task in tasks {
        guard let id = task.taskDescription, let assetTask = task as? AVAssetDownloadTask else { continue }
        self.observe(task: assetTask, id: id)
        self.mutate {
          guard var entry = self.entries[id] else { return }
          entry.state = switch task.state {
          case .running: "downloading"
          case .suspended: "stopped"
          case .canceling: "removing"
          case .completed: entry.state
          @unknown default: entry.state
          }
          entry.updatedAt = Date().timeIntervalSince1970
          self.entries[id] = entry
        }
      }
      self.mutate {
        for key in Array(self.entries.keys) {
          guard var entry = self.entries[key] else { continue }
          if ["queued", "downloading", "stopped"].contains(entry.state) && !ids.contains(key) {
            if self.localPackageExists(entry.localUri) {
              entry.state = "completed"
              entry.progress = 1
              entry.error = nil
            } else {
              entry.state = "failed"
              entry.error = "The background download is no longer registered with the system."
            }
            entry.updatedAt = Date().timeIntervalSince1970
            self.entries[key] = entry
          }
        }
      }
    }
  }

  private func validateCompletedPackages() {
    mutate {
      for key in Array(entries.keys) {
        guard var entry = entries[key], entry.state == "completed" else { continue }
        if !localPackageExists(entry.localUri) {
          entry.state = "failed"
          entry.progress = 0
          entry.error = "The downloaded asset package is missing from disk."
          entry.updatedAt = Date().timeIntervalSince1970
          entries[key] = entry
        }
      }
    }
  }

  private func removeStored(id: String) {
    var local: String?
    mutate {
      local = entries[id]?.localUri
      entries[id] = nil
    }
    if let local, let url = URL(string: local), url.isFileURL {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func describe(id: String) -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return entries[id].map(Self.dictionary) ?? ["id": id, "state": "unknown"]
  }

  private static func dictionary(_ entry: Entry) -> [String: Any] {
    var value: [String: Any] = [
      "id": entry.id,
      "uri": entry.uri,
      "state": entry.state,
      "percentDownloaded": entry.progress * 100,
      "headersPersisted": entry.headersPersisted,
      "updatedAt": entry.updatedAt
    ]
    if let localUri = entry.localUri { value["localUri"] = localUri }
    if let error = entry.error { value["failureReason"] = error }
    if let title = entry.title { value["title"] = title }
    return value
  }

  private func mutate(_ block: () -> Void) {
    lock.lock()
    block()
    persistLocked()
    lock.unlock()
  }

  private func persistLocked() {
    if let data = try? JSONEncoder().encode(entries) {
      UserDefaults.standard.set(data, forKey: defaultsKey)
    }
  }

  private func restore() {
    if let data = UserDefaults.standard.data(forKey: defaultsKey),
       let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
      entries = decoded
      return
    }

    // One-time migration from the Phase 4 entry shape.
    guard
      let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
      let legacy = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
    else { return }
    let now = Date().timeIntervalSince1970
    for (id, raw) in legacy {
      entries[id] = Entry(
        id: id,
        uri: raw["uri"] as? String ?? "",
        state: raw["state"] as? String ?? "failed",
        progress: raw["progress"] as? Double ?? 0,
        localUri: raw["localUri"] as? String,
        error: raw["error"] as? String,
        title: raw["title"] as? String,
        headersPersisted: false,
        updatedAt: now
      )
    }
    persistLocked()
  }

  private func localPackageExists(_ raw: String?) -> Bool {
    guard let raw, let url = URL(string: raw), url.isFileURL else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private func stableId(_ uri: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in uri.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(format: "rnfv-%016llx", hash)
  }

  enum OfflineError: LocalizedError {
    case invalidUri
    case liveUnsupported
    case drmUnsupported
    case hlsRequired
    case duplicateId(String)

    var errorDescription: String? {
      switch self {
      case .invalidUri:
        return "Invalid offline video URI"
      case .liveUnsupported:
        return "Apple offline downloads support HLS VOD, not active live streams"
      case .drmUnsupported:
        return "Offline FairPlay license persistence is reserved for Phase 6"
      case .hlsRequired:
        return "Apple offline downloads require an HLS VOD source"
      case let .duplicateId(id):
        return "An active offline download already uses id: \(id)"
      }
    }
  }
}
