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
  }

  private let lock = NSLock()
  private let defaultsKey = "react-native-fast-video.offline.v1"
  private var entries: [String: Entry] = [:]
  private var observations: [Int: NSKeyValueObservation] = [:]
  private var backgroundCompletionHandler: (() -> Void)?
  private lazy var session: AVAssetDownloadURLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
    configuration.allowsCellularAccess = true
    configuration.sessionSendsLaunchEvents = true
    return AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: nil)
  }()

  private override init() {
    super.init()
    restore()
  }

  func handleBackgroundEvents(completionHandler: @escaping () -> Void) {
    lock.lock()
    backgroundCompletionHandler = completionHandler
    lock.unlock()
    _ = session
  }

  func enqueue(source: FastVideoSource, id requestedId: String?, title: String?) throws -> [String: Any] {
    guard !source.isLive else { throw OfflineError.liveUnsupported }
    guard source.drm == nil else { throw OfflineError.drmUnsupported }
    guard let url = URL(string: source.uri) else { throw OfflineError.invalidUri }
    let sourceType = source.type.lowercased()
    guard sourceType == "hls" || source.uri.lowercased().contains(".m3u8") else {
      throw OfflineError.hlsRequired
    }
    let id = requestedId?.isEmpty == false ? requestedId! : (source.customCacheKey ?? UUID().uuidString)
    let options: [String: Any] = source.headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
    let asset = AVURLAsset(url: url, options: options)
    let configuration = AVAssetDownloadConfiguration(asset: asset, title: title ?? source.metadata?.title ?? id)
    let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
    task.taskDescription = id

    mutate {
      entries[id] = Entry(id: id, uri: source.uri, state: "queued", progress: 0, localUri: nil, error: nil)
    }
    let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self, weak task] progress, _ in
      guard let self, let task, let id = task.taskDescription else { return }
      self.mutate {
        guard var entry = self.entries[id] else { return }
        entry.progress = progress.fractionCompleted
        entry.state = task.state == .running ? "downloading" : entry.state
        self.entries[id] = entry
      }
    }
    lock.lock(); observations[task.taskIdentifier] = observation; lock.unlock()
    task.resume()
    mutate {
      if var entry = entries[id] { entry.state = "downloading"; entries[id] = entry }
    }
    return describe(id: id)
  }

  func playbackURL(id: String) -> URL? {
    lock.lock(); defer { lock.unlock() }
    guard let entry = entries[id], entry.state == "completed", let local = entry.localUri else { return nil }
    return URL(string: local)
  }

  func remove(id: String) -> [String: Any] {
    session.getAllTasks { [weak self] tasks in
      tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
      self?.removeStored(id: id)
    }
    return ["id": id, "state": "removing"]
  }

  func pauseAll() {
    session.getAllTasks { tasks in tasks.forEach { $0.suspend() } }
    mutate {
      for key in Array(entries.keys) {
        if entries[key]?.state == "downloading" { entries[key]?.state = "stopped" }
      }
    }
  }

  func resumeAll() {
    session.getAllTasks { tasks in tasks.forEach { $0.resume() } }
    mutate {
      for key in Array(entries.keys) {
        if entries[key]?.state == "stopped" { entries[key]?.state = "downloading" }
      }
    }
  }

  func list() -> [[String: Any]] {
    lock.lock(); defer { lock.unlock() }
    return entries.values.sorted { $0.id < $1.id }.map(Self.dictionary)
  }

  func stats() -> [String: Any] {
    let values = list()
    return [
      "offlineDownloads": values.count,
      "offlineCompleted": values.filter { ($0["state"] as? String) == "completed" }.count
    ]
  }

  func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
    guard let id = assetDownloadTask.taskDescription else { return }
    mutate {
      guard var entry = entries[id] else { return }
      entry.localUri = location.absoluteString
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
        entry.state = "completed"
        entry.progress = 1
      }
      entries[id] = entry
    }
    lock.lock(); observations[task.taskIdentifier] = nil; lock.unlock()
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
    lock.lock(); defer { lock.unlock() }
    return entries[id].map(Self.dictionary) ?? ["id": id, "state": "unknown"]
  }

  private static func dictionary(_ entry: Entry) -> [String: Any] {
    var value: [String: Any] = [
      "id": entry.id,
      "uri": entry.uri,
      "state": entry.state,
      "percentDownloaded": entry.progress * 100
    ]
    if let localUri = entry.localUri { value["localUri"] = localUri }
    if let error = entry.error { value["failureReason"] = error }
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
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
    entries = decoded
  }

  enum OfflineError: LocalizedError {
    case invalidUri, liveUnsupported, drmUnsupported, hlsRequired
    var errorDescription: String? {
      switch self {
      case .invalidUri: return "Invalid offline video URI"
      case .liveUnsupported: return "Apple offline downloads support HLS VOD, not active live streams"
      case .drmUnsupported: return "Offline FairPlay license persistence is not enabled in 0.0.5"
      case .hlsRequired: return "Apple offline downloads require an HLS VOD source"
      }
    }
  }
}
