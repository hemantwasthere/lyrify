import Foundation
import Testing

@testable import LyrifyCore

/// Who owns playback, decided from the Now Playing Floor alone. A pure
/// decision: no Players, no adapter, no Apple Events.
@Suite("Floor arbitration")
struct FloorArbitrationTests {
    private func owner(_ holder: String?, parent: String? = nil) -> FloorArbitration.Owner {
        FloorArbitration.owner(holder: holder, parent: parent)
    }

    @Test("Spotify owning the Floor is followed as Spotify")
    func spotifyOwns() {
        #expect(owner("com.spotify.client") == .spotify)
    }

    @Test("a browser owning the Floor is followed as a browser")
    func browserOwns() {
        #expect(owner("com.google.Chrome") == .browser)
        #expect(owner("company.thebrowser.Browser") == .browser)
        #expect(owner("com.apple.Safari") == .browser)
    }

    /// The Floor is single-valued: when nobody holds it, nothing is playing
    /// anywhere.
    @Test("no owner at all is nobody")
    func noOwner() {
        #expect(owner(nil) == .nobody)
    }

    /// Showing another application's media as though it were a video would be a
    /// wrong Track, not a missing one.
    @Test("an application that is neither Spotify nor a browser is not followed")
    func unrecognisedOwner() {
        #expect(owner("com.apple.Music") == .unrecognised)
        #expect(owner("org.videolan.vlc") == .unrecognised)
        #expect(owner("com.apple.QuickTimePlayerX") == .unrecognised)
    }

    /// No browser was ever observed publishing from a helper process — see
    /// `docs/findings/2026-08-02-now-playing-floor.md` — so this is defence
    /// against a shape the adapter documents rather than one seen in the wild.
    /// It costs nothing, and its absence is not a defect.
    @Test("a helper process is resolved through the application behind it")
    func helperResolvedThroughParent() {
        #expect(owner("com.google.Chrome.helper", parent: "com.google.Chrome") == .browser)
        #expect(owner("com.spotify.client.helper", parent: "com.spotify.client") == .spotify)
    }

    /// The publishing identity is preferred; the parent only answers for what
    /// the publisher could not.
    @Test("a recognised publisher wins over its parent")
    func publisherWinsOverParent() {
        #expect(owner("com.google.Chrome", parent: "com.apple.Music") == .browser)
    }

    @Test("a helper of something unrecognised stays unrecognised")
    func unrecognisedHelper() {
        #expect(owner("com.example.helper", parent: "com.example.app") == .unrecognised)
    }
}
