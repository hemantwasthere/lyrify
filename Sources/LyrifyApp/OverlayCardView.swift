import AppKit
import LyrifyCore
import QuartzCore

/// The Overlay's one and only window content — the Now Playing face (a
/// small spinning Disc of album art alongside the current Track's title
/// and artist) or the Lyrics face (`LyricsCardView`) — toggled by the
/// lyrics button and crossfaded between. As the Overlay's window is now
/// user-resizable (`OverlayWindow`), this view is sized directly by that
/// window rather than pinning its own fixed size the way it used to;
/// `defaultSize` remains only as the starting size before any resize is
/// remembered. Rendering only ever shows Compact Layout for now, at
/// whatever size the window resolves to — `OverlayLayout`'s Full Layout
/// case lands in a later ticket. Previous / play-pause / next / lyrics /
/// seek / volume controls are revealed on hover over either face and
/// faded back out the moment the mouse leaves. Clicking any
/// non-interactive area (inherited from `DraggableBackgroundView`) only
/// ever starts a drag — there is no more expand/collapse gesture, since
/// there's nothing left to expand into.
///
/// Seek and volume only commit on mouse-up, not on every intermediate
/// value — dragging either shouldn't fire a live AppleScript command for
/// every pixel crossed. Both ignore external updates while the listener is
/// actively dragging them, so a redraw never fights the gesture in progress.
///
/// Deliberately untested — AppKit event handling and layout verified by
/// hand.
final class OverlayCardView: DraggableBackgroundView {
    /// The Overlay's size before any resize has ever been remembered —
    /// also `OverlayWindow`'s minimum resizable size, since it's the
    /// smallest proven-usable Compact Layout.
    static let defaultSize = NSSize(width: 220, height: 96)

    /// Compact Layout's thumbnail is a small square, not the circular Disc
    /// the pre-resizable widget used — matching Spotify's own Mini Player,
    /// which ADR-0009 names as the concrete reference for this redesign.
    static let discSize: CGFloat = 40
    private static let discCornerRadius: CGFloat = 8

    /// Not tied to the view's actual (now-variable) height — a fixed,
    /// reasonable radius for Compact Layout at any size. Full Layout's own
    /// visual treatment is a later ticket's concern.
    private static let cornerRadius: CGFloat = 24

    private static let crossfadeDuration: TimeInterval = 0.2

    var onTogglePlayPause: (() -> Void)?
    var onSkipToNext: (() -> Void)?
    var onSkipToPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onVolumeChange: ((Int) -> Void)?
    var onToggleLyrics: (() -> Void)?

    private let nowPlayingFace = NSView()
    private let discImageView = PassthroughImageView()
    private let titleLabel = PassthroughLabel(labelWithString: "")
    private let artistLabel = PassthroughLabel(labelWithString: "")
    private let lyricsFace = LyricsCardView()
    private let controlsOverlay = NSView()
    private let seekSlider = NSSlider()
    private let volumeSlider = NSSlider()
    private let playPauseButton = NSButton()
    private let lyricsButton = NSButton()

