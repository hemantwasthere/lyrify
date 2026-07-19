import AppKit
import LyrifyCore

/// Lyrify's only visible surface for now: a status item naming the current Track.
///
/// Ticket 1 polls once a second. Ticket 2 replaces the timer with Spotify's
/// playback notification, at which point the poll becomes the slow re-anchor
/// that bounds Drift rather than the primary signal.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let bridge: SpotifyBridge
    private var timer: Timer?
    private var lastState: PlaybackState = .notRunning

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
        let state: PlaybackState
        do {
            state = try bridge.currentState()
        } catch {
            // Ticket 10 turns a refused permission into an explanatory state.
            // Until then, stay quiet rather than showing a broken title.
            state = .notRunning
        }

        guard state != lastState else { return }
        lastState = state
        statusItem.button?.title = MenuBarTitle.text(for: state).map { " " + $0 } ?? ""
    }
}
