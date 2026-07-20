import AppKit

/// The Overlay's Minimized form: a small circle showing the current Track's
/// album art, or a placeholder when none is known yet or none exists.
///
/// Deliberately untested — a rendering leaf with no decisions of its own.
final class DiscView: NSView {
    static let diameter: CGFloat = 56

    /// An `NSImageView` that never intercepts a click — every mouse-down
    /// must reach the window's background so `isMovableByWindowBackground`
    /// can start a drag, even one that begins right on the icon or the art.
    private final class PassthroughImageView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let imageView = PassthroughImageView()

    private static var placeholderImage: NSImage? {
        NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrify")?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
    }

    private static let placeholderTint = NSColor.white.withAlphaComponent(0.6)

    init() {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: Self.diameter, height: Self.diameter)))

        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Fills the disc exactly — the circular mask above clips whatever
        // doesn't fit, the same way a physical disc's label is cut round.
        // `.scaleProportionallyDown` never enlarges: the small placeholder
        // icon stays small and centered, while real album art (always
        // larger than 56pt) scales down to fill.
        imageView.image = Self.placeholderImage
        imageView.contentTintColor = Self.placeholderTint
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rotates the disc's artwork to `degrees` — `DiscRotation`'s current
    /// estimate, or its frozen angle while paused. The ring around it is
    /// circularly symmetric, so only the artwork needs to turn.
    func update(rotationDegrees: Double) {
        imageView.frameCenterRotation = CGFloat(rotationDegrees)
    }

    /// Shows real album art. No tint — the art speaks for itself.
    func updateArtwork(_ image: NSImage) {
        imageView.contentTintColor = nil
        imageView.image = image
    }

    /// Back to the placeholder — no artwork known yet for the current
    /// Track, or a confirmed no-artwork outcome.
    func updatePlaceholder() {
        imageView.contentTintColor = Self.placeholderTint
        imageView.image = Self.placeholderImage
    }
}
