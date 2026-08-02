import Foundation

/// Two Players behind one port: the preferred one whenever it has something to
/// say, and the other when it does not.
///
/// This is the interim answer, and deliberately a small one. It satisfies what
/// the browser path needs today — Spotify keeps every listener it already has,
/// and a browser is followed only when Spotify is not running — without
/// pretending to arbitrate. Real arbitration reads which application holds the
/// Now Playing Floor and routes on that; when it arrives, this type is what it
/// replaces.
///
/// A Player that is `notRunning` is the only thing that yields the floor here.
/// A *paused* Spotify is still Spotify: someone who paused a song and has not
/// closed the app has not asked to be shown something else.
@MainActor
public final class PreferredPlaybackSource: PlaybackSource {
    private let preferred: any PlaybackSource
    private let fallback: any PlaybackSource

    public init(preferred: any PlaybackSource, fallback: any PlaybackSource) {
        self.preferred = preferred
        self.fallback = fallback
    }

    public func currentState() throws -> PlaybackState {
        // A preferred Player that fails is treated as one that is not running:
        // a refused Automation permission must not take the browser path down
        // with it.
        let preferredState = (try? preferred.currentState()) ?? .notRunning
        guard preferredState == .notRunning else { return preferredState }

        return (try? fallback.currentState()) ?? .notRunning
    }
}
