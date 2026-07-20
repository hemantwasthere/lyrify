import Foundation

/// Estimates the Disc's current rotation angle between Anchors, the same
/// way `PlaybackClock` estimates Playback Position — but the angle is never
/// externally observed the way Playback Position is; it's entirely
/// self-computed from a constant spin rate. Anchoring simply records
/// whether playback is underway right now, capturing the angle as it was
/// *estimated at that instant* so pausing never jumps to a stale value and
/// resuming always continues smoothly from where it froze.
///
/// Pure by construction: time only enters as instants passed in, so the
/// rotation is testable without timers or a live spinning view.
public struct DiscRotation: Sendable {
    private enum State: Sendable {
        /// Spinning since `instant`, having already turned `angleAtAnchor`
        /// degrees.
        case playing(angleAtAnchor: Double, instant: ContinuousClock.Instant)

        /// Frozen at `angle`, however long the pause lasts.
        case paused(angle: Double)
    }

    private var state: State?

    /// Degrees turned per second while playing — one full turn every six
    /// seconds. A tuning knob, not a locked design decision; adjust freely
    /// if the spin reads as too frantic or too slow.
    static let degreesPerSecond: Double = 60

    public init() {}

    /// Records a trusted observation of whether playback is underway, paired
    /// with the instant it was observed.
    ///
    /// The latest-fed Anchor always wins, even one carrying an older instant
    /// — same trade PlaybackClock accepts, for the same reason: both
    /// playback sources observe on the main actor and stamp their instant at
    /// delivery.
    public mutating func anchor(isPlaying: Bool, at instant: ContinuousClock.Instant) {
        let currentAngle = angle(at: instant)
        state = isPlaying
            ? .playing(angleAtAnchor: currentAngle, instant: instant)
            : .paused(angle: currentAngle)
    }

    /// The estimated angle in degrees, wrapped to `[0, 360)`, at `instant`.
    public func angle(at instant: ContinuousClock.Instant) -> Double {
        guard let state else { return 0 }

        switch state {
        case .paused(let angle):
            return angle

        case .playing(let angleAtAnchor, let anchorInstant):
            // A query behind the Anchor (out-of-order delivery) must not
            // rewind.
            let elapsed = max(0, anchorInstant.duration(to: instant).seconds)
            let degrees = angleAtAnchor + elapsed * Self.degreesPerSecond
            return degrees.truncatingRemainder(dividingBy: 360)
        }
    }
}
