import AppKit
import LyrifyCore

/// Lyrify's only visible surface for now: a status item naming the current Track.
///
/// Every poll result becomes an Anchor for the `PlaybackClock`, and the title
/// renders from the clock's answer. Issue #3 adds Spotify's playback
/// notification as a second Anchor source, at which point the poll becomes the
/// slow re-anchor that bounds Drift rather than the primary signal (issue #4).
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let bridge: SpotifyBridge
    private var timer: Timer?
    private var clock = PlaybackClock()
    private var lastTitle = ""

    private static let refreshInterval: TimeInterval = 1.0

    init(bridge: SpotifyBridge) {
        self.bridge = bridge
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        buildMenu()
        refresh()
        startTimer()
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
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let observed: PlaybackState
        do {
            observed = try bridge.currentState()
        } catch {
            // A later ticket turns a refused permission into an explanatory
            // state. Until then, stay quiet rather than showing a broken title.
            observed = .notRunning
        }

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
