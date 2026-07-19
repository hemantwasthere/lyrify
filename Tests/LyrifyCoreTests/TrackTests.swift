import Foundation
import Testing

@testable import LyrifyCore

/// The URI is how a Track is told apart from a Non-Lyrical Item — an
/// advertisement, a podcast episode, or a local file.
@Suite("Track")
struct TrackTests {
    private func track(uri: String) -> Track {
        Track(uri: uri, name: "n", artist: "a", album: "al", duration: 100)
    }

    @Test("a Spotify track URI is lyrical")
    func lyrical() {
        #expect(track(uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed").isLyrical)
    }

    @Test("ads, episodes and local files are Non-Lyrical Items")
    func nonLyrical() {
        #expect(track(uri: "spotify:ad:0123456789abcdef").isLyrical == false)
        #expect(track(uri: "spotify:episode:512ojhOuo1ktJprKbVcKyQ").isLyrical == false)
        #expect(track(uri: "spotify:local:artist:album:name:120").isLyrical == false)
    }
}
