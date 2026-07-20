import AppKit

/// The Overlay's window: a borderless, non-activating panel drawn at
/// status-bar level so it stays above ordinary windows, joins the listener
/// across every Space and fullscreen app, and never takes keyboard focus or
/// intercepts a click. See ADR-0004.
///
/// Deliberately untested — built and verified by hand; every decision it
/// draws comes from `LineSelection`, the tested core seam.
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
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
