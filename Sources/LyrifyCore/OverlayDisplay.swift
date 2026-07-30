import Foundation

/// The Overlay's outermost decision: hidden, its Idle State naming the
/// Track, or Synced Lyrics via `LineSelection` — in that priority order.
///
/// Hidden-by-toggle beats every other state. Below that, no Track means
/// nothing to show. Below that, a Track with no Synced Lyrics yet — a lookup
/// still in flight, a confirmed miss, unavailability, or a Non-Lyrical Item —
/// is the Idle State: naming the Track (reusing `TrackLabel`'s wording)
/// without pretending to follow it. Only a Track with Synced Lyrics found
/// hands off to `LineSelection`.
public enum OverlayDisplay {
    public enum Content: Equatable, Sendable {
        case hidden
        case idle(trackName: String)
        case lines(LineSelection.Content)
    }

    public struct Answer: Equatable, Sendable {
        public let content: Content

        /// The Playback Position at which `content` next changes, carried
        /// straight from `LineSelection` — nil for `.hidden` and `.idle`,
        /// which have no transition of their own to schedule.
        public let nextChange: TimeInterval?

        public init(content: Content, nextChange: TimeInterval?) {
            self.content = content
            self.nextChange = nextChange
        }
    }

    public static func resolve(
        isVisible: Bool,
        state: PlaybackState,
        lyrics: [LyricLine]?
    ) -> Answer {
        guard isVisible, let track = state.track, let position = state.position else {
            return Answer(content: .hidden, nextChange: nil)
        }
        guard let lyrics else {
            return Answer(content: .idle(trackName: TrackLabel.text(for: track)), nextChange: nil)
        }

        let selection = LineSelection.at(position, in: lyrics)
        return Answer(content: .lines(selection.content), nextChange: selection.nextChange)
    }
}
