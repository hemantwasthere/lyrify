import Foundation
import Testing

@testable import LyrifyCore

/// What the Overlay shows. Spotify is a fake; the browser is the real Floor
/// source fed lines, because that is how it behaves in the app.
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

    /// A video has no title, artist or artwork worth putting where the music
    /// goes. Showing one there put a video's name under an album cover, which
    /// made both look wrong; what a browser plays is captioned in its own
    /// window instead.
    @Test("a browser holding the Floor is never shown here")
    func browserIsNeverShown() {
        let spotify = FakeSpotify()
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.google.Chrome", title: "a video"))

        #expect(try! players(spotify, floor).currentState() == .notRunning)
    }

    /// And it does not clear the music either. Someone who paused a song and
    /// started a video still has their Track, its artwork and its lyrics.
    @Test("a browser taking the Floor leaves a paused Spotify Track on screen")
    func browserDoesNotClearSpotify() {
        let spotify = FakeSpotify()
        spotify.state = .paused(Self.song, position: 120)
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.google.Chrome", title: "a video"))

        guard case .paused(let track, let position) = try! players(spotify, floor).currentState()
        else {
            Issue.record("expected Spotify's paused Track to survive")
            return
        }
        #expect(track.name == "Sesame Syrup")
        #expect(track.album == "Crush")
        #expect(position == 120)
    }

    /// A browser coming and going changes nothing about what is shown.
    @Test("the Floor moving between a browser and Spotify keeps showing Spotify")
    func floorMovingKeepsSpotify() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 12)
        let floor = NowPlayingFloorSource()
        let players = players(spotify, floor)

        floor.receive(reading("com.google.Chrome", title: "a video"))
        #expect(try! players.currentState().track?.name == "Sesame Syrup")

        floor.receive(reading("com.spotify.client", title: "Sesame Syrup"))
        #expect(try! players.currentState().track?.name == "Sesame Syrup")
    }

    /// A paused Player still holds the Floor and is still worth showing — the
    /// Overlay has always shown a paused Spotify Track.
    @Test("a paused Spotify is still answered, not treated as nothing playing")
    func pausedSpotifyIsStillAnswered() {
        let spotify = FakeSpotify()
        spotify.state = .paused(Self.song, position: 3)
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.spotify.client", title: "Sesame Syrup"))

        guard case .paused(let track, _) = try! players(spotify, floor).currentState() else {
            Issue.record("expected a paused Track")
            return
        }
        #expect(track.name == "Sesame Syrup")
    }

    /// Something else genuinely owns playback, and showing Spotify's Track over
    /// the top of it would be a wrong answer rather than a missing one.
    @Test("an application that is neither Spotify nor a browser is not shown")
    func unrecognisedHolder() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 5)
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.apple.Music", title: "something else"))

        #expect(try! players(spotify, floor).currentState() == .notRunning)
        #expect(spotify.asked == 0)
    }

    @Test("nobody holding the Floor, and nothing running, is quiet")
    func nobodyHolds() {
        #expect(try! players(FakeSpotify(), NowPlayingFloorSource()).currentState() == .notRunning)
    }

    /// An empty Floor is not proof that nothing is playing. Spotify has been
    /// observed playing without publishing to the Floor at all, and the adapter
    /// that reads it can fail to start or die at any moment. Asking Spotify
    /// anyway is what stops a workaround for one of Apple's restrictions from
    /// taking Spotify support down with it.
    @Test("an empty Floor still follows a Spotify that is running")
    func emptyFloorFallsBackToSpotify() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 42)

        let state = try! players(spotify, NowPlayingFloorSource()).currentState()
        #expect(state.track?.name == "Sesame Syrup")
        #expect(state.position == 42)
    }

    /// The same protection when the adapter dies mid-session: the Floor is
    /// emptied, and Spotify carries on being followed rather than the Overlay
    /// going blank.
    @Test("the adapter dying mid-session leaves Spotify on screen")
    func floorEmptyingHandsBackToSpotify() {
        let spotify = FakeSpotify()
        spotify.state = .playing(Self.song, position: 7)
        let floor = NowPlayingFloorSource()
        let players = players(spotify, floor)

        floor.receive(reading("com.google.Chrome", title: "a video"))
        #expect(try! players.currentState().track?.name == "Sesame Syrup")

        // What `NowPlayingFloorProcess` does when the adapter exits.
        floor.forget()
        #expect(try! players.currentState().track?.name == "Sesame Syrup")
    }

    /// A refused Automation permission must not become a crash or a broken
    /// title.
    @Test("a failing Spotify bridge is quiet rather than fatal")
    func failingSpotifyIsQuiet() {
        let spotify = FakeSpotify()
        spotify.fails = true
        let floor = NowPlayingFloorSource()
        floor.receive(reading("com.spotify.client", title: "Sesame Syrup"))

        #expect(try! players(spotify, floor).currentState() == .notRunning)
    }
}
