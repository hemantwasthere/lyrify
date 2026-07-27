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

    /// The smallest height this mapping expects, and what it answers at or
    /// below it.
    ///
    /// This is the height of the *lyrics area* — the panel the lines are drawn
    /// in — not the whole card. Feeding it the card's height was what made the
    /// text far too large for the space it actually had: the panel is only ever
    /// a fraction of the card, so every line came out sized for a box roughly
    /// twice as tall as the one it had to fit inside.
    public static let minimumHeight: CGFloat = 64
    public static let minimumLineCount = 2
    public static let minimumFontSize: CGFloat = 11

    /// However tall the panel grows, line count and font size stop growing
    /// here — a panel too crowded with lines stops being legible at a
    /// glance, which is the whole point of the Overlay.
    public static let maximumLineCount = 9
    public static let maximumFontSize: CGFloat = 20

    /// Below this much height, even the two base lines cannot be drawn at a
    /// readable size. The Overlay hides its lyrics button entirely rather than
    /// offering a view that would arrive unreadable.
    public static let minimumUsableHeight: CGFloat = 58

    /// One additional line for every this many points of extra height. Set so
    /// `lineCount` lines at `fontSize` always fit the height that asked for
    /// them, with room for the spacing between them.
    private static let pointsPerLine: CGFloat = 46

    /// Degrees of font growth per additional line — kept in step with
    /// line count so the two always change together.
    private static let fontSizeStepPerLine: CGFloat = 1.0

    public static func resolve(forHeight height: CGFloat) -> Scale {
        let extraHeight = max(0, height - minimumHeight)
        let extraLines = Int(extraHeight / pointsPerLine)

        let lineCount = min(minimumLineCount + extraLines, maximumLineCount)
        let fontSize = min(minimumFontSize + CGFloat(extraLines) * fontSizeStepPerLine, maximumFontSize)

        return Scale(lineCount: lineCount, fontSize: fontSize)
    }
}
