import AppKit
import LyrifyCore

/// The Overlay's Lyrics face: the Active Line prominent, the surrounding
/// lines `LyricsWindow` resolves dimmed around it — always `lineCount`
/// lines at `fontSize`, both fixed now that the widget itself is a fixed
/// size. Also draws the three cases that have no window to show: "nothing
/// playing," the Idle State's honest naming, and an Instrumental Gap.
///
/// Deliberately untested — a rendering leaf with no decisions of its own;
/// every decision it draws comes from `OverlayDisplay`, `LineSelection`,
/// and `LyricsWindow`.
final class LyricsCardView: NSView {
    /// What this view draws — computed by `OverlayController` from the
    /// Core seams above, never derived here.
    enum Content: Equatable {
        case nothingPlaying
        case idle(trackName: String)
        case gap
        case lines([LyricsWindow.Entry])
    }

    /// How many lines `OverlayController` asks `LyricsWindow` to resolve —
    /// the single source of truth shared with this view's own label pool,
    /// so the two can never drift apart.
    static let lineCount = 3
    static let fontSize: CGFloat = 15

    /// Shared with `OverlayCardView`'s track-info placeholder, so the two
    /// can't drift on what "nothing known yet" is called.
    static let nothingPlayingText = "Nothing Playing"

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

        for _ in 0..<Self.lineCount {
            let label = NSTextField(labelWithString: "")
            label.textColor = .white
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.isHidden = true
            label.translatesAutoresizingMaskIntoConstraints = false
            labels.append(label)
            stack.addArrangedSubview(label)
            // Relative to this view's own width, not a fixed constant, so
            // this stays correct if the widget's fixed size ever changes.
            // Must come after addArrangedSubview: activating a constraint
            // between the label and this view before the label is anywhere
            // in this view's hierarchy has no common ancestor to resolve
            // against, and Auto Layout raises for it.
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32).isActive = true
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
    /// interactive elements of its own, and a click anywhere non-interactive
    /// on the widget only ever starts a drag.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(with content: Content) {
        switch content {
        case .nothingPlaying:
            showSingleLine(Self.nothingPlayingText, alpha: Self.idleAlpha)

        case .idle(let trackName):
            showSingleLine(trackName, alpha: Self.idleAlpha)

        case .gap:
            showSingleLine(Self.instrumentalGapPlaceholder, alpha: Self.idleAlpha)

        case .lines(let entries):
            showWindow(entries)
        }
    }

    private func showSingleLine(_ text: String, alpha: CGFloat) {
        for (index, label) in labels.enumerated() {
            guard index == 0 else {
                label.isHidden = true
                continue
            }
            label.isHidden = false
            label.stringValue = text
            label.font = .systemFont(ofSize: Self.fontSize, weight: .semibold)
            label.alphaValue = alpha
        }
    }

    private func showWindow(_ entries: [LyricsWindow.Entry]) {
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
            label.font = .systemFont(ofSize: Self.fontSize, weight: isActive ? .semibold : .regular)
            label.alphaValue = isGap ? Self.idleAlpha : (isActive ? 1.0 : Self.dimmedAlpha)
        }
    }
}
