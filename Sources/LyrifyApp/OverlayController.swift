import AppKit
import LyrifyCore

/// Owns the Overlay's window and its one `OverlayCardView` — keeping it
/// where the listener left it and however large they last resized it to,
/// spinning the Disc's artwork in time with playback, turning the controls
/// into real Spotify commands (ADR-0007), and rendering the Lyrics face
/// from the same `OverlayDisplay`/`LineSelection`/`LyricsWindow` seams the
/// retired Overlay used.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the
/// rotation angle, artwork outcome, and lyrics content it draws come from
/// `DiscRotation`, `ArtworkProvider`, and `OverlayDisplay`/`LineSelection`,
/// the tested core seams.
@MainActor
final class OverlayController {
    private let window: OverlayWindow
    private let overlayView: OverlayCardView
    private let anchorSource: PlaybackAnchorSource
    private let bridge: SpotifyBridge
    private let artworkProvider: ArtworkProvider
    private let blurredArtworkProvider: BlurredArtworkProvider
    private let lyricsProvider: LyricsProvider
    private let positionPreference: OverlayPositionPreference
    private let sizePreference: OverlaySizePreference
    private let visibilityPreference: OverlayVisibilityPreference
    private let blurredBackgroundPreference: BlurredBackgroundPreference

    private var rotation = DiscRotation()

    /// Fired after the Overlay's own hide button flips
    /// `OverlayVisibilityPreference` — so whatever else displays that same
    /// preference (the status item's "Show Overlay" checkbox) can re-sync
    /// itself, since this hide path doesn't go through that checkbox's own
    /// toggle.
    var onVisibilityChangedByHideButton: (() -> Void)?

    /// The current Track's Synced Lyrics once found; nil while looking up,
    /// on a confirmed miss, or when unavailable — every one of those is "no
    /// Synced Lyrics" to `OverlayDisplay`, which answers the Idle State for
    /// them.
    private var currentLyrics: [LyricLine]?

    /// Whether the widget is currently showing the Lyrics face rather than
    /// Now Playing. Not persisted — every launch starts on Now Playing.
    private var isShowingLyrics = false

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

    /// The current Track's plain artwork, once fetched — Full Layout's
    /// background falls back to this whenever the blurred treatment isn't
    /// ready yet, or the listener has turned it off.
    private var currentArtworkImage: NSImage?

    /// The current Track's blurred/color-boosted background, once
    /// computed — nil until `reconcileBlurredBackground` finishes, or if it
    /// never does (unavailable, or no real artwork to blur).
    private var currentBlurredBackgroundImage: NSImage?

    /// Redraws the spinning Disc and the seek slider between Anchors.
    /// Armed only while playing; a pause cancels it, freezing both exactly
    /// where they stopped.
    private var spinTimer: Timer?
    private static let spinFrameInterval: TimeInterval = 1.0 / 30.0

    /// "Near the top edge," matching where the retired pill used to sit —
    /// a familiar first-launch spot, not a meaningful design commitment.
    private static let defaultTopInset: CGFloat = 8
    private static let defaultTrailingInset: CGFloat = 24

    /// The smallest proven-usable Compact Layout — also the smallest the
    /// listener can resize the Overlay down to.
    private static let minimumSize = OverlayCardView.defaultSize

    /// However large the listener drags the Overlay, resizing stops
    /// here. Width is deliberately more modest than an earlier draft of
    /// this bound (480) — Full Layout's square artwork area grows with
    /// the Overlay's width, so a wider ceiling here also raises how tall
    /// Full Layout's structural minimum can get at that width, and
    /// `OverlayLayout.thresholdHeight` has to clear that at every width
    /// this ceiling allows (see its own comment). Raising this width
    /// means raising that threshold correspondingly, not independently.
    private static let maximumSize = NSSize(width: 320, height: 550)

    // nonisolated(unsafe) so deinit may remove it; safe because it's written
    // once in init and never mutated again. Same rationale as
    // `SpotifyNotificationObserver`.
    private nonisolated(unsafe) var moveObserver: NSObjectProtocol?
    private nonisolated(unsafe) var resizeObserver: NSObjectProtocol?

