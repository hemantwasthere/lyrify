import Foundation
import Testing

@testable import LyrifyCore

/// Resolves a Track's Spotify share link from its URI alone — no network
/// call, so every scenario here is a pure string transformation. Modelled on
/// `TrackTests`' own Track-URI fixtures, and on `OverlayLayoutTests`'/
/// `OverlayOriginTests`' style for a pure resolver taking inputs as
/// parameters.
@Suite("Spotify share link")
struct SpotifyShareLinkTests {
    @Test("a real Track URI resolves to its Spotify share URL")
    func realTrack() {
        let result = SpotifyShareLink.resolve(uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed")

        #expect(result == URL(string: "https://open.spotify.com/track/2X485T9Z5Ly0xyaghN73ed"))
    }

    @Test("a Non-Lyrical Item's URI resolves to nil")
    func nonLyricalItem() {
        #expect(SpotifyShareLink.resolve(uri: "spotify:ad:0123456789abcdef") == nil)
        #expect(SpotifyShareLink.resolve(uri: "spotify:episode:512ojhOuo1ktJprKbVcKyQ") == nil)
        #expect(SpotifyShareLink.resolve(uri: "spotify:local:artist:album:name:120") == nil)
    }

    @Test("no current Track (a nil URI) resolves to nil")
    func noTrack() {
        #expect(SpotifyShareLink.resolve(uri: nil) == nil)
    }

    @Test("an empty URI resolves to nil")
    func emptyURI() {
        #expect(SpotifyShareLink.resolve(uri: "") == nil)
    }

    @Test("a track URI with nothing after the prefix resolves to nil")
    func emptyID() {
        #expect(SpotifyShareLink.resolve(uri: "spotify:track:") == nil)
    }

    @Test("a malformed URI with no recognizable Spotify shape at all resolves to nil")
    func malformedURI() {
        #expect(SpotifyShareLink.resolve(uri: "not a uri at all") == nil)
        #expect(SpotifyShareLink.resolve(uri: "2X485T9Z5Ly0xyaghN73ed") == nil)
    }
}
