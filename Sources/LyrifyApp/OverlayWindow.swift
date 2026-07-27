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
        // Without this the resize border never sees the pointer move over it,
        // and so never gets to change the cursor — cursor rects are no help
        // here, being consulted only for the key window, which this never is.
        acceptsMouseMovedEvents = true

        self.contentView = contentView
    }

    /// Swaps in `view` and resizes to match — `size` when given (a
    /// persisted card size on a fresh expand), otherwise `view`'s own frame
    /// size (the Disc's fixed size, or a first-launch default). Keeps the
    /// Overlay's center point fixed either way, so expanding or collapsing
    /// grows or shrinks in place rather than jumping, wherever it was
    /// dragged to.
    ///
    /// When `animated`, the window frame eases to its new size while the
    /// incoming view fades in — the grow/shrink between the Disc and the card
    /// that makes expanding and collapsing feel physical rather than snapping.
    func setContent(_ view: NSView, size: NSSize? = nil, animated: Bool = false) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let newSize = size ?? view.frame.size
        let newOrigin = NSPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        let newFrame = Self.clampedToScreen(NSRect(origin: newOrigin, size: newSize))

        guard animated else {
            contentView = view
            setFrame(newFrame, display: true)
            return
        }

        view.alphaValue = 0
        contentView = view
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(newFrame, display: true)
            view.animator().alphaValue = 1
        }
    }

    /// Nudges `frame` back onto the screen it is closest to, so the Overlay can
    /// never end up somewhere the listener can't see or reach it.
    ///
    /// This is not hypothetical: the Overlay remembers where it was dragged, but
    /// its *size* changes when the card's layout does. A position saved while
    /// the card was short leaves its bottom-left corner high up the screen, and
    /// a later, taller card grown from that same corner runs straight off the
    /// top edge — the whole Overlay silently invisible, with nothing on screen
    /// to drag back. Clamping on every content swap keeps a remembered position
    /// from outliving the size it made sense for.
    static func clampedToScreen(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }

        var clamped = frame
        // `max` last, so a card larger than the screen pins to the top-left
        // corner rather than being pushed off the opposite edge.
        clamped.origin.x = max(min(clamped.origin.x, visible.maxX - clamped.width), visible.minX)
        clamped.origin.y = max(min(clamped.origin.y, visible.maxY - clamped.height), visible.minY)
        return clamped
    }

    /// Only the Expanded card is user-resizable — the Minimized Disc is a
    /// fixed size. Toggled on expand/collapse rather than left on always.
    func setResizable(_ resizable: Bool) {
        styleMask = resizable
            ? [.borderless, .nonactivatingPanel, .resizable]
            : [.borderless, .nonactivatingPanel]
    }

    /// macOS lets only the window that can take key status decide what the
    /// pointer looks like over it, which is why the resize border could never
    /// change the cursor. Allowing key status costs nothing here: paired with
    /// `.nonactivatingPanel`, clicking this window does not activate Lyrify, so
    /// whatever the listener was typing into keeps the keyboard (ADR-0006).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
