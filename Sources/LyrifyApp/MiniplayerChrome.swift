import AppKit

/// The window furniture Spotify's miniplayer wears: the red close dot and the
/// grid of drag dots. Neither exists in AppKit for a borderless panel, so both
/// are drawn here. Resizing lives in `WindowResizer`.
///
/// Deliberately untested — drawing and event-handling leaves, verified by hand.

/// The red dot in the chrome bar's corner. A real traffic light is not available
/// to a borderless panel, so this draws one and behaves like the only button
/// Spotify puts there.
final class CloseDotButton: NSButton {
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        wantsLayer = true
        toolTip = "Quit Lyrify"
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 12),
            heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    /// Invisible to clicks while faded out, matching the volume popover.
    ///
    /// This matters more in the band than it looks, and more than it did: the
    /// band's rail no longer reserves its width, so at rest this dot sits over
    /// the album art rather than in a gutter of its own — and AppKit hit-tests a
    /// fully transparent view like any other. Without this, grabbing the cover to
    /// drag the Overlay would quit Lyrify.
    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.1 ? nil : super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dot = bounds.insetBy(dx: 1, dy: 1)
        NSColor(srgbRed: 0.99, green: 0.35, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(ovalIn: dot).fill()

        // The × only appears under the pointer, the way a real traffic light's
        // glyph does.
        guard isHovering else { return }
        let inset = dot.insetBy(dx: 3.2, dy: 3.2)
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset.minX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: NSPoint(x: inset.minX, y: inset.maxY))
        cross.line(to: NSPoint(x: inset.maxX, y: inset.minY))
        cross.lineWidth = 1.3
        NSColor.black.withAlphaComponent(0.55).setStroke()
        cross.stroke()
    }
}

/// The grid of dots marking where the card can be grabbed. Spotify lays them out
/// wide across the chrome bar in its taller layouts and turns them on their side
/// when the card collapses to a band, so this does both.
///
/// Purely an affordance — the whole card is draggable — so it refuses clicks and
/// lets them fall through to the `DraggableBackgroundView` behind it.
final class DragDotsView: NSView {
    enum Orientation {
        /// Four across, two down — for the horizontal chrome bar.
        case horizontal
        /// Two across, four down — for the band layout's left edge.
        case vertical
    }

    private static let dotSize: CGFloat = 3.4
    private static let spacing: CGFloat = 4.4

    private let columns: Int
    private let rows: Int

    init(orientation: Orientation) {
        switch orientation {
        case .horizontal: (columns, rows) = (4, 2)
        case .vertical: (columns, rows) = (2, 4)
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let width = CGFloat(columns) * Self.dotSize + CGFloat(columns - 1) * Self.spacing
        let height = CGFloat(rows) * Self.dotSize + CGFloat(rows - 1) * Self.spacing
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        OverlayPalette.glyphRest.setFill()
        for row in 0..<rows {
            for column in 0..<columns {
                let origin = NSPoint(
                    x: CGFloat(column) * (Self.dotSize + Self.spacing),
                    y: CGFloat(row) * (Self.dotSize + Self.spacing)
                )
                NSBezierPath(ovalIn: NSRect(origin: origin, size: NSSize(width: Self.dotSize, height: Self.dotSize))).fill()
            }
        }
    }
}
