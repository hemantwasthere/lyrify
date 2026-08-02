import Foundation
import Testing

@testable import LyrifyCore

/// Both Players behind one port. Spotify is a fake; the browser is the real
/// Floor source fed lines, because that is how it behaves in the app.
@Suite("Floor arbitrated source")
@MainActor
struct FloorArbitratedSourceTests {
    final class FakeSpotify: PlaybackSource {
        var state: PlaybackState = .notRunning
        var fails = false
        private(set) var asked = 0

        struct Refused: Error {}

        func currentState() throws -> PlaybackState {
            asked += 1
            if fails { throw Refused() }
            return state
        }
    }

    private static let song = Track(
        uri: "spotify:track:6lnqe1urLVOV4tn0YgmnIw",
        name: "Sesame Syrup",
        artist: "Cigarettes After Sex",
        album: "Crush",
        duration: 303.296
    )

    private func reading(_ bundle: String, title: String, playing: Bool = true) -> Data {
        Data(
            """
            {"type": "data", "diff": false, "payload":
              {"bundleIdentifier": "\(bundle)", "title": "\(title)", "artist": "someone",
               "duration": 200, "elapsedTime": 5, "playing": \(playing)}}
            """.utf8)
    }

    private func players(_ spotify: FakeSpotify, _ floor: NowPlayingFloorSource)
        -> FloorArbitratedSource
    {
        FloorArbitratedSource(spotify: spotify, floor: floor)
    }

    /// The Floor says who; Spotify says what. The Track answered must be
    /// Spotify's own, carrying the URI the Floor could never supply.
    @Test("Spotify holding the Floor is answered from Spotify's own bridge")
    func spotifyHolds() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 30)
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.spotify.client", title: "Sesame Syrup"))

        let state = try! players(spotify, floor).currentState()
        #expect(state.track?.uri == "spotify:track:6lnqe1urLVOV4tn0YgmnIw")
        #expect(state.track?.album == "Crush")
        #expect(spotify.asked == 1)
    }

    /// Even with Spotify running and holding a Track, the browser wins once it
    /// takes the Floor — that is the whole point of following the system's
    /// answer rather than preferring one Player.
    @Test("a browser taking the Floor is followed even while Spotify is running")
    func browserTakesTheFloorFromSpotify() {
        let spotify = FakeSpotify()
        spotify.state = .paused(Self.song, position: 30)
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.google.Chrome", title: "a video"))

        let state = try! players(spotify, floor).currentState()
        #expect(state.track?.name == "a video")
        // Spotify is not even consulted: it does not hold the Floor.
        #expect(spotify.asked == 0)
    }

    /// The Floor moving back is all it takes; no user action, no preference.
    @Test("the Floor moving back to Spotify moves the answer back")
    func floorMovesBack() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 12)
        let floor = NowPlayingFloorSource()
        let players = players(spotify, floor)

        floor.receive(reading("com.google.Chrome", title: "a video"))
        #expect(try! players.currentState().track?.name == "a video")

        floor.receive(reading("com.spotify.client", title: "Sesame Syrup"))
        #expect(try! players.currentState().track?.uri.hasPrefix("spotify:track:") == true)
    }

    /// A paused Player still holds the Floor and is still worth showing — the
    /// Overlay has always shown a paused Spotify Track, and a paused video is
    /// no different.
    @Test("a paused holder is still answered, not treated as nothing playing")
    func pausedHolderIsStillAnswered() {
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.google.Chrome", title: "a video", playing: false))

        guard case .paused(let track, _) = try! players(FakeSpotify(), floor).currentState() else {
            Issue.record("expected a paused Track")
            return
        }
        #expect(track.name == "a video")
    }

    @Test("an application that is neither Spotify nor a browser is not shown")
    func unrecognisedHolder() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 5)
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.apple.Music", title: "something else"))

        #expect(try! players(spotify, floor).currentState() == .notRunning)
        #expect(spotify.asked == 0)
    }

    @Test("nobody holding the Floor is quiet")
    func nobodyHolds() {
        #expect(try! players(FakeSpotify(), NowPlayingFloorSource()).currentState() == .notRunning)
    }

    /// A refused Automation permission must not become a crash or a broken
    /// title, and must not stop the browser being followed next time.
    @Test("a failing Spotify bridge is quiet, and the browser still works after")
    func failingSpotifyIsQuiet() {
        let spotify = FakeSpotify()
        spotify.fails = true
        let floor = NowPlayingFloorSource()
        let players = players(spotify, floor)

        floor.receive(reading("com.spotify.client", title: "Sesame Syrup"))
        #expect(try! players.currentState() == .notRunning)

        floor.receive(reading("com.google.Chrome", title: "a video"))
        #expect(try! players.currentState().track?.name == "a video")
    }
}
