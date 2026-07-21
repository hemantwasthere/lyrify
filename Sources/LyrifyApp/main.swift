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
        // Shared with OverlayController below — one Spotify truth, not one
        // bridge per subscriber (same reasoning as `PlaybackAnchorSource`'s
        // own doc comment), and it keeps `isAutomationPermitted` consistent
        // across both.
        let bridge = SpotifyBridge()
        let anchorSource = PlaybackAnchorSource(bridge: bridge)
        let lyricsProvider = LyricsProvider(transport: URLSessionLyricsTransport())
        let artworkProvider = ArtworkProvider(transport: URLSessionLyricsTransport())
        let overlayVisibility = OverlayVisibilityPreference()
        let overlayPosition = OverlayPositionPreference()
        let overlaySize = OverlaySizePreference()

        let overlay = OverlayController(
            anchorSource: anchorSource,
            bridge: bridge,
            artworkProvider: artworkProvider,
            lyricsProvider: lyricsProvider,
            visibilityPreference: overlayVisibility,
            positionPreference: overlayPosition,
            sizePreference: overlaySize
        )
        self.overlay = overlay

        let menuBar = MenuBarController(
            anchorSource: anchorSource,
            lyricsProvider: lyricsProvider,
            overlayVisibility: overlayVisibility,
            onVisibilityChange: { overlay.refreshVisibility() }
        )
        self.menuBar = menuBar

        overlay.onVisibilityChangedByHideButton = { [weak menuBar] in
            menuBar?.refreshOverlayVisibilityMenuState()
        }

        // Registered before anchoring starts, so it doesn't miss the seed poll.
        anchorSource.start()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
