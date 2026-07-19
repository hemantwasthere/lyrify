import Foundation

/// Decides what the Overlay shows for a Playback Position within Synced
/// Lyrics — the Active Line with its Next Line, or an Instrumental Gap — and
/// the Playback Position at which that answer next changes, so the app can
/// arm one precise timer per transition instead of polling.
///
/// Expects lyrics in start-time order, which is what the parser answers.
public enum LineSelection {
    public enum Content: Equatable, Sendable {
        /// Nothing is being sung; `nextChange` says when that ends, if ever.
        case instrumentalGap

        /// The Active Line, and the Next Line when one remains.
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
            // Before the first Lyric Line: the intro is an Instrumental Gap.
            return Answer(content: .instrumentalGap, nextChange: lyrics.first?.start)
        }

        let active = lyrics[activeIndex]
        let next = lyrics.indices.contains(activeIndex + 1) ? lyrics[activeIndex + 1] : nil

        // An empty-text Active Line is the marker form of an Instrumental
        // Gap, preserved by the parser for exactly this moment.
        let content: Content = active.text.isEmpty
            ? .instrumentalGap
            : .lines(active: active, next: next)
        return Answer(content: content, nextChange: next?.start)
    }
}
