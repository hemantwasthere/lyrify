import Foundation

/// Estimates the current `PlaybackState` between Anchors.
///
/// An Anchor is a trusted observation of playback — its state and Playback
/// Position — paired with the monotonic instant it was observed. Between
/// Anchors the Playback Position is estimated from elapsed time; each new
/// Anchor corrects the accumulated Drift. See ADR-0002.
///
/// Pure by construction: time only enters as instants passed in, so the clock
/// is testable without timers or music playing.
public struct PlaybackClock: Sendable {
    private var latest: (state: PlaybackState, instant: ContinuousClock.Instant)?

    public init() {}

    /// Records a trusted observation.
    ///
    /// The latest-fed Anchor always wins, even one carrying an older instant.
    /// Both sources — the poll and the playback notification — observe on the
    /// main actor and stamp their instant at delivery, so a stale observation
    /// can only overtake a fresh one by a queue hop measured in milliseconds,
    /// and the next re-anchor repairs it. Accepted trade; revisit only if a
    /// source ever stamps observation time rather than delivery time.
    public mutating func anchor(_ state: PlaybackState, at instant: ContinuousClock.Instant) {
        latest = (state, instant)
    }

    /// The estimated `PlaybackState` at `instant`, from the latest Anchor.
    public func estimatedState(at instant: ContinuousClock.Instant) -> PlaybackState {
        guard let latest else { return .notRunning }
        guard case .playing(let track, let position) = latest.state else {
            return latest.state
        }

        // A query behind the Anchor (out-of-order delivery) must not rewind.
        let elapsed = max(0, latest.instant.duration(to: instant).seconds)
        return .playing(track, position: min(position + elapsed, track.duration))
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let (whole, attoseconds) = components
        return TimeInterval(whole) + TimeInterval(attoseconds) / 1e18
    }
}
