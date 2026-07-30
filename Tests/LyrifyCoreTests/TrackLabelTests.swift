import Foundation
import Testing

@testable import LyrifyCore

/// How a Track reads when it has to fit on one line.
@Suite("Track label")
struct TrackLabelTests {
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

    @Test("a track reads as name and artist")
    func nameAndArtist() {
        #expect(TrackLabel.text(for: track()) == "Let It Happen — Tame Impala")
    }

    @Test("a long label is truncated so it cannot outgrow the card")
    func truncation() {
        let text = TrackLabel.text(
            for: track(
                name: String(repeating: "long name ", count: 12),
                artist: String(repeating: "long artist ", count: 12)
            )
        )

        #expect(text.count <= TrackLabel.maximumLength)
        #expect(text.hasSuffix("…"))
    }

    @Test("a label that just fits is left alone")
    func noUnnecessaryTruncation() {
        #expect(TrackLabel.text(for: track()).hasSuffix("…") == false)
    }

    /// Truncation must not leave the ellipsis hanging off a space — that reads
    /// as a gap before it, not a continuation.
    @Test("truncation trims trailing whitespace before the ellipsis")
    func trimsBeforeEllipsis() {
        let text = TrackLabel.text(for: track(name: String(repeating: "ab ", count: 20)))

        #expect(text.hasSuffix(" …") == false)
    }
}
