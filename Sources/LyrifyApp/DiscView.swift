import AppKit

/// The Overlay's Minimized form: a small circle showing the current Track's
/// album art, or a placeholder when none is known yet or none exists.
/// Dragging it moves the Overlay; clicking it (via `onClick`) expands to
/// the Now Playing card.
///
/// Deliberately untested — a rendering leaf with no decisions of its own.
final class DiscView: DraggableBackgroundView {
    static let diameter: CGFloat = 56

    private let imageView = SpinningArtworkView()

    /// Kept because `layout()` has to reapply it after resetting the frame.
    private var rotationDegrees: CGFloat = 0

    init() {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: Self.diameter, height: Self.diameter)))

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Fills the disc exactly — the circular mask above clips whatever
        // doesn't fit, the same way a physical disc's label is cut round.
        // `.scaleProportionallyDown` never enlarges: the small placeholder
        // icon stays small and centered, while real album art (always
        // larger than 56pt) scales down to fill.
        imageView.image = OverlayArtworkPlaceholder.image(pointSize: 20)
        imageView.isPlaceholder = true
        // Outside Auto Layout, frame set in `layout()`: it is the artwork's own
        // drawing that turns, so nothing here should be re-laid-out per frame.
        imageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(imageView)

        // The Disc's own size is pinned, not merely set as a frame.
        //
        // Album art is a 640pt `NSImageView` image, and an image view's
        // intrinsic content size is its image's. With the artwork pinned to
        // these edges and nothing holding the Disc itself, Auto Layout grew it
        // toward that intrinsic size the moment real art arrived — measured at
        // 154pt across. A `cornerRadius` of half the *intended* 56 on a 154pt
        // box is not a circle, it is a rounded square, which is exactly what
        // was on screen.
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
        ])
    }

    /// Keeps the mask a circle whatever size the Disc ends up.
    ///
    /// Belt and braces over the constraints above: a radius written once in
    /// `init` is a claim about a size that nothing enforced, and that claim is
    /// what silently became false. Deriving it from `bounds` cannot go stale.
    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2

        imageView.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rotates the disc's artwork to `degrees` — `DiscRotation`'s current
    /// estimate, or its frozen angle while paused. The ring around it is
    /// circularly symmetric, so only the artwork needs to turn.
    ///
    /// The artwork is drawn rotated rather than the view being rotated. Both
    /// `frameCenterRotation` and a layer transform were tried and neither holds:
    /// AppKit owns the frame of a laid-out view and the backing layer of a
    /// layer-backed one, so each was reset underneath the animation — leaving
    /// the cover shrunk to fit its own rotated bounding box, and at some angles
    /// not drawn at all.
    func update(rotationDegrees degrees: Double) {
        rotationDegrees = CGFloat(degrees)
        imageView.angle = rotationDegrees
    }

    /// Shows real album art. No tint — the art speaks for itself.
    func updateArtwork(_ image: NSImage) {
        imageView.isPlaceholder = false
        imageView.image = image
    }

    /// Back to the placeholder — no artwork known yet for the current
    /// Track, or a confirmed no-artwork outcome.
    func updatePlaceholder() {
        imageView.isPlaceholder = true
        imageView.image = OverlayArtworkPlaceholder.image(pointSize: 20)
    }
}

/// Draws the album art turned about its centre, filling the Disc.
///
/// A view of its own rather than an `NSImageView` because rotating a view is
/// what kept failing: the frame belongs to layout and the backing layer belongs
/// to AppKit, and whichever one carried the angle got reset. Drawing is the one
/// thing nothing else owns.
///
/// The art is drawn as a square of the Disc's full diameter. A square of side D
/// covers the inscribed circle of diameter D at *every* angle, so the cover
/// always reaches the rim; the corners sweep outside and the Disc's circular
/// mask cuts them, which is what a record label does.
private final class SpinningArtworkView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var angle: CGFloat = 0 { didSet { needsDisplay = true } }

    /// The placeholder is a small glyph, not a cover: it is drawn at its own
    /// size, centred and still, rather than blown up to the rim and spun.
    var isPlaceholder = false { didSet { needsDisplay = true } }

    /// The whole card is draggable, so this must not swallow the click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current else { return }

        guard !isPlaceholder else {
            let size = image.size
            image.draw(in: NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
            return
        }

        let side = min(bounds.width, bounds.height)
        context.saveGraphicsState()
        context.cgContext.translateBy(x: bounds.midX, y: bounds.midY)
        context.cgContext.rotate(by: angle * .pi / 180)
        image.draw(in: NSRect(x: -side / 2, y: -side / 2, width: side, height: side))
        context.restoreGraphicsState()
    }
}
