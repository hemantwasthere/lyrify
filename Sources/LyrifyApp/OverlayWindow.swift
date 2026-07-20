import AppKit

/// The Overlay's window, Minimized or Expanded: a borderless, non-activating
/// panel that never takes keyboard focus. See ADR-0006.
///
/// Dragging is handled by the content view (`DraggableBackgroundView`), not
/// by `isMovableByWindowBackground` — that flag can't tell a click from a
/// drag, and a click on this Overlay means something (expand or collapse).
///
/// Deliberately untested — built and verified by hand.
final class OverlayWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentView.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false

        self.contentView = contentView
    }

    /// Swaps in `view` and resizes to match — `size` when given (a
    /// persisted card size on a fresh expand), otherwise `view`'s own frame
    /// size (the Disc's fixed size, or a first-launch default). Keeps the
    /// Overlay's center point fixed either way, so expanding or collapsing
    /// grows or shrinks in place rather than jumping, wherever it was
    /// dragged to.
    func setContent(_ view: NSView, size: NSSize? = nil) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let newSize = size ?? view.frame.size
        let newOrigin = NSPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)

        contentView = view
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }

    /// Only the Expanded card is user-resizable — the Minimized Disc is a
    /// fixed size. Toggled on expand/collapse rather than left on always.
    func setResizable(_ resizable: Bool) {
        styleMask = resizable
            ? [.borderless, .nonactivatingPanel, .resizable]
            : [.borderless, .nonactivatingPanel]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
