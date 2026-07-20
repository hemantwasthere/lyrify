import AppKit

/// The Overlay's Minimized form: a small circle with a placeholder image.
/// Real album art replaces the placeholder in a later ticket; spinning with
/// playback in another.
///
/// Deliberately untested — a rendering leaf with no decisions of its own.
final class DiscView: NSView {
    static let diameter: CGFloat = 56

    /// An `NSImageView` that never intercepts a click — every mouse-down
    /// must reach the window's background so `isMovableByWindowBackground`
    /// can start a drag, even one that begins right on the icon.
    private final class PassthroughImageView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let imageView = PassthroughImageView()

    init() {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: Self.diameter, height: Self.diameter)))

        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        imageView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrify")
        imageView.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        let inset: CGFloat = 16
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.diameter - inset * 2),
            imageView.heightAnchor.constraint(equalToConstant: Self.diameter - inset * 2),
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
}
