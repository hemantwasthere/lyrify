import AppKit

/// Makes the Overlay resizable from every edge and corner, the way a native
/// window is, and shows the matching resize cursor on approach.
///
/// A borderless panel does technically accept edge drags, but its resize margin
/// is a couple of invisible points wide — which is why the card felt fixed. This
/// view lies over the whole card and claims only the outer `margin` points,
/// letting everything further in fall through to the controls beneath.
///
/// The diagonal resize cursors have no public API. They are looked up by
/// selector at runtime and fall back to the horizontal/vertical ones if a future
/// macOS stops vending them, so a missing cursor costs a nicety rather than the
/// gesture itself.
///
/// Note that the cursor only actually changes while Lyrify is the frontmost
/// application. macOS lets the active app decide what the pointer looks like,
/// and the Overlay is a non-activating panel that deliberately never becomes key
/// (ADR-0006) — so in the background the system keeps drawing the arrow no
/// matter what is set here. The resize gesture itself works regardless.
///
/// Deliberately untested — cursor and event handling verified by hand.
final class WindowResizer: NSView {
    /// How far in from the edge counts as a grab.
    private static let margin: CGFloat = 8

    var minimumSize = NSSize(width: 240, height: 62)
    var maximumSize = NSSize(width: 2000, height: 2000)

    /// Called on mouse-up so the owner can persist the new size.
    var onResized: (() -> Void)?

    private enum Edge: String {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private var activeEdge: Edge?
    private var initialFrame: NSRect = .zero
    private var dragOrigin: NSPoint = .zero

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Claims only the border ring; anything further in belongs to the controls
    /// underneath, so a click on the play button is never swallowed here.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return edge(at: local) == nil ? nil : self
    }

    private func edge(at point: NSPoint) -> Edge? {
        let m = Self.margin
        let nearLeft = point.x <= m
        let nearRight = point.x >= bounds.maxX - m
        // This view is flipped-agnostic: `bounds` is bottom-left origin, so
        // "top" here is the high-y edge, matching the window's own geometry.
        let nearBottom = point.y <= m
        let nearTop = point.y >= bounds.maxY - m

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    /// One tracking area per edge and corner, rather than one over the whole
    /// view with `.mouseMoved`.
    ///
    /// This window never becomes key, and macOS only generates mouse-moved and
    /// cursor-update events for the key window — `acceptsMouseMovedEvents` does
    /// nothing here. Enter and exit events *are* delivered to a `.activeAlways`
    /// tracking area regardless, so the border is carved into eight regions and
    /// the cursor is set as the pointer crosses into each. It is the same effect
    /// by the only route that actually reports.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        let m = Self.margin
        let w = bounds.width
        let h = bounds.height
        guard w > 2 * m, h > 2 * m else { return }

        let regions: [(Edge, NSRect)] = [
            (.bottomLeft, NSRect(x: 0, y: 0, width: m, height: m)),
            (.bottomRight, NSRect(x: w - m, y: 0, width: m, height: m)),
            (.topLeft, NSRect(x: 0, y: h - m, width: m, height: m)),
            (.topRight, NSRect(x: w - m, y: h - m, width: m, height: m)),
            (.left, NSRect(x: 0, y: m, width: m, height: h - 2 * m)),
            (.right, NSRect(x: w - m, y: m, width: m, height: h - 2 * m)),
            (.bottom, NSRect(x: m, y: 0, width: w - 2 * m, height: m)),
            (.top, NSRect(x: m, y: h - m, width: w - 2 * m, height: m)),
        ]

        for (edge, rect) in regions {
            addTrackingArea(NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["edge": edge.rawValue]
            ))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard activeEdge == nil,
              let raw = event.trackingArea?.userInfo?["edge"] as? String,
              let edge = Edge(rawValue: raw)
        else { return }
        cursor(for: edge).set()
    }

    override func mouseExited(with event: NSEvent) {
        // Leaving mid-resize must not reset the pointer out from under the drag.
        guard activeEdge == nil else { return }
        NSCursor.arrow.set()
    }

