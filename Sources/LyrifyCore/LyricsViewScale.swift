import CoreGraphics

/// Maps the Lyrics view's available height to how many lines it shows and
/// how large their font is — growing the card adds more lines at a bigger
/// font, the way Spotify's own full-screen lyrics view scales, independent
/// of `LyricsWindow`'s own windowing logic.
public enum LyricsViewScale {
    public struct Scale: Equatable, Sendable {
        public let lineCount: Int
        public let fontSize: CGFloat

        public init(lineCount: Int, fontSize: CGFloat) {
            self.lineCount = lineCount
            self.fontSize = fontSize
        }
    }

    /// The smallest card height this mapping expects — the Expanded card's
    /// own minimum size — and what it answers at or below that height.
    public static let minimumHeight: CGFloat = 96
    public static let minimumLineCount = 2
    public static let minimumFontSize: CGFloat = 15

    /// However tall the card grows, line count and font size stop growing
    /// here — a card too crowded with lines stops being legible at a
    /// glance, which is the whole point of the Overlay.
    public static let maximumLineCount = 9
    public static let maximumFontSize: CGFloat = 32

    /// One additional line for every this many points of extra height.
    private static let pointsPerLine: CGFloat = 40

    /// Degrees of font growth per additional line — kept in step with
    /// line count so the two always change together.
    private static let fontSizeStepPerLine: CGFloat = 1.5

    public static func resolve(forHeight height: CGFloat) -> Scale {
        let extraHeight = max(0, height - minimumHeight)
        let extraLines = Int(extraHeight / pointsPerLine)

        let lineCount = min(minimumLineCount + extraLines, maximumLineCount)
        let fontSize = min(minimumFontSize + CGFloat(extraLines) * fontSizeStepPerLine, maximumFontSize)

        return Scale(lineCount: lineCount, fontSize: fontSize)
    }
}
