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

    /// A Track observed on the Now Playing Floor rather than from Spotify. Its
    /// identity cannot be a Spotify URI, because there isn't one — but it still
    /// has to key lyrics memoisation and tell one video from the next.
    @Test("a browser Track's identity is its own, not a Spotify URI")
    func browserIdentityIsDistinct() {
        let video = Track(
            floorBundleIdentifier: "com.google.Chrome",
            title: "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)",
            channel: "Rick Astley",
            duration: 213.061
        )

        #expect(video.uri.hasPrefix("spotify:") == false)
        // Read into an artist and a name at the boundary, so that everything
        // downstream receives an ordinary Track.
        #expect(video.name == "Never Gonna Give You Up")
        #expect(video.artist == "Rick Astley")
        // Identity is composed from the raw title, so sharpening how titles are
        // read cannot orphan what has already been remembered.
        #expect(video.uri.contains("(Official Video)"))
        #expect(video.album.isEmpty)
        #expect(video.duration == 213.061)
    }

    /// Memoisation is keyed on identity, so two different videos must never
    /// collide and the same video must answer the same key every time.
    @Test("browser Tracks are told apart by title and channel, and are stable")
    func browserIdentityIsStableAndDistinguishing() {
        func video(title: String, channel: String, bundle: String = "com.google.Chrome") -> Track {
            Track(floorBundleIdentifier: bundle, title: title, channel: channel, duration: 200)
        }

        #expect(video(title: "One", channel: "A").uri == video(title: "One", channel: "A").uri)
        #expect(video(title: "One", channel: "A").uri != video(title: "Two", channel: "A").uri)
        #expect(video(title: "One", channel: "A").uri != video(title: "One", channel: "B").uri)
        // The same video in two browsers is two Tracks; nothing depends on
        // them being one, and pretending otherwise would be a guess.
        #expect(
            video(title: "One", channel: "A").uri
                != video(title: "One", channel: "A", bundle: "company.thebrowser.Browser").uri
        )
    }

    /// A video is worth looking lyrics up for; the Match either lands or it
    /// doesn't. Live content is the one case known up front to be hopeless —
    /// it reports no duration at all, and every lyrics lookup needs one.
    @Test("a browser Track is lyrical unless it has no duration to Match on")
    func browserLyricality() {
        func video(duration: TimeInterval?) -> Track {
            Track(
                floorBundleIdentifier: "com.google.Chrome",
                title: "t",
                channel: "c",
                duration: duration
            )
        }

        #expect(video(duration: 213.061).isLyrical)
        #expect(video(duration: nil).isLyrical == false)
        #expect(video(duration: .infinity).isLyrical == false)
        #expect(video(duration: nil).duration == 0)
    }
}
