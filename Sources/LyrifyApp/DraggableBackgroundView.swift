import AppKit

/// A view that drags its own window on a click-and-drag anywhere on it.
/// `isMovableByWindowBackground` alone would move the window on every
/// sub-threshold jitter of a plain click, so this tracks the gesture
/// manually instead: the window's origin only moves once the pointer has
/// travelled past a small threshold.
///
/// Deliberately untested — AppKit event handling verified by hand.
class DraggableBackgroundView: NSView {
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
        dragStartScreenLocation = nil
        windowOriginAtDragStart = nil
        didExceedDragThreshold = false
    }
}
