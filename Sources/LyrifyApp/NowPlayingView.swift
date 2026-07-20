import AppKit
import LyrifyCore

/// The Overlay's Expanded form: album art or the Lyrics view at rest —
/// toggled by the lyrics button — with previous / play-pause / next /
/// lyrics / seek / volume controls revealed on hover and faded back out the
/// moment the mouse leaves, regardless of which background is showing.
/// Clicking any non-interactive area (via `onClick`, inherited) collapses
/// back to the Disc; dragging anywhere moves the Overlay, exactly like the
/// Disc.
///
/// Seek and volume only commit on mouse-up, not on every intermediate
/// value — dragging either shouldn't fire a live AppleScript command for
/// every pixel crossed. Both ignore external updates while the listener is
/// actively dragging them, so a redraw never fights the gesture in progress.
///
/// Deliberately untested — AppKit event handling and layout verified by
/// hand.
final class NowPlayingView: DraggableBackgroundView {
    static let size = NSSize(width: 260, height: 96)

    var onTogglePlayPause: (() -> Void)?
    var onSkipToNext: (() -> Void)?
    var onSkipToPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onVolumeChange: ((Int) -> Void)?
    var onToggleLyrics: (() -> Void)?

    private let artView = PassthroughImageView()
    private let lyricsView = LyricsCardView()
    private let controlsOverlay = NSView()
    private let seekSlider = NSSlider()
    private let volumeSlider = NSSlider()
    private let playPauseButton = NSButton()
    private let lyricsButton = NSButton()

    private var isDraggingSeek = false
    private var isDraggingVolume = false
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        wantsLayer = true
        layer?.cornerRadius = Self.size.height / 4
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        artView.image = OverlayArtworkPlaceholder.image(pointSize: 28)
        artView.contentTintColor = OverlayArtworkPlaceholder.tint
        artView.imageScaling = .scaleProportionallyDown
        artView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artView)

        NSLayoutConstraint.activate([
            artView.leadingAnchor.constraint(equalTo: leadingAnchor),
            artView.trailingAnchor.constraint(equalTo: trailingAnchor),
            artView.topAnchor.constraint(equalTo: topAnchor),
            artView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        lyricsView.isHidden = true
        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lyricsView)

        NSLayoutConstraint.activate([
            lyricsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            lyricsView.topAnchor.constraint(equalTo: topAnchor),
            lyricsView.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    /// Shows real album art. No tint — the art speaks for itself.
    func updateArtwork(_ image: NSImage) {
        artView.contentTintColor = nil
        artView.image = image
    }

    /// Back to the placeholder — no artwork known yet for the current
    /// Track, or a confirmed no-artwork outcome.
    func updatePlaceholder() {
        artView.contentTintColor = OverlayArtworkPlaceholder.tint
        artView.image = OverlayArtworkPlaceholder.image(pointSize: 28)
    }

    func update(isPlaying: Bool) {
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Play/Pause")
    }

    /// Swaps the background to the Lyrics view. The controls overlay above
    /// it is unaffected — hovering still reveals the same transport, seek,
    /// and volume controls, so playback stays reachable while reading along.
    func showLyrics() {
        lyricsView.isHidden = false
        artView.isHidden = true
        lyricsButton.contentTintColor = .white
    }

    /// Back to album art.
    func showArtwork() {
        lyricsView.isHidden = true
        artView.isHidden = false
        lyricsButton.contentTintColor = .white.withAlphaComponent(0.7)
    }

    /// What the Lyrics view shows — forwarded straight to `LyricsCardView`,
    /// updated regardless of whether it's currently the visible background,
    /// so it's already current the moment the listener switches to it.
    func updateLyrics(_ content: LyricsCardView.Content) {
        lyricsView.update(with: content)
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
    /// called once when the card expands, so the first drag starts from
    /// the real value rather than jumping Spotify's volume to wherever the
    /// thumb happened to be drawn. Ignored while being dragged, same as
    /// `updateSeek`.
    func updateVolume(_ percent: Int) {
        guard !isDraggingVolume else { return }
        volumeSlider.doubleValue = Double(percent)
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
            seekSlider.widthAnchor.constraint(equalToConstant: Self.size.width - 32),
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
