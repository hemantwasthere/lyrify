import AppKit
import LyrifyCore

/// Lyrify's only visible surface for now: a status item naming the current Track.
///
/// Spotify's playback notification and the poll each feed the `PlaybackClock`
/// as Anchor sources, and the title renders from the clock's answer. The
/// notification carries the events; the poll is the slow re-anchor that
/// bounds Drift and catches what notifications cannot report.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let bridge: SpotifyBridge
    private var timer: Timer?
    private var notificationObserver: SpotifyNotificationObserver?
    private var clock = PlaybackClock()
    private var lastTitle = ""

    /// The re-anchor cadence. This knob bounds two worst cases at once: how
    /// far Drift can accumulate between Anchors, and how long a seek — which
    /// produces no notification — can leave the Playback Position wrong. Ten
    /// seconds keeps both unnoticeable for a menu bar title; revisit downward
    /// if lyric-line accuracy ever demands a tighter Drift bound.
    private static let reAnchorInterval: TimeInterval = 10.0

    init(bridge: SpotifyBridge) {
        self.bridge = bridge
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        buildMenu()
        // The seed poll: playback already underway when Lyrify launches
        // appears without waiting for a state change.
        poll()
        startTimer()
        notificationObserver = SpotifyNotificationObserver { [weak self] observed in
            self?.anchor(observed)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "quote.bubble",
            accessibilityDescription: "Lyrify"
        )
        button.imagePosition = .imageLeading
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Lyrify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.reAnchorInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
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
        render(at: now)
    }

    /// Estimated position changes on every query, so deduplicate on the title
    /// — the part of the state this surface actually shows.
    private func render(at instant: ContinuousClock.Instant) {
        let state = clock.estimatedState(at: instant)
        let title = MenuBarTitle.text(for: state).map { " " + $0 } ?? ""

        guard title != lastTitle else { return }
        lastTitle = title
        statusItem.button?.title = title
    }
}
