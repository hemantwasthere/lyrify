import AppKit
import LyrifyCore

/// Lyrify runs as a menu bar agent: no Dock icon, no windows, no main menu.
/// `.accessory` gives us that even when launched straight from the build
/// products directory rather than from an assembled bundle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var overlay: OverlayController?
    // Held because letting it go terminates the adapter it runs.
    private var floorProcess: NowPlayingFloorProcess?
    private var liveCaptions: LiveCaptionsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Shared with OverlayController below — one Spotify truth, not one
        // bridge per subscriber (same reasoning as `PlaybackAnchorSource`'s
        // own doc comment), and it keeps `isAutomationPermitted` consistent
        // across both.
        let bridge = PlayerBridge()

        // The browser Player. The adapter feeds it; if it cannot be found — the
        // app running unbundled — nothing is fed and it stays quiet.
        let floorSource = NowPlayingFloorSource()
        let floorProcess = NowPlayingFloorProcess(source: floorSource)
        self.floorProcess = floorProcess

        // The one place that names either Spotify's notification or the
        // adapter. Which Player is followed is not decided here — macOS has
        // already decided it, and the Floor is where that answer is read from.
        // The Anchor stream takes this as a port, so nothing downstream of it
        // knows that more than one Player exists.
        let liveCaptions = LiveCaptionsController()
        self.liveCaptions = liveCaptions

        // With Live Captions on, a browser is passed over entirely: the words
        // are in the captions window, and the video's title and channel have no
        // business taking the Overlay over from the music as well.
        let players = FloorArbitratedSource(
            spotify: bridge,
            floor: floorSource,
            followsBrowser: { [weak liveCaptions] in liveCaptions?.isEnabled != true }
        )

        let anchorSource = PlaybackAnchorSource(
            source: players,
            observations: { anchor in
                // Spotify's broadcast already carries the state it is
                // announcing, so it anchors directly.
                let spotify = PlayerNotificationObserver(onObservation: anchor)

                // A reading from the Floor says only that something changed;
                // what to show is still the Players' answer. Readings arrive
                // when playback changes rather than on a clock, which is
                // exactly when a fresh Anchor is worth taking.
                floorProcess.onReading = {
                    guard let state = try? players.currentState() else { return }
                    anchor(state)
                }
                return spotify
            }
        )
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
            onVisibilityChange: { overlay.refreshVisibility() },
            onMinimizeToDisc: { overlay.collapseToDisc() },
            liveCaptions: liveCaptions
        )

        // Toggling changes what the Players answer, so take a fresh Anchor at
        // once rather than leaving the Overlay wrong until the next poll.
        liveCaptions.onToggle = { [weak anchorSource] in anchorSource?.reAnchor() }

        // What is captioned is whatever holds the Floor, so the words describe
        // the thing being played rather than everything the machine is making
        // noise about.
        anchorSource.onAnchor { [weak liveCaptions] _ in
            liveCaptions?.follow(process: floorSource.holderProcess)
        }

        // Registered before anchoring starts, so it doesn't miss the seed poll.
        anchorSource.start()

        // After the Anchor stream, which is what installs the reading handler
        // the adapter's output is delivered through.
        floorProcess.start()

        // Last, so a listener who left it on gets it back without delaying
        // anything that matters more.
        liveCaptions.restore()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The adapter is a child process, and nothing reaps it for us.
        floorProcess?.stop()
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
