import Foundation

/// A window of several Lyric Lines centred on the Active Line, built on top
/// of the unmodified `LineSelection` — the seam the resizable Lyrics view
/// scales against as it grows to show more surrounding context or shrinks
/// back to just the Active Line.
public enum LyricsWindow {
    /// Where an entry sits relative to the Active Line.
    public enum Role: Equatable, Sendable {
        case before
        case active
        case after
    }

    public struct Entry: Equatable, Sendable {
        public let line: LyricLine
        public let role: Role

        public init(line: LyricLine, role: Role) {
            self.line = line
            self.role = role
        }
    }

    /// Resolves up to `lineCount` entries centred on the Active Line for
    /// `position`, clamped at the start and end of `lyrics` — a window that
    /// would otherwise run off one end borrows the extra room from the
    /// other side instead of simply answering fewer lines.
    ///
    /// An odd `lineCount` splits evenly; an even one gives the extra line
    /// to `after`, since upcoming context matters more to a listener than
    /// reviewing what already passed. In an Intro Gap or with empty lyrics
    /// there is no Active Line to centre on, so the window is empty.
    ///
    /// A Gap Marker is centred on like any other line. That is the whole of
    /// what keeps the lines either side of an Instrumental Gap on screen
    /// through the break — the window is not interrupted by one, it simply
    /// contains it, and the display draws it as "♪" in place of words.
    public static func resolve(at position: TimeInterval, in lyrics: [LyricLine], lineCount: Int) -> [Entry] {
        // `LineSelection.at` is the one place "which line is Active" is
        // decided — reused here rather than re-deriving that rule, even
        // though it only answers the line itself, not its index; finding
        // that index back within `lyrics` is the one thing this seam adds.
        guard lineCount > 0,
              case .lines(let active, _) = LineSelection.at(position, in: lyrics).content,
              let activeIndex = lyrics.firstIndex(of: active)
        else {
            return []
        }

        let lastIndex = lyrics.count - 1
        let before = (lineCount - 1) / 2
        let after = lineCount - 1 - before

        var start = activeIndex - before
        var end = activeIndex + after

        if start < 0 {
            end += -start
            start = 0
        }
        if end > lastIndex {
            start -= end - lastIndex
            end = lastIndex
        }
        start = max(start, 0)

        return (start...end).map { index in
            let role: Role = index == activeIndex ? .active : (index < activeIndex ? .before : .after)
            return Entry(line: lyrics[index], role: role)
        }
    }
}
