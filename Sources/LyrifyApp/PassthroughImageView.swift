import AppKit

/// An `NSImageView` that never intercepts a click — every mouse-down must
/// reach the `DraggableBackgroundView` hosting it, so it can tell a click
/// from a drag, even one that begins right on the image itself. Shared by
/// the Disc and the Now Playing card's background art.
///
/// Also keeps its layer's rotation pivot centered on itself. AppKit gives a
/// layer-backed view's `CALayer` an `anchorPoint` of (0, 0), not the (0.5,
/// 0.5) a plain `CALayer` defaults to, so the Disc's rotation transform
/// (`OverlayCardView.update(rotationDegrees:)`) would otherwise orbit
/// around the view's corner rather than spin in place. Corrected in
/// `setFrameOrigin`/`setFrameSize` rather than `layout()`: AppKit only
/// invokes `layout()` when a view has its own subviews to place, so a
/// childless leaf like this one never gets called back there when Auto
/// Layout moves or resizes it — confirmed by instrumenting a throwaway
/// harness, since it's exactly the case ADR-0008 already got bitten by
/// once with `NSView.frameCenterRotation`. `setFrameOrigin`/`setFrameSize`
/// fire on every relayout regardless, which is what re-settling the
/// anchor point after the transform is already applied actually needs.
final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        centerLayerAnchor()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        centerLayerAnchor()
    }

    private func centerLayerAnchor() {
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
    }
}
