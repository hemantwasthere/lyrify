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
        case idle(trackName: String, note: String?)
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

    /// Why there are no lyrics to show, when there are none.
    ///
    /// The Idle State used to name the Track and say nothing else, so a lookup
    /// LRCLIB could not answer looked identical to a song that genuinely has no
    /// synced lyrics — and identical to Lyrify being broken. It is a free
    /// community service and it does fall over; when it does, that is worth
    /// saying rather than leaving the listener to guess whose fault it is.
    public enum Availability: Equatable, Sendable {
        case searching
        case noLyrics
        case serviceUnavailable

        /// Deliberately quiet: no note at all while a lookup is still in flight,
        /// because most land fast enough that a message would only flicker.
        var note: String? {
            switch self {
            case .searching: nil
            case .noLyrics: "No synced lyrics for this track"
            case .serviceUnavailable: "LRCLIB isn't responding — nothing wrong on your side"
            }
        }
    }

    public static func resolve(
        isVisible: Bool,
        state: PlaybackState,
        lyrics: [LyricLine]?,
        availability: Availability = .searching
    ) -> Answer {
        guard isVisible, let track = state.track, let position = state.position else {
            return Answer(content: .hidden, nextChange: nil)
        }
        guard let lyrics else {
            return Answer(
                content: .idle(trackName: TrackLabel.text(for: track), note: availability.note),
                nextChange: nil
            )
        }

        let selection = LineSelection.at(position, in: lyrics)
        return Answer(content: .lines(selection.content), nextChange: selection.nextChange)
    }
}
