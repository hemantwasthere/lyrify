import Foundation
import Testing

@testable import LyrifyCore

/// Two Players behind one port, driven by fakes on both sides.
@Suite("Preferred playback source")
@MainActor
struct PreferredPlaybackSourceTests {
    final class Fixed: PlaybackSource {
        private let answer: () throws -> PlaybackState
        private(set) var asked = 0

        init(_ state: PlaybackState) { answer = { state } }
        init(failing error: @escaping @autoclosure () -> any Error) {
            answer = { throw error() }
        }

        func currentState() throws -> PlaybackState {
            asked += 1
            return try answer()
        }
    }

    struct Refused: Error {}

    private static func track(_ name: String) -> Track {
        Track(uri: "spotify:track:\(name)", name: name, artist: "a", album: "al", duration: 100)
    }

    private static let video = Track(
        floorBundleIdentifier: "com.google.Chrome",
        title: "a video",
        channel: "a channel",
        duration: 200
    )

    @Test("the preferred Player wins whenever it is running")
    func preferredWins() {
        let spotify = Fixed(.playing(Self.track("song"), position: 3))
        let browser = Fixed(.playing(Self.video, position: 9))
        let players = PreferredPlaybackSource(preferred: spotify, fallback: browser)

        #expect(try! players.currentState().track?.name == "song")
        #expect(browser.asked == 0)
    }

    /// Someone who paused a song and has not closed Spotify has not asked to be
    /// shown something else.
    @Test("a paused preferred Player still wins")
    func pausedPreferredStillWins() {
        let spotify = Fixed(.paused(Self.track("song"), position: 3))
        let browser = Fixed(.playing(Self.video, position: 9))
        let players = PreferredPlaybackSource(preferred: spotify, fallback: browser)

        #expect(try! players.currentState().track?.name == "song")
    }

    @Test("the fallback is followed once the preferred Player is not running")
    func fallbackTakesOver() {
        let spotify = Fixed(.notRunning)
        let browser = Fixed(.playing(Self.video, position: 9))
        let players = PreferredPlaybackSource(preferred: spotify, fallback: browser)

        #expect(try! players.currentState().track?.artist == "a channel")
    }

    /// A refused Automation permission must not take the browser path down
    /// with it.
    @Test("a preferred Player that fails yields to the fallback")
    func failingPreferredYields() {
        let spotify = Fixed(failing: Refused())
        let browser = Fixed(.playing(Self.video, position: 9))
        let players = PreferredPlaybackSource(preferred: spotify, fallback: browser)

        #expect(try! players.currentState().track?.artist == "a channel")
    }

    @Test("neither Player running is quiet, not an error")
    func neitherRunning() {
        let players = PreferredPlaybackSource(
            preferred: Fixed(failing: Refused()),
            fallback: Fixed(failing: Refused())
        )
        #expect(try! players.currentState() == .notRunning)
    }
}
