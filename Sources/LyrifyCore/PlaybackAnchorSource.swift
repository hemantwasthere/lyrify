import Foundation

/// Subscribes a handler to the Player's own broadcast of state changes,
/// answering the object whose lifetime *is* the subscription — which the Anchor
/// stream then holds for as long as it runs. Answering `nil` means there is no
/// such broadcast to listen to, which leaves the re-anchor poll as the only
/// source of Anchors.
///
/// A port rather than a concrete observer because the broadcast is a
/// platform notification: the Anchor stream's own logic can then be driven
/// without one.
public typealias PlaybackObservations =
    @MainActor (@escaping @MainActor (PlaybackState) -> Void) -> AnyObject?

/// The one Anchor stream Lyrify runs: the Player's playback notification and
/// the slow re-anchor poll both feed a single `PlaybackClock`, and every
/// subscriber — the menu bar title, the Overlay — is handed the same
/// estimated `PlaybackState` from the same Anchor. Extracted so neither
/// surface scripts the Player or subscribes to the notification on its own;
/// there is one playback truth, not one per subscriber.
///
/// Both of its collaborators are ports, so which Player is being followed is
/// not this type's business — it is decided once, where the stream is
/// constructed. That is what lets a second Player be introduced without the
/// estimated Playback Position, the menu bar title or the Overlay learning
/// that more than one exists.
@MainActor
public final class PlaybackAnchorSource {
    private let source: any PlaybackSource
    private let observations: PlaybackObservations
    private var clock = PlaybackClock()
    private var timer: Timer?
    private var observation: AnyObject?
    private var handlers: [(PlaybackState) -> Void] = []

    /// The re-anchor cadence. This knob bounds two worst cases at once: how
    /// far Drift can accumulate between Anchors, and how long a seek — which
    /// produces no notification — can leave the Playback Position wrong. Ten
    /// seconds keeps both unnoticeable for the menu bar title and the
    /// Overlay's line timing; revisit downward if lyric-line accuracy ever
    /// demands a tighter Drift bound.
    private static let reAnchorInterval: TimeInterval = 10.0

    public init(source: any PlaybackSource, observations: @escaping PlaybackObservations) {
        self.source = source
        self.observations = observations
    }

    /// Registers a handler invoked with the estimated `PlaybackState` on
    /// every Anchor. Register every subscriber before calling `start()`, so
    /// none of them miss the seed poll.
    public func onAnchor(_ handler: @escaping (PlaybackState) -> Void) {
        handlers.append(handler)
    }

    /// The estimated `PlaybackState` right now, from the latest Anchor — for
    /// a timer firing between Anchors to re-derive without waiting for a new
    /// one.
    public func currentEstimate() -> PlaybackState {
        clock.estimatedState(at: ContinuousClock.Instant.now)
    }

    /// Starts observing the Player: the seed poll (so playback already underway
    /// appears without waiting for a state change), the slow re-anchor timer,
    /// and the notification subscription.
    public func start() {
        poll()

        // Added in `.common` mode, not the default: a menu bar's own tracking
        // loop (opening the status item's menu) otherwise suspends a
        // default-mode timer, silently pausing the re-anchor poll — and now
        // the Overlay's line changes — for as long as the menu stays open.
        let reAnchorTimer = Timer(timeInterval: Self.reAnchorInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.current.add(reAnchorTimer, forMode: .common)
        timer = reAnchorTimer

        observation = observations { [weak self] observed in
            self?.anchor(observed)
        }
    }

    private func poll() {
        let observed: PlaybackState
        do {
            observed = try source.currentState()
        } catch {
            // A later ticket turns a refused permission into an explanatory
            // state. Until then, stay quiet rather than showing a broken title.
            observed = .notRunning
        }

        anchor(observed)
    }

    private func anchor(_ observed: PlaybackState) {
        let now = ContinuousClock.Instant.now
        clock.anchor(observed, at: now)

        let state = clock.estimatedState(at: now)
        for handler in handlers {
            handler(state)
        }
    }
}
