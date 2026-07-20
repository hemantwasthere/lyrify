import Foundation

/// Shared by every Anchor/Instant-driven estimator (`PlaybackClock`,
/// `DiscRotation`) that turns elapsed `Duration` into the `TimeInterval`
/// their arithmetic is in.
extension Duration {
    var seconds: TimeInterval {
        let (whole, attoseconds) = components
        return TimeInterval(whole) + TimeInterval(attoseconds) / 1e18
    }
}
