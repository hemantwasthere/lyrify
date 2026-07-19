import Foundation

/// What Spotify is doing right now, as far as Lyrify can observe it.
///
/// `notRunning` is a first-class state rather than an error: Spotify being
/// closed is entirely normal, and Lyrify must stay quiet rather than complain.
public enum PlaybackState: Equatable, Sendable {
    case notRunning
    case stopped
    case paused(Track, position: TimeInterval)
    case playing(Track, position: TimeInterval)

    public var track: Track? {
        switch self {
        case .notRunning, .stopped: nil
        case .paused(let track, _), .playing(let track, _): track
        }
    }

    /// The observed Playback Position, in seconds, when there is one.
    public var position: TimeInterval? {
        switch self {
        case .notRunning, .stopped: nil
        case .paused(_, let position), .playing(_, let position): position
        }
    }

    public var isPlaying: Bool {
        if case .playing = self { true } else { false }
    }
}

/// Where Lyrify gets its playback observations.
///
/// The port exists so the timing logic can be driven by a fake in tests; the
/// real implementation talks to the Spotify desktop client. See ADR-0002.
///
/// Main-actor isolated because observing playback means talking to Apple Events,
/// which is not thread-safe. Fakes are cheap to write against it regardless.
@MainActor
public protocol PlaybackSource {
    func currentState() throws -> PlaybackState
}
