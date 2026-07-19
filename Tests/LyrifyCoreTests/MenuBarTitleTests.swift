import Foundation
import Testing

@testable import LyrifyCore

/// What the menu bar actually reads, for each state Lyrify can be in.
@Suite("Menu bar title")
struct MenuBarTitleTests {
    private func track(
        name: String = "Let It Happen",
        artist: String = "Tame Impala"
    ) -> Track {
        Track(
            uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed",
            name: name,
            artist: artist,
            album: "Currents",
            duration: 467.586
        )
    }

    @Test("a playing track reads as name and artist")
    func playing() {
        let title = MenuBarTitle.text(for: .playing(track(), position: 12))

        #expect(title == "Let It Happen — Tame Impala")
    }

    @Test("a paused track still names the track")
    func paused() {
        let title = MenuBarTitle.text(for: .paused(track(), position: 12))

        #expect(title == "Let It Happen — Tame Impala")
    }

    /// Spotify not running is a normal, quiet state — not an error.
    @Test("nothing playing produces no title")
    func quietStates() {
        #expect(MenuBarTitle.text(for: .notRunning) == nil)
        #expect(MenuBarTitle.text(for: .stopped) == nil)
    }

    @Test("a long title is truncated so it cannot crowd out the menu bar")
    func truncation() {
        let title = MenuBarTitle.text(
            for: .playing(
                track(
                    name: String(repeating: "long name ", count: 12),
                    artist: String(repeating: "long artist ", count: 12)
                ),
                position: 0
            )
        )

        let text = try! #require(title)
        #expect(text.count <= MenuBarTitle.maximumLength)
        #expect(text.hasSuffix("…"))
    }

    @Test("a title that just fits is left alone")
    func noUnnecessaryTruncation() throws {
        let title = try #require(MenuBarTitle.text(for: .playing(track(), position: 0)))

        #expect(title.hasSuffix("…") == false)
    }
}
