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
    /// When `animated`, the two forms cross-dissolve into one another while the
    /// window grows or shrinks between them.
    ///
    /// The outgoing form is carried through the transition as a **snapshot**,
    /// laid over the incoming one and dissolved away. That is what makes this
    /// read as one thing changing shape. Swapping the content view outright and
    /// fading the newcomer up from nothing — which is what this did before —
    /// leaves the window empty for the whole resize, so the Disc appeared to
    /// materialise out of thin air at its new size rather than the card becoming
    /// it.
    ///
    /// A snapshot rather than the real outgoing view for two reasons: the live
    /// card would still hit-test while it faded, so a click mid-transition could
    /// land on a transport button that is visually on its way out; and an image
    /// stretches with the window, so the old content squashes into the new shape
    /// instead of being cropped by it.
    func setContent(_ view: NSView, size: NSSize? = nil, animated: Bool = false) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let newSize = size ?? view.frame.size
        let newOrigin = NSPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        let newFrame = Self.clampedToScreen(NSRect(origin: newOrigin, size: newSize))

        guard animated, let ghost = contentView.map(Self.ghost(of:)) ?? nil else {
            contentView = view
            setFrame(newFrame, display: true)
            return
        }

        // The incoming form is fully opaque from the first frame; the ghost on
        // top of it is what the dissolve acts on. Fading both at once would dip
        // the whole Overlay translucent through the middle of the transition and
        // show the desktop through it.
        view.alphaValue = 1
        contentView = view
        ghost.frame = view.bounds
        ghost.autoresizingMask = [.width, .height]
        view.addSubview(ghost)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.transitionDuration
            // Leaves quickly and settles slowly, so the size lands before the
            // eye goes looking for detail in the new form.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.24, 1)
            animator().setFrame(newFrame, display: true)
            ghost.animator().alphaValue = 0
        } completionHandler: {
            // The handler is nonisolated; AppKit runs it on the main thread.
            // Same assumption `NowPlayingView` makes for its own completions.
            MainActor.assumeIsolated { ghost.removeFromSuperview() }
        }
    }

    /// Slightly longer than the 0.26 this used to run at. The extra time is what
    /// makes the change of shape legible rather than a flicker; much beyond this
    /// and it starts to feel slow to answer a click.
    private static let transitionDuration: TimeInterval = 0.34

    /// A still of `view` as it looks right now, in a view that refuses clicks.
    private static func ghost(of view: NSView) -> NSImageView? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }

        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)

        let ghost = PassthroughImageView()
        ghost.image = image
        // Stretches with the window rather than holding its shape, so the card
        // squashes down into the Disc instead of being cropped by its mask.
        ghost.imageScaling = .scaleAxesIndependently
        return ghost
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
