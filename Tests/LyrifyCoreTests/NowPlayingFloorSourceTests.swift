import Foundation
import Testing

@testable import LyrifyCore

/// The browser Player, driven by fed lines rather than a subprocess. No
/// adapter is built, launched or bundled by any test here.
@Suite("Now Playing Floor source")
@MainActor
struct NowPlayingFloorSourceTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    private static let chromeVideo = #"""
        {"bundleIdentifier": "com.google.Chrome", "title": "Never Gonna Give You Up",
         "artist": "Rick Astley", "duration": 213.061, "elapsedTime": 12, "playing": true}
        """#

    private static let spotifyTrack = #"""
        {"bundleIdentifier": "com.spotify.client", "title": "Sesame Syrup",
         "artist": "Cigarettes After Sex", "duration": 303.296, "elapsedTime": 86.5, "playing": true}
        """#

    @Test("a browser holding the Floor is answered as a playing Track")
    func browserOnTheFloor() {
        let source = NowPlayingFloorSource()
        source.receive(line(Self.chromeVideo))

        guard case .playing(let track, let position) = try? source.currentState() else {
            Issue.record("expected playing")
            return
        }
        #expect(track.name == "Never Gonna Give You Up")
        #expect(track.artist == "Rick Astley")
        #expect(position == 12)
    }

    /// Spotify publishes to the Floor too, and it is followed over Apple
    /// Events instead — where it carries its URI, its album and its transport
    /// controls. Answering it here would produce a second, poorer Track for
    /// the same music.
    @Test("Spotify holding the Floor is not answered as a browser Track")
    func spotifyOnTheFloorIsNotOurs() {
        let source = NowPlayingFloorSource()
        source.receive(line(Self.spotifyTrack))

        #expect(try! source.currentState() == .notRunning)
    }

    /// A paused application keeps the Floor, so the Floor emptying is the only
    /// thing that means nothing is playing anywhere.
    @Test("the Floor emptying leaves no stale Track behind")
    func floorEmptying() {
        let source = NowPlayingFloorSource()
        source.receive(line(Self.chromeVideo))
        source.receive(line("null"))

        #expect(try! source.currentState() == .notRunning)
    }

    /// The adapter writes diagnostics to the same output it writes readings
    /// to — an infinite duration produces one. A line that is not a reading is
    /// dropped rather than throwing, because the stream is the only source of
    /// Anchors the browser path has and losing it over a log line would be a
    /// worse failure than ignoring the line.
    @Test("a diagnostic line is ignored without disturbing what is playing")
    func diagnosticLinesAreIgnored() {
        let source = NowPlayingFloorSource()
        source.receive(line(Self.chromeVideo))
        source.receive(line("Invalid JSON value type in dictionary for key 'duration': inf"))

        guard case .playing(let track, _) = try? source.currentState() else {
            Issue.record("expected the Track to survive a diagnostic line")
            return
        }
        #expect(track.artist == "Rick Astley")
    }

    /// Nothing has been fed yet — the adapter has not started, or could not be
    /// found at all because the app is running unbundled. Quiet, not broken.
    @Test("a source that has heard nothing is quiet")
    func heardNothing() {
        #expect(try! NowPlayingFloorSource().currentState() == .notRunning)
    }

    /// Diffs arrive against whatever is on the Floor, so the source has to keep
    /// merging rather than reading each line afresh.
    @Test("a diff advances the position without losing the Track")
    func diffsAdvancePosition() {
        let source = NowPlayingFloorSource()
        source.receive(line(Self.chromeVideo))
        source.receive(line(#"{"type": "data", "diff": true, "payload": {"elapsedTime": 99.5}}"#))

        guard case .playing(let track, let position) = try? source.currentState() else {
            Issue.record("expected playing")
            return
        }
        #expect(track.artist == "Rick Astley")
        #expect(position == 99.5)
    }
}
