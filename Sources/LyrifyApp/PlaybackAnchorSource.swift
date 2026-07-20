import Foundation
import LyrifyCore

/// The one Anchor stream Lyrify runs: Spotify's playback notification and the
/// slow re-anchor poll both feed a single `PlaybackClock`, and every
/// subscriber — the menu bar title, the Overlay — is handed the same
/// estimated `PlaybackState` from the same Anchor. Extracted so neither
/// surface scripts Spotify or subscribes to the notification on its own;
/// there is one playback truth, not one per subscriber.
@MainActor
final class PlaybackAnchorSource {
    private let bridge: SpotifyBridge
    private var clock = PlaybackClock()
    private var timer: Timer?
    private var notificationObserver: SpotifyNotificationObserver?
    private var handlers: [(PlaybackState) -> Void] = []

    /// The re-anchor cadence. This knob bounds two worst cases at once: how
    /// far Drift can accumulate between Anchors, and how long a seek — which
    /// produces no notification — can leave the Playback Position wrong. Ten
    /// seconds keeps both unnoticeable for the menu bar title and the
    /// Overlay's line timing; revisit downward if lyric-line accuracy ever
    /// demands a tighter Drift bound.
    private static let reAnchorInterval: TimeInterval = 10.0

    init(bridge: SpotifyBridge) {
        self.bridge = bridge
    }

    /// Registers a handler invoked with the estimated `PlaybackState` on
    /// every Anchor. Register every subscriber before calling `start()`, so
    /// none of them miss the seed poll.
    func onAnchor(_ handler: @escaping (PlaybackState) -> Void) {
        handlers.append(handler)
    }

    /// The estimated `PlaybackState` right now, from the latest Anchor — for
    /// a timer firing between Anchors to re-derive without waiting for a new
    /// one.
    func currentEstimate() -> PlaybackState {
        clock.estimatedState(at: ContinuousClock.Instant.now)
    }

    /// Starts scripting Spotify: the seed poll (so playback already underway
    /// appears without waiting for a state change), the slow re-anchor timer,
    /// and the notification subscription.
    func start() {
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

        notificationObserver = SpotifyNotificationObserver { [weak self] observed in
            self?.anchor(observed)
        }
    }

    private func poll() {
        let observed: PlaybackState
        do {
            observed = try bridge.currentState()
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
