import AppKit

/// An `NSTextField` label that never intercepts a click — every mouse-down
/// must reach the `DraggableBackgroundView` hosting it, so it can tell a
/// click from a drag, even one that begins right on the text itself. See
/// `PassthroughImageView`, its counterpart for artwork.
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
