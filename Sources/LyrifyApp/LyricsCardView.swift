import AppKit
import LyrifyCore

/// The Overlay's Lyrics view: the Active Line prominent, the surrounding
/// lines `LyricsWindow` resolves dimmed around it — as many as the resized
/// card's height calls for, at the font size `LyricsViewScale` maps to it.
/// Also draws the three cases that have no window to show: "nothing
/// playing," the Idle State's honest naming, and an Instrumental Gap.
///
/// Deliberately untested — a rendering leaf with no decisions of its own;
/// every decision it draws comes from `OverlayDisplay`, `LineSelection`,
/// `LyricsWindow`, and `LyricsViewScale`.
final class LyricsCardView: NSView {
    /// What this view draws — computed by `OverlayController` from the
    /// Core seams above, never derived here.
    enum Content: Equatable {
        case nothingPlaying
        case idle(trackName: String)
        case gap
        case lines([LyricsWindow.Entry], fontSize: CGFloat)
    }

    private static let maxLines = LyricsViewScale.maximumLineCount
    private static let idleAlpha: CGFloat = 0.6
    private static let dimmedAlpha: CGFloat = 0.55
    private static let instrumentalGapPlaceholder = "♪"

    /// One label per possible line, created once and shown/hidden per
    /// `Content` — cheaper and simpler than adding/removing arranged
    /// subviews every update.
    private var labels: [NSTextField] = []
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for _ in 0..<Self.maxLines {
            let label = NSTextField(labelWithString: "")
            label.textColor = .white
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.isHidden = true
            label.translatesAutoresizingMaskIntoConstraints = false
            // Relative to this view's own width, not a fixed constant: the
            // card is resizable now, so a hardcoded cap would stay stale as
            // it grows wider, letting truncation kick in far too early.
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32).isActive = true
            labels.append(label)
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
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

    func update(with content: Content) {
        switch content {
        case .nothingPlaying:
            showSingleLine("Nothing Playing", fontSize: LyricsViewScale.minimumFontSize, alpha: Self.idleAlpha)

        case .idle(let trackName):
            showSingleLine(trackName, fontSize: LyricsViewScale.minimumFontSize, alpha: Self.idleAlpha)

        case .gap:
            showSingleLine(Self.instrumentalGapPlaceholder, fontSize: LyricsViewScale.minimumFontSize, alpha: Self.idleAlpha)

        case .lines(let entries, let fontSize):
            showWindow(entries, fontSize: fontSize)
        }
    }

    private func showSingleLine(_ text: String, fontSize: CGFloat, alpha: CGFloat) {
        for (index, label) in labels.enumerated() {
            guard index == 0 else {
                label.isHidden = true
                continue
            }
            label.isHidden = false
            label.stringValue = text
            label.font = .systemFont(ofSize: fontSize, weight: .semibold)
            label.alphaValue = alpha
        }
    }

    private func showWindow(_ entries: [LyricsWindow.Entry], fontSize: CGFloat) {
        for (index, label) in labels.enumerated() {
            guard index < entries.count else {
                label.isHidden = true
                continue
            }

            let entry = entries[index]
            let isActive = entry.role == .active
            // The empty-text marker means an Instrumental Gap, but only the
            // Active Line can currently be mid-gap; a surrounding line is
            // always real text.
            let isGap = isActive && entry.line.text.isEmpty

            label.isHidden = false
            label.stringValue = isGap ? Self.instrumentalGapPlaceholder : entry.line.text
            label.font = .systemFont(ofSize: fontSize, weight: isActive ? .semibold : .regular)
            label.alphaValue = isGap ? Self.idleAlpha : (isActive ? 1.0 : Self.dimmedAlpha)
        }
    }
}
