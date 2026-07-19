import Foundation
import Testing

@testable import LyrifyCore

/// LRCLIB serves Synced Lyrics as LRC-style timestamped text. These tests pin
/// down how that text becomes Lyric Lines — each line's text with the
/// Playback Position at which it begins.
@Suite("Synced lyrics parser")
struct SyncedLyricsParserTests {
    @Test("a timestamped line becomes a Lyric Line with its start")
    func singleLine() throws {
        let lines = try SyncedLyricsParser.parse("[01:23.45] One by one all the days")

        #expect(lines == [LyricLine(text: "One by one all the days", start: 83.45)])
    }

    /// The overlay walks lines forward; the parser owns the ordering
    /// guarantee, wherever the source put them.
    @Test("lines are answered in start-time order")
    func ordering() throws {
        let lines = try SyncedLyricsParser.parse(
            """
            [00:20.00] second
            [00:10.00] first
            [00:30.00] third
            """
        )

        #expect(lines.map(\.text) == ["first", "second", "third"])
    }

    /// An empty-text line is how the source marks an Instrumental Gap; it
    /// must survive as a Lyric Line, not vanish.
    @Test("an empty-text line is preserved as an Instrumental Gap marker")
    func instrumentalGapMarker() throws {
        let lines = try SyncedLyricsParser.parse("[00:05.00] words\n[00:15.00]")

        #expect(lines == [
            LyricLine(text: "words", start: 5),
            LyricLine(text: "", start: 15),
        ])
    }

    /// LRC ID tags (`[ar:…]`, `[ti:…]`) are metadata, not malformed
    /// timestamps.
    @Test("metadata tags and blank lines are skipped")
    func metadataSkipped() throws {
        let lines = try SyncedLyricsParser.parse(
            """
            [ar: Tame Impala]
            [ti: Let It Happen]

            [00:10.00] first
            """
        )

        #expect(lines == [LyricLine(text: "first", start: 10)])
    }

    /// Plain Lyrics carry no timestamps, so they yield nothing — which the
    /// provider will treat as a miss. Yielding nothing is not an error.
    @Test("text with no timestamps yields an empty result")
    func plainTextYieldsNothing() throws {
        let lines = try SyncedLyricsParser.parse("Just words\non their own lines")

        #expect(lines.isEmpty)
    }

    @Test("a millisecond fraction converts as precisely as a centisecond one")
    func millisecondFraction() throws {
        let lines = try SyncedLyricsParser.parse("[00:01.500] half past one")

        #expect(lines == [LyricLine(text: "half past one", start: 1.5)])
    }

    /// The compressed LRC form: one text sung at several Playback Positions
    /// (a repeated chorus). Leaving the extra stamps in the text would show
    /// broken markup as lyrics.
    @Test("a line with several timestamps yields a Lyric Line per timestamp")
    func repeatedTimestamps() throws {
        let lines = try SyncedLyricsParser.parse("[00:50.00][00:10.00] chorus")

        #expect(lines == [
            LyricLine(text: "chorus", start: 10),
            LyricLine(text: "chorus", start: 50),
        ])
    }

    @Test("malformed timestamps are specific errors, not guesses")
    func malformedTimestamps() {
        #expect(throws: SyncedLyricsParser.ParseError.malformedTimestamp("00:xx.00")) {
            try SyncedLyricsParser.parse("[00:xx.00] words")
        }
        #expect(throws: SyncedLyricsParser.ParseError.malformedTimestamp("00:75.00")) {
            try SyncedLyricsParser.parse("[00:75.00] a 75-second minute")
        }
        #expect(throws: SyncedLyricsParser.ParseError.unterminatedTimestamp("[00:12.34 words")) {
            try SyncedLyricsParser.parse("[00:12.34 words")
        }
    }

    /// `UInt("+5")` quietly parses in Swift; a signed component must be a
    /// malformed timestamp, not a guess.
    @Test("signed digits are rejected")
    func signedDigits() {
        #expect(throws: SyncedLyricsParser.ParseError.malformedTimestamp("00:+5.00")) {
            try SyncedLyricsParser.parse("[00:+5.00] plus")
        }
        #expect(throws: SyncedLyricsParser.ParseError.malformedTimestamp("00:10.+5")) {
            try SyncedLyricsParser.parse("[00:10.+5] plus fraction")
        }
    }
}