    private var isDraggingSeek = false
    private var isDraggingVolume = false
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.defaultSize))

        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // No fixed width/height constraint of its own: as the Overlay's
        // window content view, its frame is set directly by the (now
        // resizable) window, not derived from its subviews' own demands.
        translatesAutoresizingMaskIntoConstraints = false

        configureNowPlayingFace()

        lyricsFace.isHidden = true
        lyricsFace.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lyricsFace)

        NSLayoutConstraint.activate([
            lyricsFace.leadingAnchor.constraint(equalTo: leadingAnchor),
            lyricsFace.trailingAnchor.constraint(equalTo: trailingAnchor),
            lyricsFace.topAnchor.constraint(equalTo: topAnchor),
            lyricsFace.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        configureControlsOverlay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // `.activeAlways`, not `.activeInKeyWindow`: this panel never
        // becomes key, so hover must work regardless.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        controlsOverlay.animator().alphaValue = 1
    }

    override func mouseExited(with event: NSEvent) {
        controlsOverlay.animator().alphaValue = 0
    }

    /// Renders whatever `OverlayLayout` resolves for the Overlay's current
    /// size. Only Compact Layout is implemented today; Full Layout
    /// rendering is a later ticket's job. `OverlayController`'s resize
    /// bounds keep every currently reachable size resolving to `.compact`,
    /// so this only ever asserts that invariant rather than actually
    /// branching — the assertion is what should fail loudly the moment
    /// that stops being true, rather than silently rendering the wrong
    /// thing.
    func update(layout: OverlayLayout) {
        guard case .compact = layout else {
            assertionFailure("Full Layout isn't rendered yet — OverlayController's maxSize should keep this unreachable")
            return
        }
    }

    /// Rotates the Disc's artwork to `degrees` — `DiscRotation`'s current
    /// estimate, or its frozen angle while paused. A CALayer transform,
    /// not `NSView.frameCenterRotation`: the latter mutates the view's own
    /// frame, which fights Auto Layout's own relayout on every pass and
    /// produced a visibly broken spin; a layer transform is purely a
    /// render-time effect Auto Layout never looks at.
    func update(rotationDegrees: Double) {
        let radians = CGFloat(rotationDegrees) * .pi / 180
        discImageView.layer?.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
    }

    /// Shows real album art. No tint — the art speaks for itself.
    func updateArtwork(_ image: NSImage) {
        discImageView.contentTintColor = nil
        discImageView.image = image
    }

    /// Back to the placeholder — no artwork or track name known yet, or a
    /// confirmed no-artwork outcome. Real track info follows immediately
    /// via `updateTrackInfo` whenever a Track is actually known.
    func updatePlaceholder() {
        discImageView.contentTintColor = OverlayArtworkPlaceholder.tint
        discImageView.image = OverlayArtworkPlaceholder.image(pointSize: 16)
        titleLabel.stringValue = LyricsCardView.nothingPlayingText
        artistLabel.stringValue = ""
    }

    /// The current Track's name and artist, shown on the Now Playing face.
    func updateTrackInfo(name: String, artist: String) {
        titleLabel.stringValue = name
        artistLabel.stringValue = artist
    }

    func update(isPlaying: Bool) {
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Play/Pause")
    }

    /// Crossfades to the Lyrics face. The controls overlay above it is
    /// unaffected — hovering still reveals the same transport, seek, and
    /// volume controls, so playback stays reachable while reading along.
    func showLyrics() {
        crossfade(from: nowPlayingFace, to: lyricsFace)
        lyricsButton.contentTintColor = .white
    }

    /// Crossfades back to the Now Playing face.
    func showNowPlaying() {
        crossfade(from: lyricsFace, to: nowPlayingFace)
        lyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
    }

    /// What the Lyrics face shows — forwarded straight to `LyricsCardView`,
    /// updated regardless of whether it's currently the visible face, so
    /// it's already current the moment the listener switches to it.
    func updateLyrics(_ content: LyricsCardView.Content) {
        lyricsFace.update(with: content)
    }

    /// Sets the seek slider's range to the current Track's duration. Called
    /// once per Track, not on every Anchor.
    func configureSeek(duration: TimeInterval) {
        seekSlider.minValue = 0
        seekSlider.maxValue = max(duration, 1)
    }

    /// Moves the seek slider's thumb to `position` — ignored while the
    /// listener is actively dragging it, so a redraw never yanks the thumb
    /// out from under their cursor.
    func updateSeek(position: TimeInterval) {
        guard !isDraggingSeek else { return }
        seekSlider.doubleValue = position
    }

    /// Sets the volume slider's thumb to Spotify's actual current volume —
    /// called once when the controls first appear, so the first drag
    /// starts from the real value rather than jumping Spotify's volume to
    /// wherever the thumb happened to be drawn. Ignored while being
    /// dragged, same as `updateSeek`.
    func updateVolume(_ percent: Int) {
        guard !isDraggingVolume else { return }
        volumeSlider.doubleValue = Double(percent)
    }

    /// Fades `from` out and `to` in together, leaving only `to` visible
    /// (and un-hidden) once the animation settles — a plain `isHidden`
    /// toggle would jump instantly, which is what this replaces.
    private func crossfade(from: NSView, to: NSView) {
        to.alphaValue = 0
        to.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.crossfadeDuration
            from.animator().alphaValue = 0
            to.animator().alphaValue = 1
        } completionHandler: {
            // AppKit always calls this back on the main thread, but the
            // completion handler's type isn't itself @MainActor — same
            // situation as `OverlayController`'s NotificationCenter/Timer
            // callbacks.
            MainActor.assumeIsolated {
                from.isHidden = true
            }
        }
    }

    private func configureNowPlayingFace() {
        discImageView.wantsLayer = true
        discImageView.layer?.cornerRadius = Self.discCornerRadius
        discImageView.layer?.masksToBounds = true
        // Fills the disc exactly — the rounded-square mask above clips
        // whatever doesn't fit.
        discImageView.image = OverlayArtworkPlaceholder.image(pointSize: 16)
        discImageView.contentTintColor = OverlayArtworkPlaceholder.tint
        discImageView.imageScaling = .scaleProportionallyDown
        discImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        artistLabel.font = .systemFont(ofSize: 11, weight: .regular)
        artistLabel.textColor = .white.withAlphaComponent(0.7)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        artistLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, artistLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [discImageView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        nowPlayingFace.translatesAutoresizingMaskIntoConstraints = false
        nowPlayingFace.addSubview(row)
        addSubview(nowPlayingFace)

        NSLayoutConstraint.activate([
            discImageView.widthAnchor.constraint(equalToConstant: Self.discSize),
            discImageView.heightAnchor.constraint(equalToConstant: Self.discSize),

            row.leadingAnchor.constraint(equalTo: nowPlayingFace.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(lessThanOrEqualTo: nowPlayingFace.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: nowPlayingFace.centerYAnchor),

            nowPlayingFace.leadingAnchor.constraint(equalTo: leadingAnchor),
            nowPlayingFace.trailingAnchor.constraint(equalTo: trailingAnchor),
            nowPlayingFace.topAnchor.constraint(equalTo: topAnchor),
            nowPlayingFace.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureControlsOverlay() {
        controlsOverlay.wantsLayer = true
        controlsOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        controlsOverlay.alphaValue = 0
        controlsOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlsOverlay)

        NSLayoutConstraint.activate([
            controlsOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsOverlay.topAnchor.constraint(equalTo: topAnchor),
            controlsOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let previousButton = transportButton(symbolName: "backward.fill", action: #selector(previousTapped))
        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play/Pause")
        styleTransportButton(playPauseButton)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseTapped)
        let nextButton = transportButton(symbolName: "forward.fill", action: #selector(nextTapped))

        lyricsButton.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Lyrics")
        styleTransportButton(lyricsButton)
        lyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
        lyricsButton.target = self
        lyricsButton.action = #selector(lyricsTapped)

        let transportRow = NSStackView(views: [previousButton, playPauseButton, nextButton, lyricsButton])
        transportRow.orientation = .horizontal
        transportRow.spacing = 20

        let volumeIcon = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume") ?? NSImage())
        volumeIcon.contentTintColor = .white
        styleSlider(volumeSlider, min: 0, max: 100)
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged)
        let volumeRow = NSStackView(views: [volumeIcon, volumeSlider])
        volumeRow.orientation = .horizontal
        volumeRow.spacing = 6

        styleSlider(seekSlider, min: 0, max: 1)
        seekSlider.target = self
        seekSlider.action = #selector(seekSliderChanged)

        let stack = NSStackView(views: [seekSlider, transportRow, volumeRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: controlsOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: controlsOverlay.centerYAnchor),
            // Relative to the card's own (now resizable) width, not a fixed
            // constant, so the seek bar keeps filling it at any size.
            seekSlider.widthAnchor.constraint(equalTo: controlsOverlay.widthAnchor, constant: -32),
            volumeSlider.widthAnchor.constraint(equalToConstant: 100),
        ])
    }

    private func transportButton(symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage(), target: self, action: action)
        styleTransportButton(button)
        return button
    }

    private func styleTransportButton(_ button: NSButton) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .white
    }

    private func styleSlider(_ slider: NSSlider, min: Double, max: Double) {
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = true
    }

    @objc private func playPauseTapped() {
        onTogglePlayPause?()
    }

    @objc private func previousTapped() {
        onSkipToPrevious?()
    }

    @objc private func nextTapped() {
        onSkipToNext?()
    }

    @objc private func lyricsTapped() {
        onToggleLyrics?()
    }

    @objc private func seekSliderChanged(_ sender: NSSlider) {
        isDraggingSeek = !isFinalSliderEvent
        guard isFinalSliderEvent else { return }
        onSeek?(sender.doubleValue)
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        isDraggingVolume = !isFinalSliderEvent
        guard isFinalSliderEvent else { return }
        onVolumeChange?(Int(sender.doubleValue))
    }

    /// False for the mouse-down and every drag tick, true for whatever ends
    /// the gesture (mouse-up) — the commit-on-release gate both sliders
    /// share, so dragging never fires a live command per pixel crossed.
    private var isFinalSliderEvent: Bool {
        switch window?.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged: false
        default: true
        }
    }
}
