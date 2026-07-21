import AppKit

/// The Overlay's window: a borderless, non-activating, fixed-size panel
/// that never takes keyboard focus. See ADR-0006, and the ticket that
/// retired its old Minimized/Expanded two-state design in favor of one
/// fixed-size `OverlayCardView`.
///
/// Dragging is handled by the content view (`DraggableBackgroundView`), not
/// by `isMovableByWindowBackground` — that flag can't tell a click from the
/// start of a drag.
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
        // .floating, not .statusBar: the latter is the same level the real
        // system status-bar menus use, which makes macOS treat any window
        // there as "a menu is open" and dim every other status item for as
        // long as it's on screen. .floating still sits above regular
        // windows and, paired with .fullScreenAuxiliary below, still joins
        // a fullscreen app's Space — without that system-wide side effect.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
