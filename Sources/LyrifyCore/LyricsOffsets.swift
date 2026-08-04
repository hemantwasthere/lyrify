import Foundation

/// The Offsets a listener has applied, one per Track.
///
/// Some Matches are right but shifted. A music video carrying an intro card
/// ahead of the song is the same recording started late, and no comparison of
/// durations can tell that apart from a different recording — the only thing
/// that can is the listener, who can hear it. This is where their correction
/// lives.
///
/// An Offset moves *which Lyric Line is Active* and nothing else. The Playback
/// Position, the progress bar and everything Lyrify reports about the Player
/// stay exactly as observed: the Track has not moved, only the words have.
///
/// A pure value, so applying, accumulating and remembering are all testable
/// without a Track playing.
public struct LyricsOffsets: Equatable, Sendable {
    /// How far one nudge moves the words. Fine enough that a listener can land
    /// on the beat, coarse enough that getting there does not take all day.
    public static let step: TimeInterval = 0.25

    /// How far an Offset may be pushed either way. An intro card is seconds,
    /// not minutes, and a bound is what stops a held button pushing the lyrics
    /// somewhere they cannot be recovered from.
    public static let limit: TimeInterval = 30

    /// Only Tracks actually corrected appear. A Track nudged back to nothing is
    /// removed rather than stored as zero — otherwise this grows to hold every
    /// video ever watched, to say nothing about any of them.
    private var offsets: [String: TimeInterval] = [:]

    public init() {}

    /// Rebuilds from the form a preference can hold.
    public init(stored: [String: Double]) {
        offsets = stored.filter { $0.value != 0 }
    }

    /// The form a preference can hold.
    public var stored: [String: Double] { offsets }

    /// The correction applied to this Track, or zero.
    public func offset(for uri: String) -> TimeInterval { offsets[uri] ?? 0 }

    /// The Playback Position to choose a Lyric Line by.
    ///
    /// A positive Offset holds the lyrics back — the video began late — so it
    /// looks *earlier* into the Synced Lyrics than the Playback Position alone
    /// would.
    ///
    /// Nothing is clamped. Looking before the first Lyric Line is an Intro Gap,
    /// which `LineSelection` already answers properly, and looking past the last
    /// is simply the last line still being Active.
    public func adjusted(_ position: TimeInterval, for uri: String) -> TimeInterval {
        position - offset(for: uri)
    }

    /// Moves this Track's Offset by `steps`, bounded by the limit.
    public mutating func nudge(_ uri: String, by steps: Int) {
        let moved = offset(for: uri) + TimeInterval(steps) * Self.step
        let bounded = min(max(moved, -Self.limit), Self.limit)

        if bounded == 0 {
            offsets.removeValue(forKey: uri)
        } else {
            offsets[uri] = bounded
        }
    }

    /// Forgets this Track's correction entirely.
    public mutating func clear(_ uri: String) {
        offsets.removeValue(forKey: uri)
    }
}
