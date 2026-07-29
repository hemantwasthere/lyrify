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
        let bridge = PlayerBridge()
        let anchorSource = PlaybackAnchorSource(bridge: bridge)
        let lyricsProvider = LyricsProvider(transport: URLSessionLyricsTransport())
        let artworkProvider = ArtworkProvider(transport: URLSessionLyricsTransport())
        let overlayVisibility = OverlayVisibilityPreference()
        let overlayPosition = OverlayPositionPreference()
        let overlayExpansion = OverlayExpansionPreference()
        let overlaySize = OverlaySizePreference()

        let overlay = OverlayController(
            anchorSource: anchorSource,
            bridge: bridge,
            artworkProvider: artworkProvider,
            lyricsProvider: lyricsProvider,
            visibilityPreference: overlayVisibility,
            positionPreference: overlayPosition,
            expansionPreference: overlayExpansion,
            sizePreference: overlaySize
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

// Tooltips appear after roughly two seconds by default, which is far too long
// for controls the listener is already pointing at. AppKit exposes no API for
// this, only the defaults key its tooltip manager reads at startup — hence
// registering it here, before any window exists to read it.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350])

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
