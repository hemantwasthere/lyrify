import CoreGraphics

/// Resolves where the Overlay should sit, given whatever position was last
/// remembered — a screen or display change between launches can silently
/// invalidate it, and the Overlay must never be stranded off every
/// currently attached screen with no way back except clearing preferences
/// by hand.
public enum OverlayOrigin {
    /// `remembered` if a window of `size` there would still have its center
    /// on at least one of `screens`, otherwise `fallback`. Checked by
    /// center point rather than requiring the whole window to fit, so a
    /// window mostly but not entirely on screen still counts as fine.
    public static func resolve(
        remembered: CGPoint?,
        size: CGSize,
        screens: [CGRect],
        fallback: CGPoint
    ) -> CGPoint {
        guard let remembered else { return fallback }

        let center = CGPoint(x: remembered.x + size.width / 2, y: remembered.y + size.height / 2)
        let isOnScreen = screens.contains { $0.contains(center) }
        return isOnScreen ? remembered : fallback
    }
}
