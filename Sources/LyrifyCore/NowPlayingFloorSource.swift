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
///
/// **`currentState()` has no caller today, and that is on purpose.** Showing a
/// video where the music goes put its title under an album cover belonging to a
/// paused song, which made both look wrong, so `FloorArbitratedSource` answers
/// Spotify for a browser instead. Everything below this line still runs and is
/// still tested — the reading, the Track it builds, the artist and name
/// `VideoTitle` reads out of a video's title — it simply is not drawn anywhere.
///
/// Restoring it is one line, in `FloorArbitratedSource.currentState()`:
///
/// ```swift
/// case .browser:
///     return (try? floor.currentState()) ?? .notRunning
/// ```
///
/// `holder` and `holderProcess` are *not* dormant: Live Captions reads them to
/// know which process to listen to.
@MainActor
public final class NowPlayingFloorSource: PlaybackSource {
    private var floor = NowPlayingFloor()

    public init() {}

    /// Which application holds the Floor, and the one behind it if the
    /// publisher is a helper. Exposed so arbitration can decide whose playback
    /// this is; that decision is deliberately not made here.
    public var holder: (identifier: String?, parent: String?) {
        (floor.holder, floor.holderParent)
    }

    /// The process making the sound, when the Floor names one.
    public var holderProcess: Int? { floor.holderProcess }

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
        floor.state
    }
}
