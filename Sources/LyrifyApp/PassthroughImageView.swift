import AppKit

/// An `NSImageView` that never intercepts a click — every mouse-down must
/// reach the `DraggableBackgroundView` hosting it, so it can tell a click
/// from a drag, even one that begins right on the image itself. Shared by
/// the Disc and the Now Playing card's background art.
final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
