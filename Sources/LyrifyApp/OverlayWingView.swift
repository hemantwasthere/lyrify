import AppKit

/// One wing of the notch-straddling Overlay: a single line of text on the
/// same translucent dark background as the pill, sized to fill a notch's
/// safe margin so it merges visually with the notch itself. See ADR-0004.
///
/// Deliberately untested — a rendering leaf with no decisions of its own.
final class OverlayWingView: NSView {
    private let label = NSTextField(labelWithString: "")

    /// `.leading` for the left margin (text hugs the notch), `.trailing` for
    /// the right (text hugs the notch from the other side).
    enum Side {
        case left
        case right
    }

    init(side: Side) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = side == .left ? .right : .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let inset: CGFloat = 8
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.height / 2, 12)
    }

    func update(text: String, alpha: CGFloat) {
        label.stringValue = text
        label.alphaValue = alpha
    }
}
