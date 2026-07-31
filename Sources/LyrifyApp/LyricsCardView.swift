import AppKit
import LyrifyCore

/// The Overlay's Lyrics view: the Active Line prominent, the surrounding
/// lines `LyricsWindow` resolves dimmed around it — as many as the resized
/// card's height calls for, at the font size `LyricsViewScale` maps to it.
/// Also draws the three cases that have no window to show: "nothing
/// playing," the Idle State's honest naming, and the Intro Gap. An
/// Instrumental Gap partway through a Track is not one of them — it arrives
/// as an ordinary window, its Gap Marker drawn as "♪" in the Active Line's
/// place with the surrounding lines still around it.
///
/// Deliberately untested — a rendering leaf with no decisions of its own;
/// every decision it draws comes from `OverlayDisplay`, `LineSelection`,
/// `LyricsWindow`, and `LyricsViewScale`.
final class LyricsCardView: NSView {
    /// What this view draws — computed by `OverlayController` from the
    /// Core seams above, never derived here.
    enum Content: Equatable {
        case nothingPlaying
        case idle(trackName: String, note: String?)
        /// The Intro Gap only — the stretch before the first Lyric Line, where
        /// there is no lyrical context to show because none has happened yet.
        /// An Instrumental Gap mid-Track arrives as `.lines` instead, carrying
        /// its Gap Marker along with the lines around it.
        case introGap
        case lines([LyricsWindow.Entry], fontSize: CGFloat)
    }

    private static let maxLines = LyricsViewScale.maximumLineCount
    private static let idleAlpha: CGFloat = 0.6
    private static let dimmedAlpha: CGFloat = 0.55
    /// Stands in for nothing being sung, in both kinds of gap.
    private static let gapPlaceholder = "♪"

    /// One label per possible line, created once and shown/hidden per
    /// `Content` — cheaper and simpler than adding/removing arranged
    /// subviews every update.
    private var labels: [NSTextField] = []
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)

        // Whatever the lyrics need, they never get a vote on how big the card
        // is. Without this the two feed each other without limit: a taller card
        // makes `LyricsViewScale` ask for more lines, those lines demand more
        // height, the card grows to supply it, and around again — which is how
        // a 300×400 card ended up over a thousand points on a side. Lines that
        // don't fit are clipped instead.
        wantsLayer = true
        layer?.masksToBounds = true

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
            // Part of the same rule: a long or numerous set of lines must be
            // free to be clipped rather than push the card wider or taller.
            for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
                label.setContentCompressionResistancePriority(.defaultLow, for: axis)
                label.setContentHuggingPriority(.defaultLow, for: axis)
            }
            labels.append(label)
            // Added to the hierarchy *before* the width constraint below is
            // activated: that constraint spans the label and this view, and
            // activating it while the label still has no superview throws —
            // the two have no common ancestor to resolve it against.
            stack.addArrangedSubview(label)
            // Relative to this view's own width, not a fixed constant: the
            // card is resizable now, so a hardcoded cap would stay stale as
            // it grows wider, letting truncation kick in far too early.
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
    /// interactive elements of its own, and a click here means "collapse,"
    /// the same as a click anywhere else non-interactive on the card.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(with content: Content) {
        switch content {
        case .nothingPlaying:
            showSingleLine("Nothing Playing", fontSize: LyricsViewScale.minimumFontSize, alpha: Self.idleAlpha)

        case .idle(let trackName, let note):
            showIdle(trackName: trackName, note: note)

        case .introGap:
            showSingleLine(Self.gapPlaceholder, fontSize: LyricsViewScale.minimumFontSize, alpha: Self.idleAlpha)

        case .lines(let entries, let fontSize):
            showWindow(entries, fontSize: fontSize)
        }
    }

    /// The Track's name, and under it — quieter and smaller — why there are no
    /// lyrics beneath it, when there is a reason worth giving.
    private func showIdle(trackName: String, note: String?) {
        guard let note else {
            showSingleLine(trackName, fontSize: LyricsViewScale.minimumFontSize, alpha: Self.idleAlpha)
            return
        }

        for (index, label) in labels.enumerated() {
            switch index {
            case 0:
                label.isHidden = false
                label.stringValue = trackName
                label.font = .systemFont(ofSize: LyricsViewScale.minimumFontSize, weight: .semibold)
                label.alphaValue = Self.idleAlpha
            case 1:
                label.isHidden = false
                label.stringValue = note
                label.font = .systemFont(ofSize: LyricsViewScale.minimumFontSize - 2, weight: .regular)
                label.alphaValue = Self.idleAlpha * 0.7
            default:
                label.isHidden = true
            }
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
            label.stringValue = isGap ? Self.gapPlaceholder : entry.line.text
            label.font = .systemFont(ofSize: fontSize, weight: isActive ? .semibold : .regular)
            label.alphaValue = isGap ? Self.idleAlpha : (isActive ? 1.0 : Self.dimmedAlpha)
        }
    }
}
