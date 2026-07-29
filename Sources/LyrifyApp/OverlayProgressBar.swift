import AppKit

/// The Overlay's progress bar, drawn rather than borrowed from AppKit: a thin
/// fully rounded track with a filled portion, which on hover takes the accent
/// colour and grows a circular knob at the fill's end. Used for both the seek
/// bar and the volume bar, which behave identically.
///
/// Modelled on Spotify's, but nothing here is Spotify's — it is a drawing leaf
/// with no knowledge of any player, which is why it is named for the Overlay.
///
/// `NSSlider` was the obvious thing to reach for and is the wrong shape
/// entirely — it draws a macOS track and thumb that no amount of tinting turns
/// into this.
///
/// Scrubbing reports twice, matching the commit-on-release rule the whole
/// Overlay follows: `onScrub` fires continuously so labels can follow the
/// gesture, while `onCommit` fires only on mouse-up, so one drag sends one
/// AppleScript command rather than one per pixel crossed. `isDragging` lets the
/// owner ignore external updates mid-gesture, so a redraw never fights the
/// listener's cursor.
///
/// Deliberately untested — a drawing and event-handling leaf, verified by hand.
final class OverlayProgressBar: NSView {
    /// Continuous, while dragging — for live time labels.
    var onScrub: ((Double) -> Void)?
    /// Once, on release — the only point a real command is sent.
    var onCommit: ((Double) -> Void)?

    var minValue: Double = 0
    var maxValue: Double = 1 {
        didSet { needsDisplay = true }
    }

    var value: Double = 0 {
        didSet { needsDisplay = true }
    }

    private(set) var isDragging = false
    private var isHovering = false

    private static let barHeight: CGFloat = 4
    private static let knobDiameter: CGFloat = 12

    /// Tall enough to be an easy target even though the bar itself is 4pt —
    /// Spotify's is likewise far easier to hit than it looks.
    static let hitHeight: CGFloat = 16

    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.hitHeight).isActive = true
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
        // `.activeAlways`, not `.activeInKeyWindow`: the Overlay's panel never
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
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    // Deliberately does not call `super`: these events must not reach the
    // `DraggableBackgroundView` behind this bar, or scrubbing would drag the
    // whole Overlay and a click would collapse it.
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateValue(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(from: event)
        isDragging = false
        needsDisplay = true
        onCommit?(value)
    }

    private func updateValue(from event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let fraction = max(0, min(1, x / max(bounds.width, 1)))
        value = minValue + fraction * (maxValue - minValue)
        onScrub?(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        let span = maxValue - minValue
        let fraction = span > 0 ? max(0, min(1, (value - minValue) / span)) : 0

        // The bar sits centred in the taller hit area.
        let barY = (bounds.height - Self.barHeight) / 2
        let trackRect = NSRect(x: 0, y: barY, width: bounds.width, height: Self.barHeight)
        let radius = Self.barHeight / 2

        OverlayPalette.barTrack.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        let fillWidth = bounds.width * CGFloat(fraction)
        if fillWidth > 0 {
            let fillRect = NSRect(x: 0, y: barY, width: fillWidth, height: Self.barHeight)
            // Green while hovered or scrubbing, white at rest — Spotify's exact
            // affordance for "this bar is grabbable."
            let active = isHovering || isDragging
            (active ? OverlayPalette.accent : OverlayPalette.textPrimary).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
        }

        guard isHovering || isDragging else { return }
        let knobRect = NSRect(
            x: fillWidth - Self.knobDiameter / 2,
            y: (bounds.height - Self.knobDiameter) / 2,
            width: Self.knobDiameter,
            height: Self.knobDiameter
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }
}
