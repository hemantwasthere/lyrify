import CoreGraphics

/// Resolves which layout the Overlay's current size calls for — Compact
/// Layout (a small thumbnail-and-text bar) below a size threshold, Full
/// Layout (Spotify Mini Player–style artwork, seek bar, and chrome) at or
/// above it — and, for Full Layout, how many Lyrics Face lines and what
/// font size that height affords.
///
/// Expands the retired `LyricsViewScale`: its old height-to-scale formula
/// reappears unchanged as Full Layout's own scaling, just anchored at a
/// new starting point rather than the old card's own minimum. That old
/// minimum (96pt) fit a lyrics-text-only view; Full Layout needs enough
/// room for a big square artwork area, an always-visible seek bar, a
/// transport row, and a top chrome bar besides — a taller, independent
/// minimum, tuned separately from the scaling curve it happens to share.
public enum OverlayLayout: Equatable, Sendable {
    case compact
    case full(LyricsScale)

    public struct LyricsScale: Equatable, Sendable {
        public let lineCount: Int
        public let fontSize: CGFloat

        public init(lineCount: Int, fontSize: CGFloat) {
            self.lineCount = lineCount
            self.fontSize = fontSize
        }
    }

    /// Below this height, Compact Layout; at or above it, Full Layout —
    /// roughly where the Overlay is tall enough to read as square rather
    /// than a short bar, matching Compact Layout's own width today. A
    /// tuning knob, not a locked design decision.
    public static let thresholdHeight: CGFloat = 220

    public static let minimumLineCount = 2
    public static let minimumFontSize: CGFloat = 15

    /// However tall the Overlay grows, line count and font size stop
    /// growing here — a Lyrics Face too crowded with lines stops being
    /// legible at a glance, which is the whole point of the Overlay.
    public static let maximumLineCount = 9
    public static let maximumFontSize: CGFloat = 32

    /// One additional line for every this many points of extra height
    /// above `thresholdHeight`.
    private static let pointsPerLine: CGFloat = 40

    /// Degrees of font growth per additional line — kept in step with
    /// line count so the two always change together.
    private static let fontSizeStepPerLine: CGFloat = 1.5

    public static func resolve(size: CGSize) -> OverlayLayout {
        guard size.height >= thresholdHeight else { return .compact }

        let extraHeight = size.height - thresholdHeight
        let extraLines = Int(extraHeight / pointsPerLine)

        let lineCount = min(minimumLineCount + extraLines, maximumLineCount)
        let fontSize = min(minimumFontSize + CGFloat(extraLines) * fontSizeStepPerLine, maximumFontSize)

        return .full(LyricsScale(lineCount: lineCount, fontSize: fontSize))
    }
}
