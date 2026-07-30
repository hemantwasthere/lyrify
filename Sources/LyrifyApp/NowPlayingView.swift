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

    /// Spotify runs the artwork panel almost to the card edge — a hairline of
    /// black, not a border.
    private static let panelMargin: CGFloat = 5

    /// The title and artist are inset much further than the panel is. Using one
    /// margin for both made the panel look fat and the title cramped at once.
    private static let textMargin: CGFloat = 18
    /// The black strip Spotify leaves above its artwork, which the chrome
    /// bar's controls fade into.
    private static let chromeHeight: CGFloat = 28

    /// How far the band's artwork sits from the leading edge with the pointer
    /// away, and with it present.
    ///
    /// The band's rail — the close dot above the drag dots — used to hold the
    /// wider of these permanently, even though both controls are fully
    /// transparent until pointed at. That left an unexplained empty gutter
    /// before the album art on a widget whose whole point is being small. The
    /// space is opened on hover instead, which is the same bargain the chrome
    /// bar strikes in portrait.
    private static let bandArtInsetAtRest: CGFloat = 6
    /// 8 to the close dot, its own 12, then 10 of air before the art.
    private static let bandArtInsetWhenRevealed: CGFloat = 30

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

    private let artPanel = ArtworkPanelView()
    private let scrimLayer = CAGradientLayer()
    private let chromeBackdrop = NSView()
    private let artView = PassthroughImageView()
    private let lyricsView = LyricsCardView()
    private let scrim = NSView()
    private let transportRow = NSStackView()
    private let progressSection = NSStackView()
    private let infoStack = NSStackView()
    private let volumePopover = HoverPanel()
    private let settingsPanel = MiniplayerSettingsView()
    private let titleLabel = MarqueeLabel(font: .systemFont(ofSize: 16, weight: .bold), color: OverlayPalette.textPrimary)
    private let artistLabel = MarqueeLabel(font: .systemFont(ofSize: 12, weight: .regular), color: OverlayPalette.textSubdued)
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let remainingLabel = NSTextField(labelWithString: "0:00")
    private let seekBar = OverlayProgressBar()
    private let volumeBar = OverlayProgressBar()
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
    private var railSlide: NSLayoutConstraint!
    private var artTop: NSLayoutConstraint!
    private var isBand = false
    private var isHovering = false
    private var lyricsAvailable = true

    /// The tint the current artwork asks for, remembered even while the
    /// background-colour switch is off, so turning it back on does not have to
    /// wait for the next Track.
    private var lastTint = OverlayPalette.fallbackTint
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
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.backgroundColor = OverlayPalette.base.cgColor
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
        refreshPanelMask(animated: false)
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

    /// Reshapes the artwork's clip so its visible top edge meets the foot of the
    /// chrome bar, rounded, while the bar is showing — and runs back up to the
    /// panel's own top when it goes. The panel's frame never changes, so the
    /// cover neither moves nor resizes; only what is drawn of it does.
    private func refreshPanelMask(animated: Bool) {
        artPanel.topCut = (isHovering && !isBand) ? Self.chromeHeight - Self.panelMargin : 0
        artPanel.reshape(animated: animated)
    }

    /// Portrait hides the transport behind the art until pointed at; the band
    /// keeps its controls on show, having nothing to hide them behind.
    private func refreshRevealedControls(animated: Bool) {
        refreshPanelMask(animated: animated)
        let revealed = isHovering
        let apply = {
            // The strip the chrome lives in is always there — it is just the
            // card's own black showing above the art — so nothing moves when the
            // controls arrive. They ease down into it from a few points higher,
            // which is the whole of Spotify's animation; sliding a black panel
            // down over black was only ever invisible work.
            self.chromeSlide.animator().constant = revealed ? 0 : -8
            // The band has nothing to hide its rail behind — the art is barely
            // larger than the rail itself — so rather than fading controls onto
            // the cover it makes room for them and gives it back. Only the art
            // and the title move; the transport is anchored to the trailing
            // edge, so the title loses this width while the pointer is present.
            self.railSlide.animator().constant = revealed
                ? Self.bandArtInsetWhenRevealed
                : Self.bandArtInsetAtRest
            self.chromeBackdrop.animator().alphaValue = revealed ? 1 : 0
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
        lastTint = OverlayPalette.tint(from: image)
        setTint(isBackgroundColorEnabled ? lastTint : OverlayPalette.base)
    }

    func updatePlaceholder() {
        artView.contentTintColor = OverlayArtworkPlaceholder.tint
        artView.image = OverlayArtworkPlaceholder.image(pointSize: 34)
        // Honours the switch like `updateArtwork` does. It didn't before, so with
        // the switch off a Track whose cover failed to load tinted the card anyway.
        setTint(isBackgroundColorEnabled ? OverlayPalette.fallbackTint : OverlayPalette.base)
    }

    /// Cross-fades the tint rather than cutting to it, so a Track change eases
    /// into its new colour.
    ///
    /// The colour goes on the card itself as well as the panel, and both stops of
    /// the gradient are the same, because Spotify's card is one flat colour edge
    /// to edge. Scanned top to bottom it reads rgb(102, 0, 17) at every row —
    /// through the chrome strip, past the cover, and behind the title. The panel
    /// used to carry a graded wash while the card stayed black around it, which
    /// left a dark band above and below the tint that Spotify simply does not
    /// have. The gradient layer stays rather than being torn out: it is what
    /// cross-fades, and a flat two-stop gradient is the cheapest way to keep that.
    private func setTint(_ color: NSColor) {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.duration = 0.45
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        artPanel.gradient.add(animation, forKey: "colors")
        artPanel.gradient.colors = [color.cgColor, color.cgColor]

        let cardFade = CABasicAnimation(keyPath: "backgroundColor")
        cardFade.duration = 0.45
        cardFade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(cardFade, forKey: "backgroundColor")
        layer?.backgroundColor = color.cgColor

        // The chrome bar and the scrim are part of the card, so they take the
        // colour too — they were left black, which put a black strip along the top
        // and a black wash over the middle of a tinted card. Spotify's are neither.
        chromeBackdrop.layer?.add(cardFade, forKey: "backgroundColor")
        chromeBackdrop.layer?.backgroundColor = color.cgColor
        setScrimBase(color)
    }

    /// Rebuilds the scrim from `color`, keeping the alpha ramp that makes it work.
    ///
    /// Safe to hand the artwork's tint rather than black because that tint is held
    /// to a fixed dark luminance by `ArtworkTint` — there is no cover bright enough
    /// to turn this into a pale sheet the white glyphs would disappear into.
    private func setScrimBase(_ color: NSColor) {
        scrimLayer.colors = [0.30, 0.38, 0.56, 0.78, 0.94].map {
            color.withAlphaComponent($0).cgColor
        }
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
        case ..<1: name = "speaker.slash"
        case ..<34: name = "speaker"
        case ..<67: name = "speaker.wave.1"
        default: name = "speaker.wave.2"
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
        // Flat, and both stops the same, for the reason `setTint` gives.
        artPanel.gradient.colors = [OverlayPalette.fallbackTint.cgColor, OverlayPalette.fallbackTint.cgColor]
        // A layer's y axis runs upward, so (0.5, 1) is the *top*. Starting at 0
        // put the first colour at the bottom and rendered both of these gradients
        // upside down — the tint pooling at the bottom and the scrim at its
        // darkest across the top of the cover.
        artPanel.gradient.startPoint = CGPoint(x: 0.5, y: 1)
        artPanel.gradient.endPoint = CGPoint(x: 0.5, y: 0)
        artPanel.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(artPanel)

        artView.wantsLayer = true
        artView.layer?.cornerRadius = 8
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
        setScrimBase(OverlayPalette.base)
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
        let fitWidth = artView.widthAnchor.constraint(lessThanOrEqualTo: artPanel.widthAnchor, constant: -12)
        let fitHeight = artView.heightAnchor.constraint(lessThanOrEqualTo: artPanel.heightAnchor, constant: -12)
        // Measured off Spotify: the cover takes about 85% of the panel's height
        // and a little over half its width, leaving the wash visible all around
        // it. Ours filled the panel to within 8pt, which is why the cover looked
        // so much larger at the same card width.
        let growWidth = artView.widthAnchor.constraint(equalTo: artPanel.heightAnchor, multiplier: 0.85)
        let growHeight = artView.heightAnchor.constraint(equalTo: artPanel.heightAnchor, multiplier: 0.85)
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
        // The chrome brings its own black backing, rounded to meet the card's top
        // corners, rather than relying on whatever is behind it: it is laid over
        // the artwork now, so without this the buttons would sit on the cover.
        chromeBackdrop.wantsLayer = true
        chromeBackdrop.layer?.backgroundColor = NSColor.black.cgColor
        // Flush with the card: rounded at the head to follow the card's own
        // corners, square at the foot. The curve at the join belongs to the
        // artwork beneath, which rounds *away* from the bar — rounding the bar's
        // own foot instead curved it the opposite way and left it looking like a
        // detached pill lying on the cover.
        chromeBackdrop.layer?.cornerRadius = 14
        chromeBackdrop.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        chromeBackdrop.layer?.masksToBounds = true
        chromeBackdrop.alphaValue = 0
        chromeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(chromeBackdrop)

        closeButton = CloseDotButton(target: self, action: #selector(closeTapped))
        settingsButton = MiniplayerButton(style: .toggle, symbolName: "slider.horizontal.3", pointSize: 14, target: self, action: #selector(settingsTapped))
        settingsButton.toolTip = "Miniplayer settings"

        let chromePieces: [NSView] = [closeButton, dotsHorizontal, dotsVertical, settingsButton]
        for view in chromePieces {
            view.alphaValue = 0
            plate.addSubview(view)
        }

        // The controls ease down into the strip; the constant is animated rather
        // than the alpha alone, so they arrive rather than simply appear.
        chromeSlide = chromeBackdrop.topAnchor.constraint(equalTo: plate.topAnchor, constant: -8)
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
        volumeButton = MiniplayerButton(style: .secondary, symbolName: "speaker.wave.2", pointSize: 15, target: self, action: #selector(volumeTapped))
        shuffleButton = MiniplayerButton(style: .toggle, symbolName: "shuffle", pointSize: 15, target: self, action: #selector(shuffleTapped))
        previousButton = MiniplayerButton(style: .secondary, symbolName: "backward.end.fill", pointSize: 16, target: self, action: #selector(previousTapped))
        playPauseButton = MiniplayerButton(style: .primary, symbolName: "play.fill", pointSize: 13, target: self, action: #selector(playPauseTapped))
        nextButton = MiniplayerButton(style: .secondary, symbolName: "forward.end.fill", pointSize: 16, target: self, action: #selector(nextTapped))
        repeatButton = MiniplayerButton(style: .toggle, symbolName: "repeat", pointSize: 15, target: self, action: #selector(repeatTapped))
        shareButton = MiniplayerButton(style: .secondary, symbolName: "square.and.arrow.up", pointSize: 15, target: self, action: #selector(shareTapped))

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

    /// Switches the artwork tint on and off.
    ///
    /// Off means black, measured: Spotify's card with its "Background color"
    /// switch down is rgb(0, 0, 0) everywhere. This used to keep the wash and
    /// merely strip its hue, on the belief that Spotify did the same — it does
    /// not, and since the wash was also far too bright, turning the switch off
    /// swapped a coloured panel for a light grey one instead of putting it away.
    func setBackgroundColorEnabled(_ enabled: Bool) {
        isBackgroundColorEnabled = enabled
        setTint(enabled ? lastTint : OverlayPalette.base)
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
        lyricsButton = MiniplayerButton(style: .toggle, symbolName: "quote.bubble.fill", pointSize: 15, target: self, action: #selector(lyricsTapped))
        lyricsButton.toolTip = "Lyrics"

        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 0
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        // Hug the two labels harder than the default 250, or a tall card breaks.
        //
        // Portrait chains the plate's top edge through the art panel, this
        // stack, and back to the plate's bottom. Two of those can stretch, so
        // one of them has to be the one that yields. The panel looks like the
        // obvious candidate — it has no intrinsic height at all — but the low
        // priority `grow` constraints in `buildArtPanel` are equalities, and
        // combined with the required square cover and its width cap they pull
        // the panel's height toward roughly 1.18x its width. At the default 250
        // that pull ties with this stack's hugging, and the solver broke the tie
        // the wrong way: past that height the stack absorbed every extra point,
        // packed its labels at the top, and left a growing slab of dead card
        // below them — with the lyrics button, which centres on this stack,
        // drifting further from the title it belongs beside.
        //
        // Raising this above the pull settles the tie for good. Nothing changes
        // at the default size, where the pull is not binding.
        infoStack.setHuggingPriority(.defaultHigh, for: .vertical)
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
        let pm = Self.panelMargin
        let tm = Self.textMargin
        // The same inset as the left and right edges, always. Nothing is held
        // open above the artwork; the curve under the bar comes from clipping,
        // not from moving this edge down. See `refreshPanelMask`.
        artTop = artPanel.topAnchor.constraint(equalTo: plate.topAnchor, constant: pm)
        // Starts closed. `refreshRevealedControls` opens it when the pointer
        // arrives, and `applyLayoutMode` calls that unanimated on every switch,
        // so entering the band with the pointer already inside still makes room.
        railSlide = artPanel.leadingAnchor.constraint(
            equalTo: plate.leadingAnchor,
            constant: Self.bandArtInsetAtRest
        )

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
            artTop,
            artPanel.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: pm),
            artPanel.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -pm),
            artPanel.bottomAnchor.constraint(equalTo: infoStack.topAnchor, constant: -8),

            transportRow.centerXAnchor.constraint(equalTo: artPanel.centerXAnchor),
            transportRow.centerYAnchor.constraint(equalTo: artPanel.centerYAnchor),

            // Sat on the deepest part of the scrim, which is exactly what that
            // dark bottom edge is for.
            progressSection.leadingAnchor.constraint(equalTo: artPanel.leadingAnchor, constant: 10),
            progressSection.trailingAnchor.constraint(equalTo: artPanel.trailingAnchor, constant: -10),
            progressSection.bottomAnchor.constraint(equalTo: artPanel.bottomAnchor, constant: -8),

            infoStack.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: tm),
            infoStack.trailingAnchor.constraint(equalTo: lyricsButton.leadingAnchor, constant: -10),
            infoStack.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -14),
            lyricsButton.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -tm),
            lyricsButton.centerYAnchor.constraint(equalTo: infoStack.centerYAnchor),
        ]

        // Band: chrome down the left edge, then art, title, and the transport
        // right-aligned — all on one line.
        bandConstraints = [
            closeButton.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: plate.topAnchor, constant: 8),
            dotsVertical.centerXAnchor.constraint(equalTo: closeButton.centerXAnchor),
            dotsVertical.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),

            // Anchored to the plate rather than to the close dot, so the rail's
            // width is something this constant grants on hover rather than
            // something the layout owes it permanently. See `railSlide`.
            railSlide,
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
        label.textColor = OverlayPalette.textSubdued
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
///
/// Conformance is the whole of what makes a control clickable here, so anything
/// added to the card that is not an `NSButton` has to be listed. `ToggleSwitch`
/// was not, and that is exactly why the "Background color" switch could not be
/// clicked: `hitTest` found it, walked up looking for a conformer, found none,
/// and returned nil so the click fell through to the drag handler. Every other
/// control on the card happens to be an `NSButton`, which is why this went
/// unnoticed — the switch was the only thing here that wasn't one.
protocol OverlayInteractive: NSView {}
extension NSButton: OverlayInteractive {}
extension OverlayProgressBar: OverlayInteractive {}
extension WindowResizer: OverlayInteractive {}
extension ToggleSwitch: OverlayInteractive {}

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


/// The tinted panel the cover sits on, which clips itself.
///
/// The clip is what lets the artwork keep the same inset at the top that it has
/// at the sides while still showing a curve under the chrome bar: rather than
/// moving the panel down to make room — which would resize the cover every time
/// the pointer arrived — the panel stays put and simply stops being drawn where
/// the bar covers it, rounding off at that edge instead.
///
/// It reshapes in its *own* `layout()`, not its parent's. A parent lays out
/// before its children have their final bounds, so a mask built up there is
/// sized from stale numbers — and on the first pass from zero, which masks the
/// panel away entirely.
///
/// Deliberately untested — a drawing leaf, verified by hand.
final class ArtworkPanelView: NSView {
    let gradient = CAGradientLayer()

    /// How much of the panel's top is currently covered by the chrome bar.
    var topCut: CGFloat = 0

    private let clip = CAShapeLayer()
    private var currentPath: CGPath?
    private static let cornerRadius: CGFloat = 13

    init() {
        super.init(frame: .zero)
        gradient.mask = clip
        layer = gradient
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        reshape(animated: false)
    }

    func reshape(animated: Bool) {
        guard bounds.width > 0, bounds.height > topCut else { return }

        // Layer coordinates put y at the bottom, so trimming the top means
        // shortening the rectangle rather than offsetting it.
        let rect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - topCut)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: Self.cornerRadius,
            cornerHeight: Self.cornerRadius,
            transform: nil
        )
        guard path != currentPath else { return }

        if animated, let currentPath {
            let slide = CABasicAnimation(keyPath: "path")
            slide.fromValue = currentPath
            slide.toValue = path
            slide.duration = 0.2
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.add(slide, forKey: "path")
        }
        clip.path = path
        currentPath = path
    }
}
