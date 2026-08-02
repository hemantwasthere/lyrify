import Foundation

/// The browser Player: a `PlaybackSource` fed by the adapter's stream.
///
/// Holds the merged `NowPlayingFloor` and answers what it reports, so the
/// Anchor stream follows a browser exactly as it follows Spotify and never
/// learns which it is talking to.
///
/// Deliberately knows nothing about subprocesses. Lines are handed to it by
/// whoever runs the adapter, which is what lets the whole browser Player be
/// driven in tests by feeding it text — no adapter built, launched or bundled.
@MainActor
public final class NowPlayingFloorSource: PlaybackSource {
    private var floor = NowPlayingFloor()

    /// Applications whose playback is followed some better way, and so must not
    /// be answered here.
    ///
    /// Spotify publishes to the Floor like everything else, but Lyrify follows
    /// it over Apple Events instead — where it carries the URI that keys lyrics
    /// memoisation, the album the first widening step Matches on, and the
    /// transport controls. Answering it here as well would produce a second,
    /// poorer Track for the same music.
    private let notOurs: Set<String>

    public static let spotifyBundleIdentifier = "com.spotify.client"

    public init(notOurs: Set<String> = [NowPlayingFloorSource.spotifyBundleIdentifier]) {
        self.notOurs = notOurs
    }

    /// Merges one line of the adapter's output.
    ///
    /// A line that is not a reading is dropped rather than raised. The adapter
    /// writes diagnostics to the same output it writes readings to — live
    /// content's infinite duration produces one every time it is reported — and
    /// this stream is the only source of Anchors the browser path has. Losing
    /// it over a log line would be a far worse failure than ignoring the line.
    public func receive(_ line: Data) {
        try? floor.merge(line)
    }

    /// Everything the Floor held is forgotten — for the adapter stopping,
    /// failing to start, or never having been found at all. The browser path
    /// goes quiet; nothing about Spotify is affected.
    public func forget() {
        floor = NowPlayingFloor()
    }

    public func currentState() throws -> PlaybackState {
        guard let holder = floor.holder, notOurs.contains(holder) == false else {
            return .notRunning
        }
        return floor.state
    }
}
