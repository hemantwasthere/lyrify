import AppKit
import LyrifyCore

/// Owns the Overlay's window and both its forms — the Minimized Disc and
/// the Expanded Now Playing card — keeping it where the listener left it,
/// spinning the Disc's artwork in time with playback, and turning the Now
/// Playing card's controls into real Spotify commands (ADR-0007).
///
/// The Lyrics view lands in a later ticket.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the
/// rotation angle and the artwork outcome it draws come from `DiscRotation`
/// and `ArtworkProvider`, the tested core seams.
@MainActor
final class OverlayController {
    private let window: OverlayWindow
    private let discView: DiscView
    private let nowPlayingView: NowPlayingView
    private let anchorSource: PlaybackAnchorSource
    private let bridge: SpotifyBridge
    private let artworkProvider: ArtworkProvider
    private let positionPreference: OverlayPositionPreference
    private let visibilityPreference: OverlayVisibilityPreference
    private let expansionPreference: OverlayExpansionPreference

    private var rotation = DiscRotation()

    /// The last-known Anchor's play state — the play/pause button consults
    /// this to decide which of `play()`/`pause()` to send, rather than
    /// Spotify's own `playpause` toggle, so the command sent always matches
    /// what Lyrify itself believes is true rather than trusting Spotify's
    /// own toggle to agree.
    private var isPlaying = false

    /// The Track URI the current Anchor's artwork lookup and seek-range
    /// configuration belong to. Mirrors `MenuBarController`'s lyrics-lookup
    /// rule: a slow answer for an abandoned Track must never overwrite
    /// what's on screen for the current one.
    private var currentTrackURI: String?

    /// Redraws the spinning Disc and, while Expanded, the seek slider,
    /// between Anchors. Armed only while playing; a pause cancels it,
    /// freezing both exactly where they stopped.
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
        positionPreference: OverlayPositionPreference,
        expansionPreference: OverlayExpansionPreference
    ) {
        self.anchorSource = anchorSource
        self.bridge = bridge
        self.artworkProvider = artworkProvider
        self.visibilityPreference = visibilityPreference
        self.positionPreference = positionPreference
        self.expansionPreference = expansionPreference

        let discView = DiscView()
        let nowPlayingView = NowPlayingView()
        self.discView = discView
        self.nowPlayingView = nowPlayingView

        let startsExpanded = expansionPreference.isExpanded
        let initialView: NSView = startsExpanded ? nowPlayingView : discView
        self.window = OverlayWindow(contentView: initialView)
        window.setFrameOrigin(positionPreference.origin ?? Self.defaultOrigin(for: initialView.frame.size))

        discView.onClick = { [weak self] in self?.expand() }
        nowPlayingView.onClick = { [weak self] in self?.collapse() }
        nowPlayingView.onTogglePlayPause = { [weak self] in
            guard let self else { return }
            try? (self.isPlaying ? self.bridge.pause() : self.bridge.play())
        }
        nowPlayingView.onSkipToNext = { [weak self] in try? self?.bridge.skipToNext() }
        nowPlayingView.onSkipToPrevious = { [weak self] in try? self?.bridge.skipToPrevious() }
        nowPlayingView.onSeek = { [weak self] position in try? self?.bridge.seek(to: position) }
        nowPlayingView.onVolumeChange = { [weak self] percent in try? self?.bridge.setVolume(to: percent) }

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

    /// Grows the Disc into the Now Playing card in place, then reads
    /// Spotify's actual current volume so the volume slider starts from
    /// the real value — touching it before that would otherwise jump
    /// Spotify's volume to wherever the thumb happened to be drawn.
    private func expand() {
        guard expansionPreference.isExpanded == false else { return }
        expansionPreference.isExpanded = true
        window.setContent(nowPlayingView)

        Task { [weak self] in
            guard let self, let volume = try? self.bridge.currentVolume() else { return }
            self.nowPlayingView.updateVolume(volume)
        }
    }

    private func collapse() {
        guard expansionPreference.isExpanded else { return }
        expansionPreference.isExpanded = false
        window.setContent(discView)
    }

    /// One lookup per Track, exactly like the menu bar's lyrics lookup. The
    /// artwork URL must be re-read from Spotify live for whatever is
    /// current *right now* — unlike the rest of a Track's fields, it was
    /// never captured at Anchor time — so the URI guard after the `await`
    /// matters here for the same reason it matters there: Spotify may have
    /// already moved on to a different Track by the time the read returns.
    private func reconcileArtwork(for track: Track) {
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

            guard self.currentTrackURI == track.uri else { return }
            guard case .found(let data) = outcome, let image = NSImage(data: data) else { return }
            self.discView.updateArtwork(image)
            self.nowPlayingView.updateArtwork(image)
        }
    }

    private func render(_ state: PlaybackState) {
        reconcileTrackChange(with: state)

        isPlaying = state.isPlaying
        let now = ContinuousClock.Instant.now
        rotation.anchor(isPlaying: state.isPlaying, at: now)
        discView.update(rotationDegrees: rotation.angle(at: now))

        nowPlayingView.update(isPlaying: state.isPlaying)
        if let position = state.position {
            nowPlayingView.updateSeek(position: position)
        }

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
        // — the spin and seek slider must still redraw while the status
        // item's menu is open.
        let timer = Timer(timeInterval: Self.spinFrameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.redrawPlayback() }
        }
        RunLoop.current.add(timer, forMode: .common)
        spinTimer = timer
    }

    /// New Track, once per Track: resets the artwork placeholder, kicks off
    /// its lookup, and gives the seek slider its range. A trackless blip
    /// forgets the URI, exactly like the menu bar's own lyrics-lookup rule,
    /// so the same Track reappearing re-triggers both.
    private func reconcileTrackChange(with state: PlaybackState) {
        guard let track = state.track else {
            if currentTrackURI != nil {
                currentTrackURI = nil
                discView.updatePlaceholder()
                nowPlayingView.updatePlaceholder()
            }
            return
        }
        guard track.uri != currentTrackURI else { return }
        currentTrackURI = track.uri

        discView.updatePlaceholder()
        nowPlayingView.updatePlaceholder()
        nowPlayingView.configureSeek(duration: track.duration)

        reconcileArtwork(for: track)
    }

    private func redrawPlayback() {
        let now = ContinuousClock.Instant.now
        discView.update(rotationDegrees: rotation.angle(at: now))

        if let position = anchorSource.currentEstimate().position {
            nowPlayingView.updateSeek(position: position)
        }
    }

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - defaultTrailingInset,
            y: screen.visibleFrame.maxY - size.height - defaultTopInset
        )
    }
}
