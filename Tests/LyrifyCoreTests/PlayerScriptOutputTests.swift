import Foundation
import Testing

@testable import LyrifyCore

/// The scripting bridge hands us one delimited line. These tests pin down how
/// that line becomes a `PlaybackState`, including the units trap recorded in
/// ADR-0002.
@Suite("Player script output")
struct PlayerScriptOutputTests {
    private let sep = PlayerScriptOutput.fieldSeparator

    private func line(
        state: String = "playing",
        uri: String = "spotify:track:2X485T9Z5Ly0xyaghN73ed",
        name: String = "Let It Happen",
        artist: String = "Tame Impala",
        album: String = "Currents",
        durationMilliseconds: String = "467586",
        positionSeconds: String = "440.904998779297"
    ) -> String {
        [state, uri, name, artist, album, durationMilliseconds, positionSeconds]
            .joined(separator: sep)
    }

    @Test("a playing track parses into every field")
    func playingTrack() throws {
        let state = try PlayerScriptOutput.parse(line())

        #expect(state.isPlaying)
        let track = try #require(state.track)
        #expect(track.uri == "spotify:track:2X485T9Z5Ly0xyaghN73ed")
        #expect(track.name == "Let It Happen")
        #expect(track.artist == "Tame Impala")
        #expect(track.album == "Currents")
        #expect(state.position == 440.904998779297)
    }

    /// ADR-0002: Spotify's scripting definition claims `duration` is seconds,
    /// but it really returns milliseconds. Getting this wrong silently breaks
    /// every lyrics lookup, because matching is done on duration in seconds.
    @Test("duration is milliseconds and is converted to seconds")
    func durationIsMilliseconds() throws {
        let state = try PlayerScriptOutput.parse(line(durationMilliseconds: "467586"))

        let track = try #require(state.track)
        #expect(abs(track.duration - 467.586) < 0.0005)
    }

    @Test("duration rounds to the whole second a lyrics lookup needs")
    func durationInWholeSeconds() throws {
        let state = try PlayerScriptOutput.parse(line(durationMilliseconds: "467586"))

        let track = try #require(state.track)
        #expect(track.durationInWholeSeconds == 468)
    }

    @Test("a paused track keeps its position")
    func pausedTrack() throws {
        let state = try PlayerScriptOutput.parse(line(state: "paused"))

        #expect(state.isPlaying == false)
        #expect(state.track != nil)
        #expect(state.position == 440.904998779297)
    }

    @Test("a stopped player has no track")
    func stoppedPlayer() throws {
        let state = try PlayerScriptOutput.parse("stopped")

        #expect(state == .stopped)
        #expect(state.track == nil)
        #expect(state.position == nil)
    }

    @Test("track and artist names survive punctuation")
    func awkwardMetadata() throws {
        let state = try PlayerScriptOutput.parse(
            line(name: "Say It Ain't So", artist: "Weezer | ünicode")
        )

        let track = try #require(state.track)
        #expect(track.name == "Say It Ain't So")
        #expect(track.artist == "Weezer | ünicode")
    }

    @Test("an unknown player state is rejected")
    func unknownState() {
        #expect(throws: PlayerScriptOutput.ParseError.self) {
            try PlayerScriptOutput.parse(line(state: "buffering"))
        }
    }

    @Test("a truncated record is rejected rather than half-read")
    func truncatedRecord() {
        let truncated = ["playing", "spotify:track:abc", "Name"].joined(separator: sep)

        #expect(throws: PlayerScriptOutput.ParseError.self) {
            try PlayerScriptOutput.parse(truncated)
        }
    }

    @Test("a non-numeric duration is rejected")
    func nonNumericDuration() {
        #expect(throws: PlayerScriptOutput.ParseError.self) {
            try PlayerScriptOutput.parse(line(durationMilliseconds: "unknown"))
        }
    }

    @Test("a non-numeric position is rejected")
    func nonNumericPosition() {
        #expect(throws: PlayerScriptOutput.ParseError.self) {
            try PlayerScriptOutput.parse(line(positionSeconds: ""))
        }
    }

    @Test("empty output is rejected")
    func emptyOutput() {
        #expect(throws: PlayerScriptOutput.ParseError.self) {
            try PlayerScriptOutput.parse("   \n ")
        }
    }

    @Test("surrounding whitespace from the scripting bridge is tolerated")
    func trailingNewline() throws {
        let state = try PlayerScriptOutput.parse("\n" + line() + "\n")

        #expect(state.track?.name == "Let It Happen")
    }
}
