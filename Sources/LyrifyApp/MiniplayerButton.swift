import AppKit

/// A control in the miniplayer's transport row, with Spotify's own hover
/// behaviour: the secondary buttons sit subdued and brighten to white under the
/// pointer, the play button is a white disc that swells slightly, and the
/// shuffle and repeat toggles turn green while they are on.
///
/// AppKit gives `NSButton` no hover state at all, so each button carries its own
/// tracking area and repaints itself — the same reason `SpotifyProgressBar`
/// draws itself rather than wrapping `NSSlider`.
///
/// Deliberately untested — an event-handling and drawing leaf, verified by hand.
final class MiniplayerButton: NSButton {
    enum Style {
        /// Previous / next / lyrics: subdued, brightening on hover.
        case secondary
        /// Play-pause: a white disc with a black glyph.
        case primary
        /// Shuffle / repeat: subdued, green while on.
        case toggle
    }

    /// Only meaningful for `.toggle`; lights the button green while true.
    var isOn = false {
        didSet { refreshAppearance() }
    }

    /// Fires as the pointer enters and leaves. The volume button uses it to
    /// bring its slider out, the way Spotify's does.
    var onHoverChanged: ((Bool) -> Void)?

    private let style: Style
    private let symbolPointSize: CGFloat
    private var symbolName: String
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    init(style: Style, symbolName: String, pointSize: CGFloat, target: AnyObject?, action: Selector) {
        self.style = style
        self.symbolName = symbolName
        self.symbolPointSize = pointSize
        super.init(frame: .zero)

        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        if case .primary = style {
            let diameter: CGFloat = 40
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.cornerRadius = diameter / 2
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: diameter),
                heightAnchor.constraint(equalToConstant: diameter),
            ])
        }

        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Swaps the glyph — play to pause, and back.
    func setSymbol(_ name: String) {
        symbolName = name
        refreshAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // `.activeAlways`: the Overlay's panel never becomes key, so hover has
        // to work without it.
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
        refreshAppearance()
        setScale(style == .primary ? 1.06 : 1.0)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshAppearance()
        setScale(1.0)
        onHoverChanged?(false)
    }

    /// Scales about the centre — the default anchor is the bottom-left corner,
    /// which would make the play disc lurch sideways instead of swelling.
    private func setScale(_ scale: CGFloat) {
        guard let layer else { return }
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private func refreshAppearance() {
        let color: NSColor
        switch style {
        case .primary:
            color = .black
        case .secondary:
            color = isHovering ? SpotifyPalette.textPrimary : SpotifyPalette.glyphRest
        case .toggle:
            color = isOn
                ? SpotifyPalette.green
                : (isHovering ? SpotifyPalette.textPrimary : SpotifyPalette.glyphRest)
        }

        // Outline glyphs take their weight from the stroke, so `.ultraLight`
        // genuinely thins them — on the filled variants they were drawn from
        // before it did almost nothing, which is why they stayed looking heavy
        // however light the weight was set. The play glyph keeps its fill, since
        // it sits on a white disc and an outline would vanish there.
        let weight: NSFont.Weight = style == .primary ? .regular : .ultraLight
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: weight)
            .applying(.init(paletteColors: [color]))
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
