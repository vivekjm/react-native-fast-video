import ExpoModulesCore
import UIKit

/// Reconnects AVAssetDownloadURLSession background events after iOS relaunches the host app.
public final class FastVideoAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == FastVideoOfflineRuntime.backgroundSessionIdentifier else {
      completionHandler()
      return
    }
    FastVideoOfflineRuntime.shared.handleBackgroundEvents(completionHandler: completionHandler)
  }
}
