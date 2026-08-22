import AVFoundation
import Foundation

internal final class FairPlayResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
  private let configuration: FastVideoDrm
  private let session: URLSession
  private let workQueue = DispatchQueue(label: "com.vivekjm.fastvideo.fairplay", qos: .userInitiated)
  private let lock = NSLock()
  private var certificate: Data?
  private var tasks: [ObjectIdentifier: URLSessionTask] = [:]
  private var completed = Set<ObjectIdentifier>()

  init(configuration: FastVideoDrm, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
    super.init()
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard loadingRequest.request.url?.scheme?.lowercased() == "skd" else { return false }
    let identifier = ObjectIdentifier(loadingRequest)
    workQueue.async { [weak self, weak loadingRequest] in
      guard let self, let loadingRequest else { return }
      self.loadCertificate(for: identifier) { result in
        switch result {
        case let .success(certificate):
          self.requestContentKey(
            certificate: certificate,
            loadingRequest: loadingRequest,
            identifier: identifier
          )
        case let .failure(error):
          self.finish(loadingRequest, identifier: identifier, error: error)
        }
      }
    }
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    let identifier = ObjectIdentifier(loadingRequest)
    lock.lock()
    let task = tasks.removeValue(forKey: identifier)
    completed.insert(identifier)
    lock.unlock()
    task?.cancel()
  }

  private func loadCertificate(
    for identifier: ObjectIdentifier,
    completion: @escaping (Result<Data, Error>) -> Void
  ) {
    lock.lock()
    if let certificate {
      lock.unlock()
      completion(.success(certificate))
      return
    }
    lock.unlock()

    guard
      let raw = configuration.certificateUrl,
      let url = URL(string: raw),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else {
      completion(.failure(FairPlayError.invalidCertificateURL))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    configuration.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    let task = session.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      self.removeTask(identifier)
      if let error {
        completion(.failure(error))
        return
      }
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        completion(.failure(FairPlayError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)))
        return
      }
      guard let data, !data.isEmpty, data.count <= 1_048_576 else {
        completion(.failure(FairPlayError.invalidCertificate))
        return
      }
      self.lock.lock()
      self.certificate = data
      self.lock.unlock()
      completion(.success(data))
    }
    store(task, identifier: identifier)
    task.resume()
  }

  private func requestContentKey(
    certificate: Data,
    loadingRequest: AVAssetResourceLoadingRequest,
    identifier: ObjectIdentifier
  ) {
    guard !isCompleted(identifier) else { return }
    guard let requestURL = loadingRequest.request.url else {
      finish(loadingRequest, identifier: identifier, error: FairPlayError.invalidContentIdentifier)
      return
    }
    let contentIdentifier = configuration.contentId?.trimmingCharacters(in: .whitespacesAndNewlines)
      .flatMap { $0.isEmpty ? nil : $0 }
      ?? requestURL.absoluteString.replacingOccurrences(of: "skd://", with: "")
    guard let contentData = contentIdentifier.data(using: .utf8), !contentData.isEmpty else {
      finish(loadingRequest, identifier: identifier, error: FairPlayError.invalidContentIdentifier)
      return
    }

    let spc: Data
    do {
      spc = try loadingRequest.streamingContentKeyRequestData(
        forApp: certificate,
        contentIdentifier: contentData,
        options: nil
      )
    } catch {
      finish(loadingRequest, identifier: identifier, error: error)
      return
    }

    guard
      let licenseURL = URL(string: configuration.licenseUrl),
      ["http", "https"].contains(licenseURL.scheme?.lowercased() ?? "")
    else {
      finish(loadingRequest, identifier: identifier, error: FairPlayError.invalidLicenseURL)
      return
    }

    var request = URLRequest(url: licenseURL)
    request.httpMethod = "POST"
    request.httpBody = spc
    request.timeoutInterval = 20
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    configuration.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let task = session.dataTask(with: request) { [weak self, weak loadingRequest] data, response, error in
      guard let self, let loadingRequest else { return }
      self.removeTask(identifier)
      if let error {
        self.finish(loadingRequest, identifier: identifier, error: error)
        return
      }
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        self.finish(
          loadingRequest,
          identifier: identifier,
          error: FairPlayError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        )
        return
      }
      guard let data, !data.isEmpty, data.count <= 4_194_304 else {
        self.finish(loadingRequest, identifier: identifier, error: FairPlayError.invalidLicenseResponse)
        return
      }

      let ckc: Data?
      if self.configuration.licenseResponseType.lowercased() == "base64" {
        let trimmed = String(decoding: data, as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        ckc = Data(base64Encoded: trimmed)
      } else {
        ckc = data
      }
      guard let ckc, !ckc.isEmpty else {
        self.finish(loadingRequest, identifier: identifier, error: FairPlayError.invalidLicenseResponse)
        return
      }
      loadingRequest.dataRequest?.respond(with: ckc)
      self.finish(loadingRequest, identifier: identifier, error: nil)
    }
    store(task, identifier: identifier)
    task.resume()
  }

  private func finish(
    _ request: AVAssetResourceLoadingRequest,
    identifier: ObjectIdentifier,
    error: Error?
  ) {
    lock.lock()
    let inserted = completed.insert(identifier).inserted
    tasks.removeValue(forKey: identifier)
    lock.unlock()
    guard inserted else { return }
    if let error { request.finishLoading(with: error) }
    else { request.finishLoading() }
  }

  private func store(_ task: URLSessionTask, identifier: ObjectIdentifier) {
    lock.lock()
    if completed.contains(identifier) {
      lock.unlock()
      task.cancel()
      return
    }
    tasks[identifier] = task
    lock.unlock()
  }

  private func removeTask(_ identifier: ObjectIdentifier) {
    lock.lock()
    tasks.removeValue(forKey: identifier)
    lock.unlock()
  }

  private func isCompleted(_ identifier: ObjectIdentifier) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return completed.contains(identifier)
  }

  private enum FairPlayError: LocalizedError {
    case invalidCertificateURL
    case invalidCertificate
    case invalidContentIdentifier
    case invalidLicenseURL
    case invalidLicenseResponse
    case httpStatus(Int)

    var errorDescription: String? {
      switch self {
      case .invalidCertificateURL: return "FairPlay certificate URL is missing or invalid."
      case .invalidCertificate: return "FairPlay application certificate is empty or too large."
      case .invalidContentIdentifier: return "FairPlay content identifier is invalid."
      case .invalidLicenseURL: return "FairPlay license URL is missing or invalid."
      case .invalidLicenseResponse: return "FairPlay CKC response is empty, malformed, or too large."
      case let .httpStatus(status): return "FairPlay server returned HTTP status \(status)."
      }
    }
  }
}
