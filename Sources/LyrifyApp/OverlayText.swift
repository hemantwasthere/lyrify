import AppKit
import LyrifyCore

/// The Active and Next Line wording and dimming, derived once from
/// `LineSelection.Content` and shared by both Placement forms — the pill and
/// the notch's two wings — so they never disagree on what an Instrumental
/// Gap or a missing Next Line looks like.
struct OverlayText {
    let activeText: String
    let activeAlpha: CGFloat
    let nextText: String

    /// Dims the Next Line wherever it's drawn — the pill and the notch's
    /// right wing alike — so the two forms can't drift apart on how much
    /// the anticipated line stands out from the active one.
    let nextAlpha: CGFloat = 0.55

    /// A quiet placeholder for an Instrumental Gap — never stale words.
    private static let instrumentalGapPlaceholder = "♪"

    init(_ content: LineSelection.Content) {
        switch content {
        case .instrumentalGap:
            activeText = Self.instrumentalGapPlaceholder
            activeAlpha = 0.5
            nextText = ""

        case .lines(let active, let next):
            activeText = active.text
            activeAlpha = 1.0
            nextText = next?.text ?? ""
        }
    }
}
