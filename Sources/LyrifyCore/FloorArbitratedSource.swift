import Foundation

/// Both Players behind one port, routed by whoever holds the Now Playing Floor.
///
/// The Floor says *who*; that Player says *what*. Spotify is asked over its own
/// bridge rather than read from the Floor, because the Floor does not carry the
/// URI that keys lyrics memoisation, the album the first widening step Matches
/// on, or anything that could drive its transport — the Floor is consulted only
/// for ownership, never as a replacement for Spotify's own reporting.
///
/// Nothing downstream of the port changes: the Anchor stream, the estimated
/// Playback Position, the menu bar title and the Overlay all see one
/// `PlaybackState` and never learn that a choice was made.
///
/// There is no preference and no source selector. The listener has already
/// chosen by pressing play, and macOS has already written that choice down.
@MainActor
public final class FloorArbitratedSource: PlaybackSource {
    private let spotify: any PlaybackSource
    private let floor: NowPlayingFloorSource

    public init(spotify: any PlaybackSource, floor: NowPlayingFloorSource) {
        self.spotify = spotify
        self.floor = floor
    }

    public func currentState() throws -> PlaybackState {
        let holder = floor.holder

        switch FloorArbitration.owner(holder: holder.identifier, parent: holder.parent) {
        case .spotify:
            // A failure here — a refused Automation permission — is quiet
            // rather than fatal, and must not take the browser path down with
            // it on the next reading.
            return (try? spotify.currentState()) ?? .notRunning

        case .browser:
            return (try? floor.currentState()) ?? .notRunning

        case .nobody:
            // An empty Floor is not proof that nothing is playing. Spotify has
            // been observed playing without publishing to it, and the adapter
            // that reads it can fail to start or die at any time — it is a
            // workaround for a restriction Apple imposed once and could impose
            // again. Falling back to asking Spotify directly is what keeps this
            // dependency from ever being able to break Spotify support, which
            // is a rule the browser path is not allowed to bend.
            return (try? spotify.currentState()) ?? .notRunning

        case .unrecognised:
            // Something else genuinely owns playback. Showing Spotify's Track
            // over the top of it would be a wrong answer, not a missing one.
            return .notRunning
        }
    }
}
