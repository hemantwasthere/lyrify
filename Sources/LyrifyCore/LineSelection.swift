import Foundation

/// Decides what the Overlay shows for a Playback Position within Synced
/// Lyrics — the Active Line with its Next Line, or an Intro Gap — and the
/// Playback Position at which that answer next changes, so the app can arm
/// one precise timer per transition instead of polling.
///
/// The one question this asks is **whether an Active Line exists yet**, which
/// is not the same as whether anything is being sung. An Instrumental Gap
/// partway through a Track has an Active Line: the empty-text Gap Marker the
/// parser preserves. That marker is answered as `.lines` like any other line,
/// so callers keep the lines around it and the listener keeps their place
/// through the break. This used to collapse the marker into a gap case, which
/// threw that context away and cleared the Lyrics view down to a bare "♪" —
/// so if this looks like a missing special case, it is a deliberately removed
/// one.
///
/// Expects lyrics in start-time order, which is what the parser answers.
public enum LineSelection {
    public enum Content: Equatable, Sendable {
        /// No Active Line exists yet — the Intro Gap before the first Lyric
        /// Line, or lyrics with no lines at all. `nextChange` says when the
        /// first line arrives, if one ever does.
        case introGap

        /// The Active Line, and the Next Line when one remains. The Active
        /// Line may be a Gap Marker, whose empty text is how an Instrumental
        /// Gap declares itself; it is an Active Line all the same.
        case lines(active: LyricLine, next: LyricLine?)
    }

    public struct Answer: Equatable, Sendable {
        public let content: Content

        /// The Playback Position at which `content` changes, or nil once no
        /// further transition remains.
        public let nextChange: TimeInterval?

        public init(content: Content, nextChange: TimeInterval?) {
            self.content = content
            self.nextChange = nextChange
        }
    }

    public static func at(_ position: TimeInterval, in lyrics: [LyricLine]) -> Answer {
        guard let activeIndex = lyrics.lastIndex(where: { $0.start <= position }) else {
            // Nothing has been reached yet, so there is no Active Line to name.
            return Answer(content: .introGap, nextChange: lyrics.first?.start)
        }

        // A Gap Marker is not filtered out here. See the note on this type:
        // an empty-text Active Line is still the Active Line, and answering it
        // as one is what lets the window keep the lines either side of a gap.
        let active = lyrics[activeIndex]
        let next = lyrics.indices.contains(activeIndex + 1) ? lyrics[activeIndex + 1] : nil
        return Answer(content: .lines(active: active, next: next), nextChange: next?.start)
    }
}
