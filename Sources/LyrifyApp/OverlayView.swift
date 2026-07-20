import AppKit
import LyrifyCore

/// The pill: Active Line prominent, Next Line dimmed below it, both centered
/// on a translucent rounded background. An Instrumental Gap shows a quiet
/// placeholder instead of stale words.
///
/// Deliberately untested — a rendering leaf with no decisions of its own;
/// every decision it draws comes from `LineSelection`.
final class OverlayView: NSView {
    static let size = NSSize(width: 480, height: 64)

    /// A quiet placeholder for an Instrumental Gap — never stale words.
    private static let instrumentalGapPlaceholder = "♪"

    private let activeLabel = NSTextField(labelWithString: "")
    private let nextLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = Self.size.height / 4

        configure(activeLabel, fontSize: 16, weight: .semibold)
        configure(nextLabel, fontSize: 13, weight: .regular)
        nextLabel.alphaValue = 0.55

        let stack = NSStackView(views: [activeLabel, nextLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let maxLabelWidth = Self.size.width - 32
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            activeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: maxLabelWidth),
            nextLabel.widthAnchor.constraint(lessThanOrEqualToConstant: maxLabelWidth),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ field: NSTextField, fontSize: CGFloat, weight: NSFont.Weight) {
        field.font = .systemFont(ofSize: fontSize, weight: weight)
        field.textColor = .white
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
    }

    func update(with content: LineSelection.Content) {
        switch content {
        case .instrumentalGap:
            activeLabel.stringValue = Self.instrumentalGapPlaceholder
            activeLabel.alphaValue = 0.5
            nextLabel.stringValue = ""

        case .lines(let active, let next):
            activeLabel.stringValue = active.text
            activeLabel.alphaValue = 1.0
            nextLabel.stringValue = next?.text ?? ""
        }
    }
}
