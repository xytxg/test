import UIKit

/// A PiP episode can end before the next URL/file has resolved. Keep the app alive for that
/// bounded handover; release the assertion on success, failure, cancellation or OS expiry.
@MainActor final class PlaybackBackgroundLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "player episode handover") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        let old = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(old)
    }
}
