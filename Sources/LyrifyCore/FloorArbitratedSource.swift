import Foundation

/// What the Overlay shows, which is Spotify and nothing else.
///
/// The Floor is read to know who owns playback, but the answer only ever
/// decides whether Spotify is shown or nothing is. A browser holding the Floor
/// is not shown here at all — what it plays has no title, artist or artwork
/// worth putting where the music goes, and pasting a video's name under an
/// album cover made both look wrong. Browser audio is captioned in its own
/// window instead.
///
/// Spotify is asked over its own bridge rather than read from the Floor,
/// because the Floor does not carry the URI that keys lyrics memoisation, the
/// album the first widening step Matches on, or anything that could drive its
/// transport.
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
            // The Overlay is Spotify's, and only Spotify's. A video playing
            // elsewhere neither replaces the music nor clears it: the Track
            // someone had up stays up, artwork and lyrics and all.
            //
            // A browser is still followed — just not here. What it is playing
            // is captioned in its own window, which is the only place anything
            // about it belongs.
            return (try? spotify.currentState()) ?? .notRunning

        case .nobody:
            // An empty Floor is not proof that nothing is playing. Spotify has
            // been observed playing without publishing to it, and the adapter
            // that reads it can fail to start or die at any time — it is a
            // workaround for a restriction Apple imposed once and could impose
            // again. Asking Spotify anyway is what keeps this dependency from
            // ever being able to break Spotify support.
            return (try? spotify.currentState()) ?? .notRunning

        case .unrecognised:
            // Something else genuinely owns playback. Showing Spotify's Track
            // over the top of it would be a wrong answer, not a missing one.
            return .notRunning
        }
    }
}
