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

        menuBar = MenuBarController(anchorSource: anchorSource, lyricsProvider: lyricsProvider)
        overlay = OverlayController(anchorSource: anchorSource, lyricsProvider: lyricsProvider)

        // Both subscribers are registered before anchoring starts, so neither
        // misses the seed poll.
        anchorSource.start()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