    init(
        anchorSource: PlaybackAnchorSource,
        bridge: SpotifyBridge,
        artworkProvider: ArtworkProvider,
        blurredArtworkProvider: BlurredArtworkProvider,
        lyricsProvider: LyricsProvider,
        visibilityPreference: OverlayVisibilityPreference,
        positionPreference: OverlayPositionPreference,
        sizePreference: OverlaySizePreference,
        blurredBackgroundPreference: BlurredBackgroundPreference
    ) {
        self.anchorSource = anchorSource
        self.bridge = bridge
        self.artworkProvider = artworkProvider
        self.blurredArtworkProvider = blurredArtworkProvider
        self.lyricsProvider = lyricsProvider
        self.visibilityPreference = visibilityPreference
        self.positionPreference = positionPreference
        self.sizePreference = sizePreference
        self.blurredBackgroundPreference = blurredBackgroundPreference

        let overlayView = OverlayCardView()
        self.overlayView = overlayView

        let initialSize = sizePreference.size ?? OverlayCardView.defaultSize

        // A remembered position can go stale between launches — a display
        // disconnected, a screen arrangement changed — and must never leave
        // the Overlay stranded off every currently attached screen.
        let initialOrigin = OverlayOrigin.resolve(
            remembered: positionPreference.origin,
            size: initialSize,
            screens: NSScreen.screens.map(\.frame),
            fallback: Self.defaultOrigin(for: initialSize)
        )

        self.window = OverlayWindow(contentView: overlayView)
        window.minSize = Self.minimumSize
        window.maxSize = Self.maximumSize
        window.setFrame(NSRect(origin: initialOrigin, size: initialSize), display: true)
        overlayView.update(layout: OverlayLayout.resolve(size: initialSize))
        overlayView.update(blurredBackgroundEnabled: blurredBackgroundPreference.isEnabled)

        overlayView.onTogglePlayPause = { [weak self] in
            guard let self else { return }
            try? (self.isPlaying ? self.bridge.pause() : self.bridge.play())
        }
        overlayView.onSkipToNext = { [weak self] in try? self?.bridge.skipToNext() }
        overlayView.onSkipToPrevious = { [weak self] in try? self?.bridge.skipToPrevious() }
        overlayView.onSeek = { [weak self] position in try? self?.bridge.seek(to: position) }
        overlayView.onVolumeChange = { [weak self] percent in try? self?.bridge.setVolume(to: percent) }
        overlayView.onToggleLyrics = { [weak self] in self?.toggleLyrics() }
        overlayView.onToggleShuffle = { [weak self] in try? self?.bridge.toggleShuffle() }
        overlayView.onToggleRepeat = { [weak self] in try? self?.bridge.toggleRepeat() }
        // Same visibility mechanism the menu bar's "Show Overlay" toggle
        // uses — not a parallel one.
        overlayView.onHideOverlay = { [weak self] in
            guard let self else { return }
            self.visibilityPreference.isVisible = false
            self.refreshVisibility()
            self.onVisibilityChangedByHideButton?()
        }
        overlayView.onToggleBlurredBackground = { [weak self] isEnabled in
            guard let self else { return }
            self.blurredBackgroundPreference.isEnabled = isEnabled
            self.applyBackgroundImage()
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionMoved() }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sizeChanged() }
        }

        refreshVisibility()

        Task { [weak self] in
            guard let self, let volume = try? self.bridge.currentVolume() else { return }
            self.overlayView.updateVolume(volume)
        }

        anchorSource.onAnchor { [weak self] state in
            self?.render(state)
        }
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
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

    private func sizeChanged() {
        let size = window.frame.size
        sizePreference.size = size
        overlayView.update(layout: OverlayLayout.resolve(size: size))
    }

    private func toggleLyrics() {
        isShowingLyrics.toggle()
        if isShowingLyrics {
            overlayView.showLyrics()
        } else {
            overlayView.showNowPlaying()
        }
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
            self.currentArtworkImage = image
            self.overlayView.updateArtwork(image)
            self.applyBackgroundImage()

            self.reconcileBlurredBackground(for: track, artwork: data)
        }
    }

    /// Layered on top of `reconcileArtwork`'s own fetch, per the ticket's
    /// own note — no fetch path of its own, just the bytes already found.
    /// Only called once real artwork bytes are confirmed in hand, so
    /// `BlurredArtworkProvider` never needs to reason about `.noArtwork`/
    /// `.unavailable` outcomes itself.
    private func reconcileBlurredBackground(for track: Track, artwork data: Data) {
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.blurredArtworkProvider.blurredBackground(for: track, artwork: data)

            guard self.currentTrackURI == track.uri else { return }
            guard case .found(let blurredData) = outcome, let image = NSImage(data: blurredData) else { return }
            self.currentBlurredBackgroundImage = image
            self.applyBackgroundImage()
        }
    }

    /// Whichever image Full Layout's background should currently show —
    /// the blurred/color-boosted treatment when enabled and ready, the
    /// plain artwork otherwise — recomputed whenever either the images or
    /// the toggle itself changes, since this is the one place that knows
    /// both.
    private func applyBackgroundImage() {
        guard let plainImage = currentArtworkImage else { return }
        let image = blurredBackgroundPreference.isEnabled ? (currentBlurredBackgroundImage ?? plainImage) : plainImage
        overlayView.updateBlurredBackground(image)
    }

    /// One lookup per Track, sharing `LyricsProvider` with the menu bar —
    /// whichever of the two asks first triggers the network call, the other
    /// rides the same memoized answer, exactly like ticket #12's Overlay did.
    /// A Non-Lyrical Item triggers no lookup at all, matching the menu bar's
    /// own rule.
    private func reconcileLyrics(for track: Track) {
        guard track.isLyrical else { return }

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.lyricsProvider.lookup(for: track)

            guard self.currentTrackURI == track.uri else { return }
            guard case .found(let lines) = outcome else { return }
            self.currentLyrics = lines
        }
    }

    private func render(_ state: PlaybackState) {
        reconcileTrackChange(with: state)

        isPlaying = state.isPlaying
        let now = ContinuousClock.Instant.now
        rotation.anchor(isPlaying: state.isPlaying, at: now)
        overlayView.update(rotationDegrees: rotation.angle(at: now))

        overlayView.update(isPlaying: state.isPlaying)
        if let position = state.position {
            overlayView.updateSeek(position: position)
        }
        refreshLyricsDisplay(state)

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

    /// New Track, once per Track: resets the artwork/track-info placeholder,
    /// kicks off its lookup, and gives the seek slider its range. A
    /// trackless blip forgets the URI, exactly like the menu bar's own
    /// lyrics-lookup rule, so the same Track reappearing re-triggers both.
    private func reconcileTrackChange(with state: PlaybackState) {
        guard let track = state.track else {
            if currentTrackURI != nil {
                currentTrackURI = nil
                currentLyrics = nil
                currentArtworkImage = nil
                currentBlurredBackgroundImage = nil
                overlayView.updatePlaceholder()
            }
            return
        }
        guard track.uri != currentTrackURI else { return }
        currentTrackURI = track.uri
        currentLyrics = nil
        currentArtworkImage = nil
        currentBlurredBackgroundImage = nil

        overlayView.updatePlaceholder()
        overlayView.updateTrackInfo(name: track.name, artist: track.artist)
        overlayView.configureSeek(duration: track.duration)

        reconcileArtwork(for: track)
        reconcileLyrics(for: track)
    }

    private func redrawPlayback() {
        let now = ContinuousClock.Instant.now
        overlayView.update(rotationDegrees: rotation.angle(at: now))

        let estimate = anchorSource.currentEstimate()
        if let position = estimate.position {
            overlayView.updateSeek(position: position)
        }
        refreshLyricsDisplay(estimate)
    }

    /// What the Lyrics face shows, composing `OverlayDisplay` (hidden/idle/
    /// lines, the same way it always has — the Overlay is always considered
    /// "visible" here, since the whole widget's own visibility is a
    /// separate concern, `refreshVisibility()`) with `LyricsWindow` for the
    /// "genuine lyrics" case, at the fixed line count `LyricsCardView`
    /// itself owns. `nextChange` goes unused: rather than arm a separate
    /// precise per-transition timer the way the retired Overlay did, this
    /// rides the same continuous redraw already driving the spin and seek
    /// slider, which is frequent enough that no line change is ever visibly
    /// late.
    private func refreshLyricsDisplay(_ state: PlaybackState) {
        let answer = OverlayDisplay.resolve(isVisible: true, state: state, lyrics: currentLyrics)

        switch answer.content {
        case .hidden:
            overlayView.updateLyrics(.nothingPlaying)

        case .idle(let trackName):
            overlayView.updateLyrics(.idle(trackName: trackName))

        case .lines(.instrumentalGap):
            overlayView.updateLyrics(.gap)

        case .lines(.lines):
            // `OverlayDisplay` only reaches `.lines` when both are known —
            // re-reading them here is cheap, and lets `LyricsWindow` widen
            // beyond the single Active/Next pair `OverlayDisplay` itself
            // answers.
            guard let position = state.position, let lyrics = currentLyrics else { return }
            let entries = LyricsWindow.resolve(at: position, in: lyrics, lineCount: LyricsCardView.lineCount)
            overlayView.updateLyrics(.lines(entries))
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
