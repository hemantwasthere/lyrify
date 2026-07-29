import AppKit
import LyrifyCore

/// Owns the Overlay's window and all three of its forms — the Minimized
/// Disc, and the Expanded card's Now Playing and Lyrics views — keeping it
/// where the listener left it, spinning the Disc's artwork in time with
/// playback, turning the Now Playing card's controls into real Spotify
/// commands (ADR-0007), and rendering the Lyrics view from the same
/// `OverlayDisplay`/`LineSelection` seams the retired Overlay used.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the
/// rotation angle, artwork outcome, and lyrics content it draws come from
/// `DiscRotation`, `ArtworkProvider`, and `OverlayDisplay`/`LineSelection`,
/// the tested core seams.
@MainActor
final class OverlayController {
    private let window: OverlayWindow
    private let discView: DiscView
    private let nowPlayingView: NowPlayingView
    private let anchorSource: PlaybackAnchorSource
    private let bridge: PlayerBridge
    private let artworkProvider: ArtworkProvider
    private let lyricsProvider: LyricsProvider
    private let positionPreference: OverlayPositionPreference
    private let visibilityPreference: OverlayVisibilityPreference
    private let expansionPreference: OverlayExpansionPreference
    private let sizePreference: OverlaySizePreference
    private let backgroundColorPreference = OverlayBackgroundColorPreference()

    private var rotation = DiscRotation()

    /// The current Track's Synced Lyrics once found; nil while looking up,
    /// on a confirmed miss, or when unavailable — every one of those is "no
    /// Synced Lyrics" to `OverlayDisplay`, which answers the Idle State for
    /// them.
    private var currentLyrics: [LyricLine]?

    /// Whether the Expanded card is currently showing the Lyrics view
    /// rather than Now Playing. Resets to Now Playing every time the card
    /// expands — unlike position and expanded/collapsed state, this isn't
    /// persisted.
    private var isShowingLyrics = false

    /// The last-known Anchor's play state — the play/pause button consults
    /// this to decide which of `play()`/`pause()` to send, rather than
    /// Spotify's own `playpause` toggle, so the command sent always matches
    /// what Lyrify itself believes is true rather than trusting Spotify's
    /// own toggle to agree.
    private var isPlaying = false

    /// Spotify's shuffle and repeat state, mirrored so the two toggle buttons
    /// can light up. Read from Spotify rather than tracked locally — the
    /// listener may flip either in Spotify itself, and a local guess would
    /// drift out of step the moment they did.
    private var isShuffling = false
    private var isRepeating = false

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
    // `PlayerNotificationObserver`.
    private nonisolated(unsafe) var moveObserver: NSObjectProtocol?
    private nonisolated(unsafe) var resizeObserver: NSObjectProtocol?

