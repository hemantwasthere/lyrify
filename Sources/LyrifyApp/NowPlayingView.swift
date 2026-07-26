import AppKit
import LyrifyCore

/// The Overlay's Expanded form, built to match Spotify's miniplayer — including
/// the way it reflows as it is resized.
///
/// Two layouts, chosen by the card's height, both read off Spotify's own
/// miniplayer at a range of sizes:
///
/// - **Portrait**, the taller shape: a chrome bar that slides down from the top
///   edge, the album art centred on a panel tinted from the artwork, the
///   progress bar, then the title and artist. The transport sits over the art
///   behind a scrim and is revealed on hover.
/// - **Band**, once the card is short: a single row — the close dot and drag
///   dots stacked down the left edge, then small square art, the title and
///   artist, and the transport right-aligned. Progress and the extra controls
///   drop away as there stops being room.
///
/// The card no longer collapses when clicked: resizing replaced that gesture, so
/// only the chrome bar's red dot returns to the Disc. Dragging anywhere still
/// moves the Overlay, and `WindowResizer` handles every edge and corner.
///
/// Deliberately untested — AppKit layout and event handling verified by hand.
final class NowPlayingView: DraggableBackgroundView {
    /// Spotify's own comfortable miniplayer shape — wider than it is tall, which
    /// leaves the cover letterboxed on the tint rather than filling the panel
    /// edge to edge and pushing the card into a tall rectangle.
    static let size = NSSize(width: 380, height: 330)

    /// Spotify's own miniplayer bottoms out at 240×62; matching it is what lets
    /// the card be dragged down to a single horizontal band.
    static let minimumSize = NSSize(width: 240, height: 62)
    static let maximumSize = NSSize(width: 1600, height: 1200)

    /// Below this height the card becomes a band. Spotify's own switches at
    /// roughly this point.
    private static let bandHeightThreshold: CGFloat = 200

    /// Below these widths the band drops controls it can no longer fit, in the
    /// order Spotify sheds them.
    private static let widthForRepeat: CGFloat = 520
    private static let widthForShuffle: CGFloat = 450
    private static let widthForShare: CGFloat = 600

    private static let margin: CGFloat = 12
    /// Matches the black strip Spotify leaves above its artwork at rest.
    private static let chromeHeight: CGFloat = 22

    var onTogglePlayPause: (() -> Void)?
    var onSkipToNext: (() -> Void)?
    var onSkipToPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onVolumeChange: ((Int) -> Void)?
    var onToggleLyrics: (() -> Void)?
    var onToggleShuffle: (() -> Void)?
    var onToggleRepeat: (() -> Void)?
    var onShare: (() -> Void)?
    var onClose: (() -> Void)?
    var onBackgroundColorChanged: ((Bool) -> Void)?
    var onResized: (() -> Void)?

    /// How much height the Lyrics view actually has. The controller scales the
    /// lyrics to this rather than to the whole card, which is what kept the text
    /// far too large for its box.
    var lyricsAreaHeight: CGFloat { artPanel.bounds.height }

    private let gradientLayer = CAGradientLayer()
    private let scrimLayer = CAGradientLayer()
    private let chromeBackdrop = NSView()
    private let artPanel = NSView()
    private let artView = PassthroughImageView()
    private let lyricsView = LyricsCardView()
    private let scrim = NSView()
    private let transportRow = NSStackView()
    private let progressSection = NSStackView()
    private let infoStack = NSStackView()
    private let volumePopover = HoverPanel()
    private let settingsPanel = MiniplayerSettingsView()
    private let titleLabel = MarqueeLabel(font: .systemFont(ofSize: 16, weight: .bold), color: SpotifyPalette.textPrimary)
    private let artistLabel = MarqueeLabel(font: .systemFont(ofSize: 12, weight: .regular), color: SpotifyPalette.textSubdued)
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let remainingLabel = NSTextField(labelWithString: "0:00")
    private let seekBar = SpotifyProgressBar()
    private let volumeBar = SpotifyProgressBar()
    private let gripGlyph = ResizeGripGlyph()
    private let resizer = WindowResizer()
    private let dotsHorizontal = DragDotsView(orientation: .horizontal)
    private let dotsVertical = DragDotsView(orientation: .vertical)

