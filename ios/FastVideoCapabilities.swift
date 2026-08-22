import AVFoundation
import AVKit
import Foundation
import UIKit

internal enum FastVideoCapabilities {
  static func read() -> [String: Any] {
    var result: [String: Any] = [
      "platform": "ios",
      "systemVersion": UIDevice.current.systemVersion,
      "supportsPictureInPicture": AVPictureInPictureController.isPictureInPictureSupported(),
      "supportsExternalPlayback": true,
      "adaptiveStreaming": ["hls"],
      "progressivePlayback": true,
      "fourKPlayback": "streamDeviceAndCodecDependent",
      "maximumDisplayRefreshRate": UIScreen.main.maximumFramesPerSecond,
      "fairPlay": ["supported": true, "providerValidationRequired": true]
    ]

    if #available(iOS 14.0, tvOS 14.0, *) {
      result["eligibleForHDRPlayback"] = AVPlayer.eligibleForHDRPlayback
    }
    result["displayGamut"] = UIScreen.main.traitCollection.displayGamut == .P3 ? "p3" : "srgb"
    return result
  }
}
