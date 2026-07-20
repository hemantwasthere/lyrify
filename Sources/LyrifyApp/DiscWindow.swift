import AppKit

/// The Overlay's window, Minimized: a borderless, non-activating panel that
/// never takes keyboard focus, yet is draggable on the very first click —
/// no separate activation step first. See ADR-0006.
///
/// Deliberately untested — built and verified by hand.
final class DiscWindow: NSPanel {
    init(contentView: DiscView) {
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

        // The two settings that make this draggable with no activation tax:
        // moving the background moves the window, and mouse events aren't
        // swallowed before they reach it.
        isMovableByWindowBackground = true
        ignoresMouseEvents = false

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
