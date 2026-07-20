import AppKit
import LyrifyCore

/// Lyrify runs as a menu bar agent: no Dock icon, no windows, no main menu.
/// `.accessory` gives us that even when launched straight from the build
/// products directory rather than from an assembled bundle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var overlay: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let anchorSource = PlaybackAnchorSource(bridge: SpotifyBridge())
        let lyricsProvider = LyricsProvider(transport: URLSessionLyricsTransport())
        let overlayVisibility = OverlayVisibilityPreference()
        let overlayPosition = OverlayPositionPreference()

        let overlay = OverlayController(
            visibilityPreference: overlayVisibility,
            positionPreference: overlayPosition
        )
        self.overlay = overlay

        menuBar = MenuBarController(
            anchorSource: anchorSource,
            lyricsProvider: lyricsProvider,
            overlayVisibility: overlayVisibility,
            onVisibilityChange: { overlay.refreshVisibility() }
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
