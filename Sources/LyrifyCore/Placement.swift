import CoreGraphics

/// Where the Overlay sits, resolved at runtime from the chosen display's
/// reported geometry — never hardcoded. See ADR-0004: the notch is a
/// Placement, not a premise.
public enum Placement: Equatable, Sendable {
    /// A floating two-line pill near the top edge, for a display with no
    /// notch.
    case pill

    /// Straddles the notch, merging visually with it: the Active Line sits
    /// in `leftMargin` and the Next Line in `rightMargin` — the safe areas
    /// either side of the notch, as the display reports them.
    case notch(leftMargin: CGRect, rightMargin: CGRect)

    /// A display reports a positive top safe-area inset exactly when it has
    /// a notch; `leftMargin` and `rightMargin` are only meaningful — and
    /// only supplied by AppKit — on such a display.
    public static func resolve(
        topSafeAreaInset: CGFloat,
        leftMargin: CGRect,
        rightMargin: CGRect
    ) -> Placement {
        guard topSafeAreaInset > 0 else { return .pill }
        return .notch(leftMargin: leftMargin, rightMargin: rightMargin)
    }
}