    private func cursor(for edge: Edge?) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return Self.diagonalCursor(rising: false)
        case .topRight, .bottomLeft: return Self.diagonalCursor(rising: true)
        case nil: return .arrow
        }
    }

    /// AppKit ships diagonal resize cursors but never exposed them. Asking for
    /// them by selector keeps the native look where they exist and degrades to a
    /// public cursor where they don't.
    private static func diagonalCursor(rising: Bool) -> NSCursor {
        let name = rising
            ? "_windowResizeNorthEastSouthWestCursor"
            : "_windowResizeNorthWestSouthEastCursor"
        let selector = NSSelectorFromString(name)
        if NSCursor.responds(to: selector),
           let cursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return rising ? .resizeLeftRight : .resizeUpDown
    }

    // Deliberately does not call `super`: these must not reach the draggable
    // background, or resizing would move the Overlay instead of sizing it.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        activeEdge = edge(at: convert(event.locationInWindow, from: nil))
        initialFrame = window.frame
        dragOrigin = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        // Only a drag that began on the border resizes: a stray drag whose
        // mouse-down landed elsewhere would otherwise size from a zero frame and
        // snap the card to its minimum. The button check rejects the other
        // shape of that bug — a drag delivered with nothing actually held down,
        // which silently resizes the card behind the listener's back.
        guard let activeEdge, let window, NSEvent.pressedMouseButtons & 0x1 == 0x1 else { return }

        let now = NSEvent.mouseLocation
        let dx = now.x - dragOrigin.x
        let dy = now.y - dragOrigin.y
        var frame = initialFrame

        // Screen coordinates put y at the bottom, so a "top" drag adds height
        // while a "bottom" drag both removes it and moves the origin.
        switch activeEdge {
        case .left, .topLeft, .bottomLeft:
            frame.origin.x += dx
            frame.size.width -= dx
        case .right, .topRight, .bottomRight:
            frame.size.width += dx
        case .top, .bottom:
            break
        }

        switch activeEdge {
        case .top, .topLeft, .topRight:
            frame.size.height += dy
        case .bottom, .bottomLeft, .bottomRight:
            frame.origin.y += dy
            frame.size.height -= dy
        case .left, .right:
            break
        }

        // Clamp, keeping whichever edge the listener is *not* dragging pinned.
        let width = min(max(frame.width, minimumSize.width), maximumSize.width)
        let height = min(max(frame.height, minimumSize.height), maximumSize.height)
        switch activeEdge {
        case .left, .topLeft, .bottomLeft:
            frame.origin.x = initialFrame.maxX - width
        default:
            frame.origin.x = initialFrame.minX
        }
        switch activeEdge {
        case .bottom, .bottomLeft, .bottomRight:
            frame.origin.y = initialFrame.maxY - height
        default:
            frame.origin.y = initialFrame.minY
        }
        frame.size = NSSize(width: width, height: height)

        // Every implicit Core Animation transition is switched off for the
        // duration of the drag. Without this each frame change starts its own
        // quarter-second animation, so the layers are still easing toward the
        // last position when the next drag event arrives — which is the lag and
        // rubber-banding that made resizing feel unlike a native window.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(frame, display: true)
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }

    override func mouseUp(with event: NSEvent) {
        guard activeEdge != nil else { return }
        activeEdge = nil
        onResized?()
    }
}

/// The diagonal hatch Spotify draws in the bottom-right corner. Purely a hint
/// that the card resizes — `WindowResizer` above does the work — so it refuses
/// clicks and lets them through to the resizer behind it.
final class ResizeGripGlyph: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 10),
            heightAnchor.constraint(equalToConstant: 10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineCapStyle = .round
        // Two short strokes rather than three long ones — Spotify's is a hint in
        // the corner, not a hatched panel.
        for offset in stride(from: CGFloat(3), through: 7, by: 4) {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 1.5))
            path.line(to: NSPoint(x: bounds.maxX - 1.5, y: bounds.minY + offset))
        }
        path.stroke()
    }
}
