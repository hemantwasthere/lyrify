import AppKit

/// A view that drags its own window on a click-and-drag anywhere on it, and
/// calls `onClick` for a plain click — the disambiguation a non-activating
/// panel needs for itself, since `isMovableByWindowBackground` alone can't
/// tell a click from the start of a drag, and a click here means something
/// (expand or collapse the Overlay).
///
/// Tracks the gesture manually rather than relying on AppKit's own
/// background-drag handling, specifically so the two can be told apart: the
/// window's origin only moves once the pointer has travelled past a small
/// threshold, and `onClick` only fires when it never did.
///
/// Deliberately untested — AppKit event handling verified by hand.
class DraggableBackgroundView: NSView {
    var onClick: (() -> Void)?

    /// Below this many points of total movement, a mouseDown-then-up is a
    /// click, not the start of a drag.
    private static let dragThreshold: CGFloat = 3

    private var dragStartScreenLocation: NSPoint?
    private var windowOriginAtDragStart: NSPoint?
    private var didExceedDragThreshold = false

    override func mouseDown(with event: NSEvent) {
        dragStartScreenLocation = NSEvent.mouseLocation
        windowOriginAtDragStart = window?.frame.origin
        didExceedDragThreshold = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartScreenLocation, let windowOriginAtDragStart, let window else { return }

        let current = NSEvent.mouseLocation
        let delta = NSPoint(
            x: current.x - dragStartScreenLocation.x,
            y: current.y - dragStartScreenLocation.y
        )

        if !didExceedDragThreshold {
            guard abs(delta.x) > Self.dragThreshold || abs(delta.y) > Self.dragThreshold else { return }
            didExceedDragThreshold = true
        }

        window.setFrameOrigin(NSPoint(
            x: windowOriginAtDragStart.x + delta.x,
            y: windowOriginAtDragStart.y + delta.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if !didExceedDragThreshold {
            onClick?()
        }
        dragStartScreenLocation = nil
        windowOriginAtDragStart = nil
        didExceedDragThreshold = false
    }
}
