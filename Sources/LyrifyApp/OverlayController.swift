import AppKit
import LyrifyCore

/// Owns the Overlay's window and keeps it where the listener left it,
/// spinning the Disc's artwork in time with playback.
///
/// For now the Overlay is only its Minimized Disc — expanding into a Now
/// Playing card and lyrics land in later tickets.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the
/// rotation angle and the artwork outcome it draws come from `DiscRotation`
/// and `ArtworkProvider`, the tested core seams.
@MainActor
final class OverlayController {
    private let window: DiscWindow
    private let view: DiscView
    private let bridge: SpotifyBridge
    private let artworkProvider: ArtworkProvider
    private let positionPreference: OverlayPositionPreference
    private let visibilityPreference: OverlayVisibilityPreference

    private var rotation = DiscRotation()

    /// The Track URI the current artwork lookup — pending, found, or
    /// missed — belongs to. Mirrors `MenuBarController`'s lyrics-lookup
    /// rule: a slow answer for an abandoned Track must never overwrite the
    /// artwork on screen for the current one.
    private var artworkTrackURI: String?

    /// Redraws the spinning artwork between Anchors — the core decision
    /// comes from `DiscRotation`; this timer only asks it again and again.
    /// Armed only while playing; a pause cancels it, freezing the artwork
    /// exactly where `DiscRotation` says it stopped.
    private var spinTimer: Timer?
    private static let spinFrameInterval: TimeInterval = 1.0 / 30.0

    /// "Near the top edge," matching where the retired pill used to sit —
    /// a familiar first-launch spot, not a meaningful design commitment.
    private static let defaultTopInset: CGFloat = 8
    private static let defaultTrailingInset: CGFloat = 24

    // nonisolated(unsafe) so deinit may remove it; safe because it's written
    // once in init and never mutated again. Same rationale as
    // `SpotifyNotificationObserver`.
    private nonisolated(unsafe) var moveObserver: NSObjectProtocol?

    init(
        anchorSource: PlaybackAnchorSource,
        bridge: SpotifyBridge,
        artworkProvider: ArtworkProvider,
        visibilityPreference: OverlayVisibilityPreference,
        positionPreference: OverlayPositionPreference
    ) {
        self.bridge = bridge
        self.artworkProvider = artworkProvider
        self.visibilityPreference = visibilityPreference
        self.positionPreference = positionPreference

        let view = DiscView()
        self.view = view
        self.window = DiscWindow(contentView: view)

        window.setFrameOrigin(positionPreference.origin ?? Self.defaultOrigin(for: view.frame.size))

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionMoved() }
        }

        refreshVisibility()

        anchorSource.onAnchor { [weak self] state in
            self?.render(state)
        }
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    /// What the status item's "Show Overlay" toggle calls after the
    /// listener flips it, so the change takes effect immediately.
    func refreshVisibility() {
        if visibilityPreference.isVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    private func positionMoved() {
        positionPreference.origin = window.frame.origin
    }

    /// One lookup per Track, exactly like the menu bar's lyrics lookup. The
    /// artwork URL must be re-read from Spotify live for whatever is
    /// current *right now* — unlike the rest of a Track's fields, it was
    /// never captured at Anchor time — so the URI guard after the `await`
    /// matters here for the same reason it matters there: Spotify may have
    /// already moved on to a different Track by the time the read returns.
    private func reconcileArtwork(with state: PlaybackState) {
        guard let track = state.track else {
            if artworkTrackURI != nil {
                artworkTrackURI = nil
                view.updatePlaceholder()
            }
            return
        }
        guard track.uri != artworkTrackURI else { return }
        artworkTrackURI = track.uri
        view.updatePlaceholder()

        Task { [weak self] in
            guard let self else { return }

            // A thrown read (permission refused, script failure, Spotify
            // quitting mid-call) means we never actually asked Spotify —
            // it must not be confused with Spotify *answering* "no artwork
            // URL," which `ArtworkProvider` remembers permanently. Skipping
            // the lookup here leaves nothing memoized, so a later replay of
            // this Track retries, exactly like a lyrics lookup does after
            // unavailability.
            guard let artworkURL = try? self.bridge.artworkURL() else { return }

            let outcome = await self.artworkProvider.lookup(for: track, artworkURL: artworkURL)

            guard self.artworkTrackURI == track.uri else { return }
            guard case .found(let data) = outcome, let image = NSImage(data: data) else { return }
            self.view.updateArtwork(image)
        }
    }

    private func render(_ state: PlaybackState) {
        reconcileArtwork(with: state)

        let now = ContinuousClock.Instant.now
        rotation.anchor(isPlaying: state.isPlaying, at: now)
        view.update(rotationDegrees: rotation.angle(at: now))

        // Anchors arrive far more often than play/pause actually changes —
        // every notification, every re-anchor poll — so only touch the timer
        // on a genuine transition; `spinTimer`'s presence already encodes
        // whether one is running.
        guard state.isPlaying != (spinTimer != nil) else { return }

        guard state.isPlaying else {
            spinTimer?.invalidate()
            spinTimer = nil
            return
        }

        // `.common` mode, not the default: see `PlaybackAnchorSource.start()`
        // — the spin must still redraw while the status item's menu is open.
        let timer = Timer(timeInterval: Self.spinFrameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.redrawSpin() }
        }
        RunLoop.current.add(timer, forMode: .common)
        spinTimer = timer
    }

    private func redrawSpin() {
        view.update(rotationDegrees: rotation.angle(at: ContinuousClock.Instant.now))
    }

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - defaultTrailingInset,
            y: screen.visibleFrame.maxY - size.height - defaultTopInset
        )
    }
}
