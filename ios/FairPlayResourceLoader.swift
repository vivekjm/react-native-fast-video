import AVFoundation
import Foundation

internal enum FairPlayError: LocalizedError {
  case missingCertificateURL
  case missingLicenseURL
  case missingContentIdentifier
  case invalidLicenseResponse
  case httpFailure(Int)

  var errorDescription: String? {
    switch self {
    case .missingCertificateURL: return "FairPlay certificateUrl is required"
    case .missingLicenseURL: return "FairPlay licenseUrl is required"
    case .missingContentIdentifier: return "Could not derive the FairPlay content identifier"
    case .invalidLicenseResponse: return "The FairPlay server returned an invalid CKC response"
    case .httpFailure(let status): return "FairPlay request failed with HTTP status \(status)"
    }
  }
}

internal final class FairPlayResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
  private let configuration: FastVideoDrm
  private let session: URLSession

  init(configuration: FastVideoDrm, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
    super.init()
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard loadingRequest.request.url?.scheme?.lowercased() == "skd" else {
      return false
    }

    Task {
      do {
        try await fulfill(loadingRequest)
      } catch {
        loadingRequest.finishLoading(with: error)
      }
    }
    return true
  }

  private func fulfill(_ loadingRequest: AVAssetResourceLoadingRequest) async throws {
    guard let certificateString = configuration.certificateUrl,
          let certificateURL = URL(string: certificateString) else {
      throw FairPlayError.missingCertificateURL
    }
    guard let licenseURL = URL(string: configuration.licenseUrl) else {
      throw FairPlayError.missingLicenseURL
    }

    let (certificate, certificateResponse) = try await session.data(from: certificateURL)
    try validate(certificateResponse)

    let contentId = configuration.contentId
      ?? loadingRequest.request.url?.host
      ?? loadingRequest.request.url?.absoluteString
    guard let contentId, let contentIdData = contentId.data(using: .utf8) else {
      throw FairPlayError.missingContentIdentifier
    }

    let spc = try loadingRequest.streamingContentKeyRequestData(
      forApp: certificate,
      contentIdentifier: contentIdData,
      options: nil
    )

    var request = URLRequest(url: licenseURL)
    request.httpMethod = "POST"
    request.httpBody = spc
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    configuration.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let (responseData, response) = try await session.data(for: request)
    try validate(response)

    let ckc: Data
    if configuration.licenseResponseType.lowercased() == "base64" {
      guard let value = String(data: responseData, encoding: .utf8),
            let decoded = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw FairPlayError.invalidLicenseResponse
      }
      ckc = decoded
    } else {
      ckc = responseData
    }

    guard !ckc.isEmpty else { throw FairPlayError.invalidLicenseResponse }
    loadingRequest.dataRequest?.respond(with: ckc)
    loadingRequest.finishLoading()
  }

  private func validate(_ response: URLResponse) throws {
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw FairPlayError.httpFailure(http.statusCode)
    }
  }
}