    init(
        anchorSource: PlaybackAnchorSource,
        bridge: PlayerBridge,
        artworkProvider: ArtworkProvider,
        lyricsProvider: LyricsProvider,
        visibilityPreference: OverlayVisibilityPreference,
        positionPreference: OverlayPositionPreference,
        expansionPreference: OverlayExpansionPreference,
        sizePreference: OverlaySizePreference
    ) {
        self.anchorSource = anchorSource
        self.bridge = bridge
        self.artworkProvider = artworkProvider
        self.lyricsProvider = lyricsProvider
        self.visibilityPreference = visibilityPreference
        self.positionPreference = positionPreference
        self.expansionPreference = expansionPreference
        self.sizePreference = sizePreference

        let discView = DiscView()
        let nowPlayingView = NowPlayingView()
        self.discView = discView
        self.nowPlayingView = nowPlayingView

        let startsExpanded = expansionPreference.isExpanded
        let initialView: NSView = startsExpanded ? nowPlayingView : discView
        let initialSize = startsExpanded ? (sizePreference.size ?? NowPlayingView.size) : initialView.frame.size
        let initialOrigin = positionPreference.origin ?? Self.defaultOrigin(for: initialSize)

        self.window = OverlayWindow(contentView: initialView)
        // Clamped for the same reason every content swap is: a position
        // remembered from a shorter card would otherwise put this one's top
        // edge off the screen, invisible and unreachable.
        let initialFrame = OverlayWindow.clampedToScreen(NSRect(origin: initialOrigin, size: initialSize))
        window.setFrame(initialFrame, display: true)
        if startsExpanded {
            enableCardResizing()
            primeExpandedState()
        }

        discView.onClick = { [weak self] in self?.expand() }
        // The card deliberately has no `onClick`: clicking it used to collapse
        // back to the Disc, which fought with resizing it. The chrome bar's red
        // dot is now the only way back.
        nowPlayingView.onClose = { [weak self] in self?.collapse() }
        nowPlayingView.onShare = { [weak self] in self?.copyTrackLink() }
        nowPlayingView.onBackgroundColorChanged = { [weak self] isOn in
            guard let self else { return }
            self.backgroundColorPreference.isEnabled = isOn
            self.nowPlayingView.setBackgroundColorEnabled(isOn)
        }
        nowPlayingView.onResized = { [weak self] in self?.sizeChanged() }
        nowPlayingView.onTogglePlayPause = { [weak self] in
            guard let self else { return }
            try? (self.isPlaying ? self.bridge.pause() : self.bridge.play())
        }
        nowPlayingView.onSkipToNext = { [weak self] in try? self?.bridge.skipToNext() }
        nowPlayingView.onSkipToPrevious = { [weak self] in try? self?.bridge.skipToPrevious() }
        nowPlayingView.onSeek = { [weak self] position in try? self?.bridge.seek(to: position) }
        nowPlayingView.onVolumeChange = { [weak self] percent in try? self?.bridge.setVolume(to: percent) }
        nowPlayingView.onToggleLyrics = { [weak self] in self?.toggleLyrics() }
        nowPlayingView.onToggleShuffle = { [weak self] in
            guard let self else { return }
            try? self.bridge.setShuffling(!self.isShuffling)
            self.reconcileToggleState()
        }
        nowPlayingView.onToggleRepeat = { [weak self] in
            guard let self else { return }
            try? self.bridge.setRepeating(!self.isRepeating)
            self.reconcileToggleState()
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

    /// Persists the card's new size and, if the Lyrics view is showing,
    /// rescales it immediately — resizing must feel live as the listener
    /// drags an edge, not wait for the next Anchor or 30fps tick, which
    /// could be up to a re-anchor interval away while paused.
    private func sizeChanged() {
        guard expansionPreference.isExpanded else { return }
        sizePreference.size = window.frame.size
        refreshLyricsDisplay(anchorSource.currentEstimate())
    }

    /// Grows the Disc into the Now Playing card in place — the persisted
    /// card size if there is one, otherwise the default — then reads
    /// Spotify's actual current volume so the volume slider starts from
    /// the real value — touching it before that would otherwise jump
    /// Spotify's volume to wherever the thumb happened to be drawn.
    private func expand() {
        guard expansionPreference.isExpanded == false else { return }
        expansionPreference.isExpanded = true
        isShowingLyrics = false
        nowPlayingView.resetToArtwork()
        window.setContent(nowPlayingView, size: sizePreference.size ?? NowPlayingView.size, animated: true)
        enableCardResizing()

        primeExpandedState()
    }

    /// Reads the state the card can't infer from an Anchor — Spotify's actual
    /// volume, shuffle, and repeat — so the controls start out matching reality
    /// rather than a default. Needed on a fresh expand *and* at launch, since an
    /// Overlay restored in its Expanded state never passes through `expand()`
    /// and would otherwise show an empty volume slider until it was collapsed
    /// and reopened.
    private func primeExpandedState() {
        nowPlayingView.update(backgroundColorEnabled: backgroundColorPreference.isEnabled)
        nowPlayingView.setBackgroundColorEnabled(backgroundColorPreference.isEnabled)
        Task { [weak self] in
            guard let self, let volume = try? self.bridge.currentVolume() else { return }
            self.nowPlayingView.updateVolume(volume)
        }
        reconcileToggleState()
    }

    /// Re-reads shuffle and repeat from Spotify and repaints the two buttons.
    /// Called when the card expands and after either is toggled, rather than on
    /// every Anchor — neither changes often enough to be worth an Apple Event
    /// per frame.
    private func reconcileToggleState() {
        Task { [weak self] in
            guard let self, let state = try? self.bridge.currentToggleState() else { return }
            self.isShuffling = state.isShuffling
            self.isRepeating = state.isRepeating
            self.nowPlayingView.update(isShuffling: state.isShuffling, isRepeating: state.isRepeating)
        }
    }

    private func collapse() {
        guard expansionPreference.isExpanded else { return }
        expansionPreference.isExpanded = false
        window.setResizable(false)
        window.setContent(discView, animated: true)
    }

    /// Sets the card's resize bounds before turning resizing on — in that
    /// order, so there's no moment the listener could grab an edge before
    /// bounds exist to enforce.
    /// The card is resized by `WindowResizer`, which sets the window's frame
    /// itself, so the `.resizable` style mask is not needed — and is actively
    /// harmful. Turning it on makes AppKit re-derive the window's size from the
    /// content view's constraints on its next layout pass, which collapsed the
    /// card to the width of its widest required row and then ignored every
    /// attempt to widen it again. Leaving the mask alone keeps the frame ours.
    private func enableCardResizing() {
        window.minSize = NowPlayingView.minimumSize
        window.maxSize = NowPlayingView.maximumSize
    }

    /// Puts a link to the current Track on the pasteboard — the miniplayer's
    /// share button. Spotify's own URI is not a link anyone can open in a
    /// browser, so it is rewritten into the `open.spotify.com` form first.
    private func copyTrackLink() {
        guard let uri = currentTrackURI else { return }
        let identifier = uri.replacingOccurrences(of: "spotify:track:", with: "")
        guard identifier != uri else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("https://open.spotify.com/track/\(identifier)", forType: .string)
    }

    private func toggleLyrics() {
        isShowingLyrics.toggle()
        if isShowingLyrics {
            nowPlayingView.showLyrics()
        } else {
            nowPlayingView.showArtwork()
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
            self.discView.updateArtwork(image)
            self.nowPlayingView.updateArtwork(image)
        }
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
        discView.update(rotationDegrees: rotation.angle(at: now))

        nowPlayingView.update(isPlaying: state.isPlaying)
        if let position = state.position {
            nowPlayingView.updateSeek(position: position)
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

    /// New Track, once per Track: resets the artwork placeholder, kicks off
    /// its lookup, and gives the seek slider its range. A trackless blip
    /// forgets the URI, exactly like the menu bar's own lyrics-lookup rule,
    /// so the same Track reappearing re-triggers both.
    private func reconcileTrackChange(with state: PlaybackState) {
        guard let track = state.track else {
            if currentTrackURI != nil {
                currentTrackURI = nil
                currentLyrics = nil
                discView.updatePlaceholder()
                nowPlayingView.updatePlaceholder()
                nowPlayingView.clearTrackInfo()
            }
            return
        }
        guard track.uri != currentTrackURI else { return }
        currentTrackURI = track.uri
        currentLyrics = nil

        discView.updatePlaceholder()
        nowPlayingView.updatePlaceholder()
        nowPlayingView.updateTrackInfo(name: track.name, artist: track.artist)
        nowPlayingView.configureSeek(duration: track.duration)

        reconcileArtwork(for: track)
        reconcileLyrics(for: track)
    }

    private func redrawPlayback() {
        let now = ContinuousClock.Instant.now
        discView.update(rotationDegrees: rotation.angle(at: now))

        let estimate = anchorSource.currentEstimate()
        if let position = estimate.position {
            nowPlayingView.updateSeek(position: position)
        }
        refreshLyricsDisplay(estimate)
    }

    /// What the Lyrics view shows, composing three Core seams: `OverlayDisplay`
    /// decides hidden/idle/lines the same way it always has (the Overlay is
    /// always considered "visible" here, since the whole widget's own
    /// visibility is a separate concern — `refreshVisibility()`); only in
    /// the "genuine lyrics" case does `LyricsWindow` and `LyricsViewScale`
    /// come in, resolving how many surrounding lines the card's current
    /// height calls for. `nextChange` goes unused: rather than arm a
    /// separate precise per-transition timer the way the retired Overlay
    /// did, this rides the same continuous redraw already driving the spin
    /// and seek slider, which is frequent enough that no line change is
    /// ever visibly late.
    private func refreshLyricsDisplay(_ state: PlaybackState) {
        let answer = OverlayDisplay.resolve(isVisible: true, state: state, lyrics: currentLyrics)

        switch answer.content {
        case .hidden:
            nowPlayingView.updateLyrics(.nothingPlaying)

        case .idle(let trackName):
            nowPlayingView.updateLyrics(.idle(trackName: trackName))

        case .lines(.instrumentalGap):
            nowPlayingView.updateLyrics(.gap)

        case .lines(.lines):
            // `OverlayDisplay` only reaches `.lines` when both are known —
            // re-reading them here is cheap, and lets `LyricsWindow` widen
            // beyond the single Active/Next pair `OverlayDisplay` itself
            // answers.
            guard let position = state.position, let lyrics = currentLyrics else { return }
            // The panel the lines are drawn in, not the whole card: scaling to
            // the card sized every line for a box roughly twice as tall as the
            // one it actually had, which is what made the lyrics overflow.
            let scale = LyricsViewScale.resolve(forHeight: nowPlayingView.lyricsAreaHeight)
            let entries = LyricsWindow.resolve(at: position, in: lyrics, lineCount: scale.lineCount)
            nowPlayingView.updateLyrics(.lines(entries, fontSize: scale.fontSize))
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
