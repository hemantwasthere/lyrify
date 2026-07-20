import AppKit
import LyrifyCore

/// The Overlay's Lyrics view: the Active Line prominent, the Next Line
/// dimmed below it, exactly like the retired Overlay drew them — plus two
/// cases that never needed drawing before, since the retired Overlay simply
/// hid itself for them: "nothing playing" and the Idle State's honest
/// "no lyrics" naming.
///
/// Deliberately untested — a rendering leaf with no decisions of its own;
/// every decision it draws comes from `OverlayDisplay` and `LineSelection`.
final class LyricsCardView: NSView {
    /// A quiet placeholder for an Instrumental Gap — never stale words.
    private static let instrumentalGapPlaceholder = "♪"

    private static let idleAlpha: CGFloat = 0.6
    private static let nextAlpha: CGFloat = 0.55

    private let activeLabel = NSTextField(labelWithString: "")
    private let nextLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)

        configure(activeLabel, fontSize: 15, weight: .semibold)
        configure(nextLabel, fontSize: 12, weight: .regular)
        nextLabel.alphaValue = Self.nextAlpha

        let stack = NSStackView(views: [activeLabel, nextLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // The width clamp belongs on each label directly, not the stack:
        // `.centerX` alignment never stretches or compresses an arranged
        // subview to the stack's own width, so a constraint on the stack's
        // edges alone would leave a long line free to overflow past the
        // card and get hard-clipped by NowPlayingView's corner mask instead
        // of truncating gracefully.
        let maxLabelWidth = NowPlayingView.size.width - 32
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

    /// Passes every click through to whatever hosts this view — it has no
    /// interactive elements of its own, and a click here means "collapse,"
    /// the same as a click anywhere else non-interactive on the card.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func configure(_ field: NSTextField, fontSize: CGFloat, weight: NSFont.Weight) {
        field.font = .systemFont(ofSize: fontSize, weight: weight)
        field.textColor = .white
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
    }

    func update(with content: OverlayDisplay.Content) {
        switch content {
        case .hidden:
            activeLabel.stringValue = "Nothing Playing"
            activeLabel.alphaValue = Self.idleAlpha
            nextLabel.stringValue = ""

        case .idle(let trackName):
            activeLabel.stringValue = trackName
            activeLabel.alphaValue = Self.idleAlpha
            nextLabel.stringValue = ""

        case .lines(.instrumentalGap):
            activeLabel.stringValue = Self.instrumentalGapPlaceholder
            activeLabel.alphaValue = Self.idleAlpha
            nextLabel.stringValue = ""

        case .lines(.lines(let active, let next)):
            activeLabel.stringValue = active.text
            activeLabel.alphaValue = 1.0
            nextLabel.stringValue = next?.text ?? ""
        }
    }
}
