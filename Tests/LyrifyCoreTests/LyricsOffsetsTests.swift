import Foundation
import Testing

@testable import LyrifyCore

/// The Offset, as a pure value: what is remembered per Track, and what it does
/// to the Playback Position a Lyric Line is chosen by.
@Suite("Lyrics offsets")
struct LyricsOffsetsTests {
    private let uri = "browser:com.google.Chrome:a video"
    private let other = "spotify:track:2X485T9Z5Ly0xyaghN73ed"

    @Test("a Track nobody has corrected has no Offset and shifts nothing")
    func noOffset() {
        let offsets = LyricsOffsets()

        #expect(offsets.offset(for: uri) == 0)
        #expect(offsets.adjusted(90, for: uri) == 90)
    }

    /// A video with an intro card is the same recording, started late. Holding
    /// the lyrics back is what lines it up, so a positive Offset looks *earlier*
    /// into the Synced Lyrics than the Playback Position alone would.
    @Test("a positive Offset holds the lyrics back")
    func positiveOffset() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 8)

        #expect(offsets.offset(for: uri) == 8 * LyricsOffsets.step)
        #expect(offsets.adjusted(90, for: uri) == 90 - 8 * LyricsOffsets.step)
    }

    @Test("a negative Offset runs the lyrics ahead")
    func negativeOffset() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: -4)

        #expect(offsets.offset(for: uri) == -4 * LyricsOffsets.step)
        #expect(offsets.adjusted(90, for: uri) == 90 + 4 * LyricsOffsets.step)
    }

    @Test("nudges accumulate and can be walked back to nothing")
    func nudgesAccumulate() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 3)
        offsets.nudge(uri, by: 2)
        #expect(offsets.offset(for: uri) == 5 * LyricsOffsets.step)

        offsets.nudge(uri, by: -5)
        #expect(offsets.offset(for: uri) == 0)
    }

    @Test("an Offset can be cleared outright")
    func clearing() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 9)
        offsets.clear(uri)

        #expect(offsets.offset(for: uri) == 0)
        #expect(offsets.adjusted(30, for: uri) == 30)
    }

    /// Correcting one Track must not disturb another; the Offset belongs to the
    /// recording, not to the app.
    @Test("Offsets belong to one Track each")
    func offsetsArePerTrack() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 6)

        #expect(offsets.offset(for: other) == 0)
        #expect(offsets.adjusted(50, for: other) == 50)
    }

    /// An Offset large enough to look before the first Lyric Line answers a
    /// position before the Track began. Nothing here clamps it: an Intro Gap is
    /// a real answer, and `LineSelection` already knows how to give it.
    @Test("an Offset past the start looks before the first Lyric Line")
    func pastTheStart() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 40)

        let adjusted = offsets.adjusted(2, for: uri)
        #expect(adjusted < 0)

        let lyrics = [
            LyricLine(text: "first", start: 0),
            LyricLine(text: "second", start: 10),
        ]
        #expect(LineSelection.at(adjusted, in: lyrics).content == .introGap)
    }

    /// And one large enough the other way lands past the last line, which is
    /// simply the last line still being Active.
    @Test("an Offset past the end lands on the last Lyric Line")
    func pastTheEnd() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: -Int(LyricsOffsets.limit / LyricsOffsets.step))

        let lyrics = [
            LyricLine(text: "first", start: 0),
            LyricLine(text: "second", start: 10),
        ]
        let adjusted = offsets.adjusted(20, for: uri)
        guard case .lines(let active, let next) = LineSelection.at(adjusted, in: lyrics).content
        else {
            Issue.record("expected a line")
            return
        }
        #expect(active.text == "second")
        #expect(next == nil)
    }

    /// A listener holding the button down should not be able to push the lyrics
    /// somewhere they can never be recovered from.
    @Test("an Offset cannot be nudged beyond its limit in either direction")
    func limited() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 10_000)
        #expect(offsets.offset(for: uri) == LyricsOffsets.limit)

        offsets.nudge(uri, by: -20_000)
        #expect(offsets.offset(for: uri) == -LyricsOffsets.limit)
    }

    /// What is remembered has to survive a restart, so it must round-trip
    /// through something a preference can hold.
    @Test("Offsets round-trip through their stored form")
    func roundTrip() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 7)
        offsets.nudge(other, by: -3)

        let restored = LyricsOffsets(stored: offsets.stored)
        #expect(restored == offsets)
        #expect(restored.offset(for: uri) == 7 * LyricsOffsets.step)
        #expect(restored.offset(for: other) == -3 * LyricsOffsets.step)
    }

    /// A Track corrected back to nothing is not worth remembering, and a store
    /// that only grows is a store that eventually holds every video ever
    /// watched.
    @Test("a Track returned to zero is forgotten rather than stored as zero")
    func zeroIsNotStored() {
        var offsets = LyricsOffsets()
        offsets.nudge(uri, by: 4)
        offsets.nudge(uri, by: -4)

        #expect(offsets.stored.isEmpty)
    }
}