    private var playPauseButton: MiniplayerButton!
    private var shuffleButton: MiniplayerButton!
    private var repeatButton: MiniplayerButton!
    private var lyricsButton: MiniplayerButton!
    private var settingsButton: MiniplayerButton!
    private var volumeButton: MiniplayerButton!
    private var shareButton: MiniplayerButton!
    private var previousButton: MiniplayerButton!
    private var nextButton: MiniplayerButton!
    private var closeButton: CloseDotButton!

    private var portraitConstraints: [NSLayoutConstraint] = []
    private var bandConstraints: [NSLayoutConstraint] = []
    private var chromeSlide: NSLayoutConstraint!
    private var isBand = false
    private var isHovering = false
    private var lyricsAvailable = true

    /// The tint the current artwork asks for, remembered even while the
    /// background-colour switch is off, so turning it back on does not have to
    /// wait for the next Track.
    private var lastAccent = SpotifyPalette.fallbackAccent
    private var isBackgroundColorEnabled = true

    /// Where a just-committed seek asked to be. Spotify keeps reporting the old
    /// position for a beat after a seek, which would drag the bar backwards
    /// under the listener's finger; until the reported position catches up (or
    /// this goes stale), incoming positions are ignored.
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekAt: Date?
    private static let pendingSeekTolerance: TimeInterval = 1.5
    private static let pendingSeekTimeout: TimeInterval = 1.5

    private var duration: TimeInterval = 1
    private var trackingArea: NSTrackingArea?
    private var volumeHideWork: DispatchWorkItem?

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = SpotifyPalette.base.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor

