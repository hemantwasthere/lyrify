import AppKit
import LyrifyCore

/// The Overlay's Lyrics face: the Active Line prominent, the surrounding
/// lines `LyricsWindow` resolves dimmed around it — at whatever line count
/// and font size `OverlayLayout` last resolved for the Overlay's current
/// size, `defaultLineCount`/`defaultFontSize` until then. Also draws the
/// three cases that have no window to show: "nothing playing," the Idle
/// State's honest naming, and an Instrumental Gap.
///
/// Deliberately untested — a rendering leaf with no decisions of its own;
/// every decision it draws comes from `OverlayDisplay`, `LineSelection`,
/// `LyricsWindow`, and `OverlayLayout`.
final class LyricsCardView: NSView {
    /// What this view draws — computed by `OverlayController` from the
    /// Core seams above, never derived here.
    enum Content: Equatable {
        case nothingPlaying
        case idle(trackName: String)
        case gap
        case lines([LyricsWindow.Entry])
    }

    /// The line count/font size shown before Full Layout scaling ever
    /// applies — Compact Layout's own Lyrics Face, which doesn't grow with
    /// height the way Full Layout's does, keeps these unconditionally.
    /// Matches the values this view always used before that scaling
    /// existed.
    static let defaultLineCount = 3
    static let defaultFontSize: CGFloat = 15

    /// Shared with `OverlayCardView`'s track-info placeholder, so the two
    /// can't drift on what "nothing known yet" is called.
    static let nothingPlayingText = "Nothing Playing"

    private static let idleAlpha: CGFloat = 0.6
    private static let dimmedAlpha: CGFloat = 0.55
    private static let instrumentalGapPlaceholder = "♪"

    /// One label per line `OverlayLayout` could ever resolve, created once
    /// and shown/hidden per `Content` and the current `lineCount` — cheaper
    /// and simpler than adding/removing arranged subviews every update.
    private var labels: [NSTextField] = []
    private let stack = NSStackView()

    /// The scale currently in force — `updateScale` moves these away from
    /// their defaults as `OverlayLayout` resolves differently for the
    /// Overlay's current size; `update(with:)` re-renders `content` at
    /// whatever's current here.
    private var lineCount = defaultLineCount
    private var fontSize: CGFloat = defaultFontSize

    /// The last content drawn — kept only so `updateScale` can re-render
    /// it immediately at a new scale, without waiting for the next content
    /// update that would otherwise carry it.
    private var content: Content = .nothingPlaying

    init() {
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for _ in 0..<OverlayLayout.maximumLineCount {
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

    /// Moves the line count/font size away from their defaults — called by
    /// `OverlayCardView.update(layout:)` on every resolved `OverlayLayout`,
    /// Full Layout's own scale or Compact Layout's default alike.
    /// Re-renders `content` immediately at the new scale so a live resize
    /// never waits for the next natural content update to reflect it.
    func updateScale(lineCount: Int, fontSize: CGFloat) {
        guard self.lineCount != lineCount || self.fontSize != fontSize else { return }
        self.lineCount = lineCount
        self.fontSize = fontSize
        update(with: content)
    }

    func update(with content: Content) {
        self.content = content
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
            label.font = .systemFont(ofSize: fontSize, weight: .semibold)
            label.alphaValue = alpha
        }
    }

    private func showWindow(_ entries: [LyricsWindow.Entry]) {
        for (index, label) in labels.enumerated() {
            guard index < entries.count, index < lineCount else {
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
