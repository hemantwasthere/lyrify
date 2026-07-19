import AppKit
import LyrifyCore

/// Lyrify runs as a menu bar agent: no Dock icon, no windows, no main menu.
/// `.accessory` gives us that even when launched straight from the build
/// products directory rather than from an assembled bundle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(
            bridge: SpotifyBridge(),
            lyricsProvider: LyricsProvider(transport: URLSessionLyricsTransport())
        )
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