        buildLayout()
        applyLayoutMode(band: false, force: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // Only when something actually changed — writing constraints on every
        // pass would invalidate layout and call this again without end.
        applyLayoutMode(band: bounds.height < Self.bandHeightThreshold, force: false)
        refreshAvailableControls()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.activeAlways`: this panel never becomes key, so hover must work
        // without it.
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
        isHovering = true
        refreshRevealedControls(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshRevealedControls(animated: true)
    }

    /// Portrait hides the transport behind the art until pointed at; the band
    /// keeps its controls on show, having nothing to hide them behind.
    private func refreshRevealedControls(animated: Bool) {
        let revealed = isHovering
        let apply = {
            // The strip the chrome lives in is always there — it is just the
            // card's own black showing above the art — so nothing moves when the
            // controls arrive. They ease down into it from a few points higher,
            // which is the whole of Spotify's animation; sliding a black panel
            // down over black was only ever invisible work.
            self.chromeSlide.animator().constant = revealed ? 0 : -6
            self.closeButton.animator().alphaValue = revealed ? 1 : 0
            self.dotsHorizontal.animator().alphaValue = revealed ? 1 : 0
            self.dotsVertical.animator().alphaValue = revealed ? 1 : 0
            self.settingsButton.animator().alphaValue = revealed ? 1 : 0
            self.gripGlyph.animator().alphaValue = revealed ? 1 : 0

            if self.isBand {
                self.scrim.animator().alphaValue = 0
                self.transportRow.animator().alphaValue = 1
                self.progressSection.animator().alphaValue = 0
            } else {
                self.scrim.animator().alphaValue = revealed ? 1 : 0
                self.transportRow.animator().alphaValue = revealed ? 1 : 0
                self.progressSection.animator().alphaValue = revealed ? 1 : 0
            }
        }

        guard animated else {
            apply()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            apply()
        }
    }

    // MARK: Track metadata

    /// Shows real album art and retints the panel's gradient to match it.
    func updateArtwork(_ image: NSImage) {
        artView.contentTintColor = nil
        artView.image = image
        lastAccent = SpotifyPalette.accent(from: image)
        setAccent(isBackgroundColorEnabled ? lastAccent : SpotifyPalette.base)
    }

    func updatePlaceholder() {
        artView.contentTintColor = OverlayArtworkPlaceholder.tint
        artView.image = OverlayArtworkPlaceholder.image(pointSize: 34)
        setAccent(SpotifyPalette.fallbackAccent)
    }

    /// Cross-fades the tint rather than cutting to it, so a Track change eases
    /// into its new colour. Two stops of the same hue — bright at the top,
    /// sinking into the card's own black — so the art sits in the colour rather
    /// than on a flat block of it.
    private func setAccent(_ color: NSColor) {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.duration = 0.45
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(animation, forKey: "colors")
        gradientLayer.colors = [
            color.cgColor,
            color.blended(withFraction: 0.55, of: SpotifyPalette.base)?.cgColor ?? color.cgColor,
            SpotifyPalette.base.cgColor,
        ]
    }

    func updateTrackInfo(name: String, artist: String) {
        titleLabel.stringValue = name
        artistLabel.stringValue = artist
    }

    func clearTrackInfo() {
        titleLabel.stringValue = ""
        artistLabel.stringValue = ""
    }

    func update(isPlaying: Bool) {
        playPauseButton.setSymbol(isPlaying ? "pause.fill" : "play.fill")
        playPauseButton.toolTip = isPlaying ? "Pause" : "Play"
    }

    func update(isShuffling: Bool, isRepeating: Bool) {
        shuffleButton.isOn = isShuffling
        repeatButton.isOn = isRepeating
    }

    // MARK: Centre swap — art ⇄ lyrics

    func showLyrics() {
        crossFade(from: artView, to: lyricsView)
        lyricsButton.isOn = true
    }

    func showArtwork() {
        crossFade(from: lyricsView, to: artView)
        lyricsButton.isOn = false
    }

    func resetToArtwork() {
        lyricsView.isHidden = true
        lyricsView.alphaValue = 0
        artView.isHidden = false
        artView.alphaValue = 1
        lyricsButton.isOn = false
    }

    private func crossFade(from: NSView, to: NSView) {
        to.alphaValue = 0
        to.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            from.animator().alphaValue = 0
            to.animator().alphaValue = 1
        } completionHandler: {
            MainActor.assumeIsolated { from.isHidden = true }
        }
    }

    func updateLyrics(_ content: LyricsCardView.Content) {
        lyricsView.update(with: content)
    }

    // MARK: Playback position & volume

    func configureSeek(duration: TimeInterval) {
        self.duration = max(duration, 1)
        seekBar.maxValue = self.duration
        pendingSeekTarget = nil
        remainingLabel.stringValue = "-" + Self.timeString(self.duration)
    }

    /// Moves the seek bar and time labels, unless the listener is scrubbing or a
    /// just-committed seek is still waiting for Spotify to report it.
    func updateSeek(position: TimeInterval) {
        guard !seekBar.isDragging else { return }

        if let target = pendingSeekTarget, let requestedAt = pendingSeekAt {
            let arrived = abs(position - target) <= Self.pendingSeekTolerance
            let stale = Date().timeIntervalSince(requestedAt) > Self.pendingSeekTimeout
            guard arrived || stale else { return }
            pendingSeekTarget = nil
            pendingSeekAt = nil
        }

        seekBar.value = position
        refreshTimeLabels(position: position)
    }

    func updateVolume(_ percent: Int) {
        guard !volumeBar.isDragging else { return }
        volumeBar.value = Double(percent)
        refreshVolumeGlyph()
    }

    private func refreshTimeLabels(position: TimeInterval) {
        elapsedLabel.stringValue = Self.timeString(position)
        remainingLabel.stringValue = "-" + Self.timeString(max(duration - position, 0))
    }

    private func refreshVolumeGlyph() {
        let level = volumeBar.value
        let name: String
        switch level {
        case ..<1: name = "speaker.slash.fill"
        case ..<34: name = "speaker.fill"
        case ..<67: name = "speaker.wave.1.fill"
        default: name = "speaker.wave.2.fill"
        }
        volumeButton.setSymbol(name)
    }

    // MARK: Layout

    private func buildLayout() {
        let plate = ControlPlate()
        plate.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)
        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: trailingAnchor),
            plate.topAnchor.constraint(equalTo: topAnchor),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        buildArtPanel(in: plate)
        buildChrome(in: plate)
        buildTransportRow(in: plate)
        buildProgressSection(in: plate)
        buildInfoBar(in: plate)
        buildVolumePopover(in: plate)
        buildSettingsPanel(in: plate)

        gripGlyph.alphaValue = 0
        plate.addSubview(gripGlyph)
        NSLayoutConstraint.activate([
            gripGlyph.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -3),
            gripGlyph.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -3),
        ])

        // Topmost, so the border ring wins over anything beneath it.
        resizer.minimumSize = Self.minimumSize
        resizer.maximumSize = Self.maximumSize
        resizer.onResized = { [weak self] in self?.onResized?() }
        addSubview(resizer)
        NSLayoutConstraint.activate([
            resizer.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizer.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizer.topAnchor.constraint(equalTo: topAnchor),
            resizer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        buildConstraintSets(in: plate)
    }

    private func buildArtPanel(in plate: NSView) {
        // Layer-*hosted*, not layer-backed: handing the gradient over as the
        // view's own layer lets AppKit resize it with the view. Adding it as a
        // sublayer instead means sizing it by hand from a parent's `layout()`,
        // which runs before nested subviews have their final bounds — so it
        // stays zero-sized and never draws.
        gradientLayer.colors = [SpotifyPalette.fallbackAccent.cgColor, SpotifyPalette.base.cgColor]
        // A layer's y axis runs upward, so (0.5, 1) is the *top*. Starting at 0
        // put the first colour at the bottom and rendered both of these gradients
        // upside down — the tint pooling at the bottom and the scrim at its
        // darkest across the top of the cover.
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.cornerRadius = 8
        gradientLayer.masksToBounds = true
        artPanel.layer = gradientLayer
        artPanel.wantsLayer = true
        artPanel.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(artPanel)

        artView.wantsLayer = true
        artView.layer?.cornerRadius = 5
        artView.layer?.masksToBounds = true
        artView.imageScaling = .scaleProportionallyUpOrDown
        artView.image = OverlayArtworkPlaceholder.image(pointSize: 34)
        artView.contentTintColor = OverlayArtworkPlaceholder.tint
        artView.translatesAutoresizingMaskIntoConstraints = false
        // An `NSImageView` reports its image's full pixel size as its intrinsic
        // size, which would drag the window out to the artwork's dimensions.
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            artView.setContentCompressionResistancePriority(.defaultLow, for: axis)
            artView.setContentHuggingPriority(.defaultLow, for: axis)
        }
        artPanel.addSubview(artView)

        lyricsView.isHidden = true
        lyricsView.alphaValue = 0
        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        artPanel.addSubview(lyricsView)

        // Not a flat wash: clear at the top and deepening toward the bottom, so
        // the art stays visible above while the controls sit on something solid
        // enough to read against. A single opacity everywhere is what made it
        // look like a grey sheet.
        // Measured off Spotify's own miniplayer, by comparing the artwork's
        // luminance with and without the controls showing: it never goes fully
        // clear at the top, which is what stops the fade reading as a hard band
        // across the middle of the cover.
        scrimLayer.colors = [
            NSColor.black.withAlphaComponent(0.40).cgColor,
            NSColor.black.withAlphaComponent(0.45).cgColor,
            NSColor.black.withAlphaComponent(0.58).cgColor,
            NSColor.black.withAlphaComponent(0.73).cgColor,
            NSColor.black.withAlphaComponent(0.88).cgColor,
        ]
        scrimLayer.locations = [0, 0.1, 0.4, 0.7, 1]
        scrimLayer.startPoint = CGPoint(x: 0.5, y: 1)
        scrimLayer.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.layer = scrimLayer
        scrim.wantsLayer = true
        scrim.alphaValue = 0
        scrim.translatesAutoresizingMaskIntoConstraints = false
        artPanel.addSubview(scrim)

        // The cover is a centred square that fits the panel, never filling it —
        // Spotify letterboxes it on the tint rather than cropping.
        let square = artView.widthAnchor.constraint(equalTo: artView.heightAnchor)
        let fitWidth = artView.widthAnchor.constraint(lessThanOrEqualTo: artPanel.widthAnchor, constant: -16)
        let fitHeight = artView.heightAnchor.constraint(lessThanOrEqualTo: artPanel.heightAnchor, constant: -16)
        let growWidth = artView.widthAnchor.constraint(equalTo: artPanel.widthAnchor, constant: -16)
        let growHeight = artView.heightAnchor.constraint(equalTo: artPanel.heightAnchor, constant: -16)
        // Both of these only ever mean "take what room there is". They must stay
        // *below* the strength at which AppKit will resize the window to oblige:
        // paired with the required square above, two high-priority grows demand a
        // square panel, and rather than letting the cover letterbox, AppKit
        // reshaped the whole card to suit — pinning its width to its height less
        // the fixed rows, so the card could not be made wider than it was tall.
        growWidth.priority = .defaultLow
        growHeight.priority = .defaultLow
        // Lower still than the grows, so hugging never wins the argument and
        // shrinks the cover back.
        artView.setContentHuggingPriority(.init(1), for: .horizontal)
        artView.setContentHuggingPriority(.init(1), for: .vertical)

        NSLayoutConstraint.activate([
            square, fitWidth, fitHeight, growWidth, growHeight,
            artView.centerXAnchor.constraint(equalTo: artPanel.centerXAnchor),
            artView.centerYAnchor.constraint(equalTo: artPanel.centerYAnchor),

            lyricsView.topAnchor.constraint(equalTo: artPanel.topAnchor),
            lyricsView.leadingAnchor.constraint(equalTo: artPanel.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: artPanel.trailingAnchor),
            lyricsView.bottomAnchor.constraint(equalTo: artPanel.bottomAnchor),

            scrim.topAnchor.constraint(equalTo: artPanel.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: artPanel.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: artPanel.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: artPanel.bottomAnchor),
        ])
    }

    private func buildChrome(in plate: NSView) {
        // A layout guide rather than a view: the strip needs no colour of its
        // own, since the card behind it is already black — exactly what Spotify
        // shows in the same place at rest.
        chromeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(chromeBackdrop)

        closeButton = CloseDotButton(target: self, action: #selector(closeTapped))
        settingsButton = MiniplayerButton(style: .toggle, symbolName: "slider.horizontal.3", pointSize: 12, target: self, action: #selector(settingsTapped))
        settingsButton.toolTip = "Miniplayer settings"

        let chromePieces: [NSView] = [closeButton, dotsHorizontal, dotsVertical, settingsButton]
        for view in chromePieces {
            view.alphaValue = 0
            plate.addSubview(view)
        }

        // The controls ease down into the strip; the constant is animated rather
        // than the alpha alone, so they arrive rather than simply appear.
        chromeSlide = chromeBackdrop.topAnchor.constraint(equalTo: plate.topAnchor, constant: -6)
        NSLayoutConstraint.activate([
            chromeSlide,
            chromeBackdrop.leadingAnchor.constraint(equalTo: plate.leadingAnchor),
            chromeBackdrop.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            chromeBackdrop.heightAnchor.constraint(equalToConstant: Self.chromeHeight),
        ])
    }

    /// Spotify's seven: volume, shuffle, previous, play-pause, next, repeat,
    /// share. The band sheds them from the outside in as it narrows.
    private func buildTransportRow(in plate: NSView) {
        volumeButton = MiniplayerButton(style: .secondary, symbolName: "speaker.wave.2.fill", pointSize: 13, target: self, action: #selector(volumeTapped))
        shuffleButton = MiniplayerButton(style: .toggle, symbolName: "shuffle", pointSize: 13, target: self, action: #selector(shuffleTapped))
        previousButton = MiniplayerButton(style: .secondary, symbolName: "backward.end.fill", pointSize: 15, target: self, action: #selector(previousTapped))
        playPauseButton = MiniplayerButton(style: .primary, symbolName: "play.fill", pointSize: 14, target: self, action: #selector(playPauseTapped))
        nextButton = MiniplayerButton(style: .secondary, symbolName: "forward.end.fill", pointSize: 15, target: self, action: #selector(nextTapped))
        repeatButton = MiniplayerButton(style: .toggle, symbolName: "repeat", pointSize: 13, target: self, action: #selector(repeatTapped))
        shareButton = MiniplayerButton(style: .secondary, symbolName: "square.and.arrow.up", pointSize: 13, target: self, action: #selector(shareTapped))

        volumeButton.toolTip = "Volume"
        shuffleButton.toolTip = "Shuffle"
        previousButton.toolTip = "Previous"
        playPauseButton.toolTip = "Play"
        nextButton.toolTip = "Next"
        repeatButton.toolTip = "Repeat"
        shareButton.toolTip = "Copy link to song"

        // The slider comes out of the icon, rather than sitting under the
        // transport taking up room — which is how Spotify's works.
        volumeButton.onHoverChanged = { [weak self] hovering in
            self?.setVolumePopoverVisible(hovering)
        }

        transportRow.orientation = .horizontal
        transportRow.alignment = .centerY
        transportRow.spacing = 12
        transportRow.alphaValue = 0
        transportRow.translatesAutoresizingMaskIntoConstraints = false
        for button in [volumeButton!, shuffleButton!, previousButton!, playPauseButton!, nextButton!, repeatButton!, shareButton!] {
            transportRow.addArrangedSubview(button)
        }
        plate.addSubview(transportRow)
    }

    /// Covers the card entirely while open, the way Spotify's does — the
    /// settings are a mode, not a popover.
    private func buildSettingsPanel(in plate: NSView) {
        settingsPanel.isHidden = true
        settingsPanel.alphaValue = 0
        settingsPanel.onDone = { [weak self] in self?.setSettingsVisible(false) }
        settingsPanel.onBackgroundColorChanged = { [weak self] isOn in
            self?.onBackgroundColorChanged?(isOn)
        }
        plate.addSubview(settingsPanel)
        NSLayoutConstraint.activate([
            settingsPanel.leadingAnchor.constraint(equalTo: plate.leadingAnchor),
            settingsPanel.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            settingsPanel.topAnchor.constraint(equalTo: plate.topAnchor, constant: Self.chromeHeight),
            settingsPanel.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
        ])
    }

    func update(backgroundColorEnabled: Bool) {
        settingsPanel.update(backgroundColorEnabled: backgroundColorEnabled)
    }

    /// Switches the artwork tint on and off. With it off the panel is left the
    /// card's own near-black, which is what Spotify's "Background color" switch
    /// does to its miniplayer.
    func setBackgroundColorEnabled(_ enabled: Bool) {
        isBackgroundColorEnabled = enabled
        setAccent(enabled ? lastAccent : SpotifyPalette.base)
    }

    private func setSettingsVisible(_ visible: Bool) {
        settingsButton.isOn = visible
        guard visible else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                settingsPanel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { self.settingsPanel.isHidden = true }
            }
            return
        }
        settingsPanel.alphaValue = 0
        settingsPanel.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            settingsPanel.animator().alphaValue = 1
        }
    }

    private func buildVolumePopover(in plate: NSView) {
        volumePopover.wantsLayer = true
        volumePopover.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.98).cgColor
        volumePopover.layer?.cornerRadius = 8
        volumePopover.layer?.borderWidth = 1
        volumePopover.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        volumePopover.alphaValue = 0
        volumePopover.translatesAutoresizingMaskIntoConstraints = false
        // Staying open while the pointer is inside it is what makes the slider
        // reachable at all — leaving the icon would otherwise dismiss it
        // before the pointer ever arrived.
        volumePopover.onHoverChanged = { [weak self] hovering in
            self?.setVolumePopoverVisible(hovering)
        }
        plate.addSubview(volumePopover)

        volumeBar.maxValue = 100
        volumeBar.onScrub = { [weak self] _ in self?.refreshVolumeGlyph() }
        volumeBar.onCommit = { [weak self] value in
            self?.onVolumeChange?(Int(value))
            self?.refreshVolumeGlyph()
        }
        volumePopover.addSubview(volumeBar)

        NSLayoutConstraint.activate([
            volumeBar.leadingAnchor.constraint(equalTo: volumePopover.leadingAnchor, constant: 10),
            volumeBar.trailingAnchor.constraint(equalTo: volumePopover.trailingAnchor, constant: -10),
            volumeBar.centerYAnchor.constraint(equalTo: volumePopover.centerYAnchor),
            volumePopover.widthAnchor.constraint(equalToConstant: 110),
            volumePopover.heightAnchor.constraint(equalToConstant: 28),
            volumePopover.centerXAnchor.constraint(equalTo: volumeButton.centerXAnchor),
            volumePopover.bottomAnchor.constraint(equalTo: volumeButton.topAnchor, constant: -6),
        ])
    }

    /// Hides on a short delay so the pointer can cross the gap from icon to
    /// slider without the slider vanishing en route.
    private func setVolumePopoverVisible(_ visible: Bool) {
        volumeHideWork?.cancel()
        guard !visible else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                volumePopover.animator().alphaValue = 1
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self?.volumePopover.animator().alphaValue = 0
            }
        }
        volumeHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func buildProgressSection(in plate: NSView) {
        seekBar.onScrub = { [weak self] value in self?.refreshTimeLabels(position: value) }
        seekBar.onCommit = { [weak self] value in
            guard let self else { return }
            // Held so the next few reported positions — still the pre-seek ones
            // — don't yank the bar back to where it came from.
            self.pendingSeekTarget = value
            self.pendingSeekAt = Date()
            self.seekBar.value = value
            self.refreshTimeLabels(position: value)
            self.onSeek?(value)
        }

        style(elapsedLabel)
        style(remainingLabel)
        remainingLabel.alignment = .right

        let timesRow = NSStackView(views: [elapsedLabel, NSView(), remainingLabel])
        timesRow.orientation = .horizontal

        progressSection.orientation = .vertical
        progressSection.alignment = .leading
        progressSection.spacing = 0
        progressSection.alphaValue = 0
        progressSection.translatesAutoresizingMaskIntoConstraints = false
        // Times above the bar, the order Spotify's miniplayer uses.
        progressSection.addArrangedSubview(timesRow)
        progressSection.addArrangedSubview(seekBar)
        plate.addSubview(progressSection)

        NSLayoutConstraint.activate([
            seekBar.widthAnchor.constraint(equalTo: progressSection.widthAnchor),
            timesRow.widthAnchor.constraint(equalTo: progressSection.widthAnchor),
        ])
    }

    private func buildInfoBar(in plate: NSView) {
        lyricsButton = MiniplayerButton(style: .toggle, symbolName: "quote.bubble.fill", pointSize: 14, target: self, action: #selector(lyricsTapped))
        lyricsButton.toolTip = "Lyrics"

        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 0
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.addArrangedSubview(titleLabel)
        infoStack.addArrangedSubview(artistLabel)
        plate.addSubview(infoStack)
        plate.addSubview(lyricsButton)

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
            artistLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
        ])
    }

    private func buildConstraintSets(in plate: NSView) {
        let m = Self.margin

        portraitConstraints = [
            closeButton.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: chromeBackdrop.centerYAnchor),
            dotsHorizontal.centerXAnchor.constraint(equalTo: chromeBackdrop.centerXAnchor),
            dotsHorizontal.centerYAnchor.constraint(equalTo: chromeBackdrop.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -10),
            settingsButton.centerYAnchor.constraint(equalTo: chromeBackdrop.centerYAnchor),

            // The art runs from the top edge to the title. Neither the chrome nor
            // the progress bar takes a row of its own — both are laid over this
            // panel and faded in, so revealing them moves nothing.
            artPanel.topAnchor.constraint(equalTo: plate.topAnchor, constant: m),
            artPanel.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: m),
            artPanel.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -m),
            artPanel.bottomAnchor.constraint(equalTo: infoStack.topAnchor, constant: -10),

            transportRow.centerXAnchor.constraint(equalTo: artPanel.centerXAnchor),
            transportRow.centerYAnchor.constraint(equalTo: artPanel.centerYAnchor),

            // Sat on the deepest part of the scrim, which is exactly what that
            // dark bottom edge is for.
            progressSection.leadingAnchor.constraint(equalTo: artPanel.leadingAnchor, constant: 10),
            progressSection.trailingAnchor.constraint(equalTo: artPanel.trailingAnchor, constant: -10),
            progressSection.bottomAnchor.constraint(equalTo: artPanel.bottomAnchor, constant: -8),

            infoStack.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: m),
            infoStack.trailingAnchor.constraint(equalTo: lyricsButton.leadingAnchor, constant: -10),
            infoStack.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -m),
            lyricsButton.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -m),
            lyricsButton.centerYAnchor.constraint(equalTo: infoStack.centerYAnchor),
        ]

        // Band: chrome down the left edge, then art, title, and the transport
        // right-aligned — all on one line.
        bandConstraints = [
            closeButton.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: plate.topAnchor, constant: 8),
            dotsVertical.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
            dotsVertical.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),

            artPanel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 10),
            artPanel.topAnchor.constraint(equalTo: plate.topAnchor, constant: 6),
            artPanel.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -6),
            artPanel.widthAnchor.constraint(equalTo: artPanel.heightAnchor),

            infoStack.leadingAnchor.constraint(equalTo: artPanel.trailingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: transportRow.leadingAnchor, constant: -16),
            infoStack.centerYAnchor.constraint(equalTo: plate.centerYAnchor),

            transportRow.trailingAnchor.constraint(equalTo: lyricsButton.leadingAnchor, constant: -12),
            transportRow.centerYAnchor.constraint(equalTo: plate.centerYAnchor),

            lyricsButton.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -14),
            lyricsButton.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
        ]
    }

    /// Swaps arrangements. `force` is for the initial pass, where `isBand`
    /// already holds the value being applied.
    private func applyLayoutMode(band: Bool, force: Bool) {
        guard force || band != isBand else { return }
        isBand = band

        NSLayoutConstraint.deactivate(band ? portraitConstraints : bandConstraints)
        NSLayoutConstraint.activate(band ? bandConstraints : portraitConstraints)

        chromeBackdrop.isHidden = band
        dotsHorizontal.isHidden = band
        dotsVertical.isHidden = !band
        settingsButton.isHidden = band
        progressSection.isHidden = band
        transportRow.spacing = band ? 14 : 12

        refreshRevealedControls(animated: false)
    }

    /// Sheds controls the current size has no room for, and takes the lyrics
    /// button away entirely once the panel is too short to read lyrics in.
    private func refreshAvailableControls() {
        // Before the first real layout pass every subview measures zero, and
        // acting on that would hide the lyrics button on a card that has plenty
        // of room for it.
        guard bounds.width > 0, artPanel.bounds.height > 0 else { return }

        let width = bounds.width
        let showExtras = !isBand
        let hideShare = isBand && width < Self.widthForShare
        let hideRepeat = isBand && width < Self.widthForRepeat
        let hideShuffle = isBand && width < Self.widthForShuffle

        setHidden(shareButton, hideShare && !showExtras)
        setHidden(repeatButton, hideRepeat && !showExtras)
        setHidden(shuffleButton, hideShuffle && !showExtras)
        setHidden(volumeButton, isBand && width < Self.widthForShuffle)

        let canShowLyrics = lyricsAreaHeight >= LyricsViewScale.minimumUsableHeight
        guard canShowLyrics != lyricsAvailable else { return }
        lyricsAvailable = canShowLyrics
        lyricsButton.isHidden = !canShowLyrics
        // A card shrunk past the point of showing lyrics must not be left
        // stranded on the Lyrics view with no button to leave it.
        if !canShowLyrics, lyricsButton.isOn {
            onToggleLyrics?()
        }
    }

    /// Guarded so an unchanged value never dirties layout — this runs from
    /// `layout()`, and writing `isHidden` there unconditionally would loop.
    private func setHidden(_ view: NSView?, _ hidden: Bool) {
        guard let view, view.isHidden != hidden else { return }
        view.isHidden = hidden
    }

    // MARK: Helpers

    private func style(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = SpotifyPalette.textSubdued
        label.maximumNumberOfLines = 1
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Actions

    @objc private func playPauseTapped() { onTogglePlayPause?() }
    @objc private func previousTapped() { onSkipToPrevious?() }
    @objc private func nextTapped() { onSkipToNext?() }
    @objc private func lyricsTapped() { onToggleLyrics?() }
    @objc private func shuffleTapped() { onToggleShuffle?() }
    @objc private func repeatTapped() { onToggleRepeat?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func settingsTapped() { setSettingsVisible(!settingsButton.isOn) }

    /// Clicking the speaker mutes and un-mutes; the slider it reveals on hover
    /// is for everything in between.
    @objc private func volumeTapped() {
        let target = volumeBar.value == 0 ? 70.0 : 0
        volumeBar.value = target
        refreshVolumeGlyph()
        onVolumeChange?(Int(target))
    }
}

/// A panel that reports when the pointer is inside it — the volume slider needs
/// to stay up while being dragged, which means knowing the pointer arrived.
private final class HoverPanel: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    /// Invisible to clicks when hidden, so it never blocks the art beneath it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.1 ? nil : super.hitTest(point)
    }
}

/// Marks the views that must receive their own clicks. Everything else inside
/// the card — art, labels, empty space — lets the click through to the
/// `DraggableBackgroundView`, so dragging the Overlay still works from anywhere.
protocol OverlayInteractive: NSView {}
extension NSButton: OverlayInteractive {}
extension SpotifyProgressBar: OverlayInteractive {}
extension WindowResizer: OverlayInteractive {}

/// The container holding the miniplayer's controls. Passes clicks on anything
/// that isn't an `OverlayInteractive` straight through to the draggable
/// background behind it.
private final class ControlPlate: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        var view = hit
        while let current = view, current !== self {
            if current is OverlayInteractive { return hit }
            view = current.superview
        }
        return nil
    }
}
