import AppKit

/// A single line of text that scrolls sideways when it is too long to fit, the
/// way Spotify's miniplayer scrolls a long Track title, and sits still when it
/// fits. Truncating instead would be the easy option, but a title clipped to
/// "Everything I Wasn't Looking F…" is exactly the case this view exists for.
///
/// The cycle is Spotify's: hold at the start, scroll left until the tail is
/// visible, hold again, then return to the start and repeat. Each run carries a
/// generation number so a Track change mid-scroll cancels the animation in
/// flight rather than letting two cycles fight over the same label.
///
/// Deliberately untested — an animation leaf, verified by hand.
final class MarqueeLabel: NSView {
    private let label = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint!

    /// Bumped on every text change and every cycle restart; a callback whose
    /// generation no longer matches has been superseded and must do nothing.
    private var generation = 0

    private static let pointsPerSecond: CGFloat = 26
    private static let holdSeconds: TimeInterval = 2.0

    init(font: NSFont, color: NSColor) {
        super.init(frame: .zero)

        // The container clips; the label inside it is free to be wider.
        wantsLayer = true
        layer?.masksToBounds = true

        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
        // A long title must not widen the card — overflowing is the whole point
        // of this view, and the container clips what doesn't fit.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(label)

        leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            leadingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalTo: label.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Passes clicks through — a title is not a control, and a click here means
    /// "collapse the Overlay", same as anywhere else non-interactive.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var stringValue: String {
        get { label.stringValue }
        set {
            guard newValue != label.stringValue else { return }
            label.stringValue = newValue
            restart()
        }
    }

    /// Restarts only when the available width actually changed.
    ///
    /// Restarting unconditionally here deadlocks the app: `restart()` writes to
    /// a layout constraint, which invalidates layout, which calls this again —
    /// and `setFrame(display:)` during startup drives the first pass, so the
    /// Overlay never finishes being built. Gating on the width both breaks that
    /// cycle and is the only case that matters, since how far the text overflows
    /// can only change when the space it has to fit in does.
    override func layout() {
        super.layout()
        guard bounds.width != lastLaidOutWidth else { return }
        lastLaidOutWidth = bounds.width
        restart()
    }

    private var lastLaidOutWidth: CGFloat = -1

    /// Cancels whatever is running, returns to the start, and begins a new cycle
    /// only if the text actually overflows.
    private func restart() {
        generation += 1
        leadingConstraint.constant = 0

        let overflow = overflowWidth
        guard overflow > 0 else { return }
        scheduleScroll(after: Self.holdSeconds, generation: generation, overflow: overflow)
    }

    /// How far past the container's trailing edge the text runs, in points.
    private var overflowWidth: CGFloat {
        guard bounds.width > 0 else { return 0 }
        return max(0, label.intrinsicContentSize.width - bounds.width)
    }

    private func scheduleScroll(after delay: TimeInterval, generation runGeneration: Int, overflow: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == runGeneration else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = TimeInterval(overflow / Self.pointsPerSecond)
                context.timingFunction = CAMediaTimingFunction(name: .linear)
                self.leadingConstraint.animator().constant = -overflow
            } completionHandler: {
                MainActor.assumeIsolated {
                    guard self.generation == runGeneration else { return }
                    // Hold at the tail, snap home, then run the whole cycle again.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds) {
                        guard self.generation == runGeneration else { return }
                        self.leadingConstraint.constant = 0
                        self.scheduleScroll(after: Self.holdSeconds, generation: runGeneration, overflow: overflow)
                    }
                }
            }
        }
    }
}
