import Foundation
import Testing

@testable import LyrifyCore

/// `LyricsWindow` sits on top of the unmodified `LineSelection`: instead of
/// just the Active and Next Line, it answers a whole window of lines
/// centred on the Active Line, clamped at the start and end of the Track's
/// lyrics — the seam the resizable Lyrics view scales against.
@Suite("Lyrics window")
struct LyricsWindowTests {
    private let lyrics = [
        LyricLine(text: "first", start: 10),
        LyricLine(text: "second", start: 20),
        LyricLine(text: "third", start: 30),
        LyricLine(text: "fourth", start: 40),
        LyricLine(text: "fifth", start: 50),
    ]

    @Test("a normal window centres on the Active Line with equal room either side")
    func centeredWindow() {
        let entries = LyricsWindow.resolve(at: 30, in: lyrics, lineCount: 3)

        #expect(entries == [
            LyricsWindow.Entry(line: lyrics[1], role: .before),
            LyricsWindow.Entry(line: lyrics[2], role: .active),
            LyricsWindow.Entry(line: lyrics[3], role: .after),
        ])
    }

    @Test("clamped at the start: the window borrows extra room from after instead")
    func clampedAtStart() {
        let entries = LyricsWindow.resolve(at: 10, in: lyrics, lineCount: 3)

        #expect(entries == [
            LyricsWindow.Entry(line: lyrics[0], role: .active),
            LyricsWindow.Entry(line: lyrics[1], role: .after),
            LyricsWindow.Entry(line: lyrics[2], role: .after),
        ])
    }

    @Test("clamped at the end: the window borrows extra room from before instead")
    func clampedAtEnd() {
        let entries = LyricsWindow.resolve(at: 50, in: lyrics, lineCount: 3)

        #expect(entries == [
            LyricsWindow.Entry(line: lyrics[2], role: .before),
            LyricsWindow.Entry(line: lyrics[3], role: .before),
            LyricsWindow.Entry(line: lyrics[4], role: .active),
        ])
    }

    @Test("requesting more lines than exist returns every line available")
    func moreThanAvailable() {
        let entries = LyricsWindow.resolve(at: 30, in: lyrics, lineCount: 10)

        #expect(entries.map(\.line) == lyrics)
        #expect(entries.map(\.role) == [.before, .before, .active, .after, .after])
    }

    @Test("a line count of one answers just the Active Line")
    func singleLine() {
        let entries = LyricsWindow.resolve(at: 30, in: lyrics, lineCount: 1)

        #expect(entries == [LyricsWindow.Entry(line: lyrics[2], role: .active)])
    }

    /// An even split can't be equal either side; upcoming context matters
    /// more than reviewing what already passed, so the extra line goes to
    /// `after`.
    @Test("an even line count favors an extra line after the Active Line")
    func evenCountFavorsAfter() {
        let entries = LyricsWindow.resolve(at: 30, in: lyrics, lineCount: 4)

        #expect(entries.map(\.role) == [.before, .active, .after, .after])
    }

    /// The parser preserves an empty-text Gap Marker for exactly this moment.
    /// It is a real Active Line, so the window centres on it like any other —
    /// which is what keeps the listener's place through a break in the singing
    /// instead of clearing the card and making them find it again.
    @Test("an Instrumental Gap centres on its Gap Marker, keeping the lines around it")
    func instrumentalGapKeepsContext() {
        let marked = [
            LyricLine(text: "first", start: 10),
            LyricLine(text: "second", start: 20),
            LyricLine(text: "", start: 30),
            LyricLine(text: "fourth", start: 40),
            LyricLine(text: "fifth", start: 50),
        ]

        let entries = LyricsWindow.resolve(at: 35, in: marked, lineCount: 3)

        #expect(entries == [
            LyricsWindow.Entry(line: marked[1], role: .before),
            LyricsWindow.Entry(line: marked[2], role: .active),
            LyricsWindow.Entry(line: marked[3], role: .after),
        ])
    }

    @Test("a Gap Marker after the last sung line keeps the lines that led into it")
    func trailingGapKeepsContext() {
        let marked = [
            LyricLine(text: "first", start: 10),
            LyricLine(text: "second", start: 20),
            LyricLine(text: "", start: 30),
        ]

        let entries = LyricsWindow.resolve(at: 40, in: marked, lineCount: 3)

        #expect(entries == [
            LyricsWindow.Entry(line: marked[0], role: .before),
            LyricsWindow.Entry(line: marked[1], role: .before),
            LyricsWindow.Entry(line: marked[2], role: .active),
        ])
    }

    /// The other half of the distinction above: an Intro Gap has no Active
    /// Line at all, because no Lyric Line has been reached yet. There is no
    /// context to keep, so the window is genuinely empty rather than centred
    /// on something.
    @Test("an Intro Gap answers an empty window, having no Active Line to centre on")
    func beforeFirstLine() {
        let entries = LyricsWindow.resolve(at: 3, in: lyrics, lineCount: 3)

        #expect(entries.isEmpty)
    }

    @Test("empty lyrics answers an empty window")
    func emptyLyrics() {
        #expect(LyricsWindow.resolve(at: 10, in: [], lineCount: 3).isEmpty)
    }

    @Test("a line count of zero, or negative, answers an empty window")
    func nonPositiveLineCount() {
        #expect(LyricsWindow.resolve(at: 30, in: lyrics, lineCount: 0).isEmpty)
        #expect(LyricsWindow.resolve(at: 30, in: lyrics, lineCount: -1).isEmpty)
    }
}
