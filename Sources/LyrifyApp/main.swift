import AppKit
import LyrifyCore

/// Lyrify runs as a menu bar agent: no Dock icon, no windows, no main menu.
/// `.accessory` gives us that even when launched straight from the build
/// products directory rather than from an assembled bundle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let anchorSource = PlaybackAnchorSource(bridge: SpotifyBridge())
        let lyricsProvider = LyricsProvider(transport: URLSessionLyricsTransport())
        let overlayVisibility = OverlayVisibilityPreference()

        // The retired pill/notch Overlay is gone (ADR-0006); its replacement,
        // the draggable widget, lands in a later ticket. The "Show Overlay"
        // toggle has nothing to refresh yet.
        menuBar = MenuBarController(
            anchorSource: anchorSource,
            lyricsProvider: lyricsProvider,
            overlayVisibility: overlayVisibility,
            onVisibilityChange: {}
        )

        // Registered before anchoring starts, so it doesn't miss the seed poll.
        anchorSource.start()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
