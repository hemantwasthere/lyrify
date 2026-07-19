import Foundation
import Testing

@testable import LyrifyCore

/// Spotify's broadcast playback-state notification carries a user-info
/// dictionary. These tests pin down how that payload becomes a
/// `PlaybackState` — including the same milliseconds trap ADR-0002 records
/// for the scripting bridge.
@Suite("Spotify notification payload")
struct SpotifyNotificationPayloadTests {
    private func payload(
        playerState: Any = "Playing",
        trackID: Any = "spotify:track:2X485T9Z5Ly0xyaghN73ed",
        name: Any = "Let It Happen",
        artist: Any = "Tame Impala",
        album: Any = "Currents",
        durationMilliseconds: Any = 467586,
        positionSeconds: Any = 440.904
    ) -> [AnyHashable: Any] {
        [
            "Player State": playerState,
            "Track ID": trackID,
            "Name": name,
            "Artist": artist,
            "Album": album,
            "Duration": durationMilliseconds,
            "Playback Position": positionSeconds,
        ]
    }

    @Test("a playing payload parses into every field")
    func playing() throws {
        let state = try SpotifyNotificationPayload.parse(payload())

        #expect(state.isPlaying)
        let track = try #require(state.track)
        #expect(track.uri == "spotify:track:2X485T9Z5Ly0xyaghN73ed")
        #expect(track.name == "Let It Happen")
        #expect(track.artist == "Tame Impala")
        #expect(track.album == "Currents")
        #expect(state.position == 440.904)
    }

    /// ADR-0002's trap holds here too: the notification's `Duration` is
    /// milliseconds, while `Playback Position` really is seconds.
    @Test("duration is milliseconds and is converted to seconds")
    func durationIsMilliseconds() throws {
        let state = try SpotifyNotificationPayload.parse(
            payload(durationMilliseconds: 467586)
        )

        let track = try #require(state.track)
        #expect(abs(track.duration - 467.586) < 0.0005)
    }

    @Test("a paused payload keeps its position")
    func paused() throws {
        let state = try SpotifyNotificationPayload.parse(payload(playerState: "Paused"))

        #expect(state.isPlaying == false)
        #expect(state.track != nil)
        #expect(state.position == 440.904)
    }

    /// Spotify posts `Stopped` with no track fields at all — when playback
    /// stops and when the app quits. It must parse without them.
    @Test("a stopped payload has no track and needs no track fields")
    func stopped() throws {
        let state = try SpotifyNotificationPayload.parse(["Player State": "Stopped"])

        #expect(state == .stopped)
    }

    @Test("a missing field is a specific error, not a guess")
    func missingField() {
        var incomplete = payload()
        incomplete.removeValue(forKey: "Artist")

        #expect(throws: SpotifyNotificationPayload.ParseError.missingKey("Artist")) {
            try SpotifyNotificationPayload.parse(incomplete)
        }
    }

    /// A present-but-wrong-typed field is a different defect from an absent
    /// one; the error must say which happened.
    @Test("a wrong-typed field is reported as invalid, not missing")
    func wrongType() {
        #expect(throws: SpotifyNotificationPayload.ParseError.invalidValue(key: "Name")) {
            try SpotifyNotificationPayload.parse(payload(name: 42))
        }
        #expect(throws: SpotifyNotificationPayload.ParseError.invalidValue(key: "Duration")) {
            try SpotifyNotificationPayload.parse(payload(durationMilliseconds: "soon"))
        }
    }

    /// Parity with the script parser's `isFinite` guard: a NaN or infinite
    /// position must never be anchored into the clock.
    @Test("a non-finite number is rejected")
    func nonFiniteNumber() {
        #expect(throws: SpotifyNotificationPayload.ParseError.invalidValue(key: "Playback Position")) {
            try SpotifyNotificationPayload.parse(payload(positionSeconds: Double.nan))
        }
    }

    /// `true` bridges to `NSNumber`, so without a guard it would parse as a
    /// one-millisecond duration rather than a wrong type.
    @Test("a boolean is not a number")
    func booleanIsNotANumber() {
        #expect(throws: SpotifyNotificationPayload.ParseError.invalidValue(key: "Duration")) {
            try SpotifyNotificationPayload.parse(payload(durationMilliseconds: true))
        }
    }

    @Test("an unknown player state is rejected")
    func unknownPlayerState() {
        #expect(throws: SpotifyNotificationPayload.ParseError.unknownPlayerState("Buffering")) {
            try SpotifyNotificationPayload.parse(payload(playerState: "Buffering"))
        }
    }
}
