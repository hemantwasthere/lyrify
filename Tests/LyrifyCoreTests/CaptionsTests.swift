import Foundation
import Testing

@testable import LyrifyCore

/// What the transcriber says, turned into something a window can draw. Shapes
/// below follow what `SpeechTranscriber` actually emitted during the spike —
/// see `docs/findings/2026-08-03-system-audio-captions.md`.
@Suite("Captions")
struct CaptionsTests {
    @Test("nothing has been said yet")
    func empty() {
        let captions = Captions()
        #expect(captions.lines.isEmpty)
        #expect(captions.current == nil)
    }

    /// The transcriber revises a line word by word while it is being spoken.
    /// Each revision replaces the last, or the window fills with fragments of
    /// one sentence.
    @Test("a line being spoken is revised in place, not repeated")
    func revisionsReplace() {
        var captions = Captions()
        captions.receive("Live", isFinal: false)
        captions.receive("Live captions", isFinal: false)
        captions.receive("Live captions should", isFinal: false)

        #expect(captions.lines.count == 1)
        #expect(captions.current?.text == "Live captions should")
        #expect(captions.current?.isSettled == false)
    }

    @Test("a settled line stays, and the next one starts fresh")
    func settlingStartsANewLine() {
        var captions = Captions()
        captions.receive("Live captions should appear.", isFinal: true)
        captions.receive("Here", isFinal: false)

        #expect(captions.lines.count == 2)
        #expect(captions.lines.first?.text == "Live captions should appear.")
        #expect(captions.lines.first?.isSettled == true)
        #expect(captions.current?.text == "Here")
        #expect(captions.current?.isSettled == false)
    }

    /// The settled text usually differs from the last partial — the model
    /// changes its mind as it commits. The settled version wins.
    @Test("settling replaces the partial it settles rather than adding to it")
    func settlingReplacesThePartial() {
        var captions = Captions()
        captions.receive("I'm not speaking Um So today", isFinal: false)
        captions.receive("I'm not... So today.", isFinal: true)

        #expect(captions.lines.count == 1)
        #expect(captions.lines.first?.text == "I'm not... So today.")
        #expect(captions.lines.first?.isSettled == true)
    }

    /// Whitespace-only revisions are what a pause produces; they are not a line.
    @Test("blank text is not a line")
    func blankIsNotALine() {
        var captions = Captions()
        captions.receive("   ", isFinal: false)
        captions.receive("", isFinal: true)

        #expect(captions.lines.isEmpty)
        #expect(captions.current == nil)
    }

    /// Leading space is normal — the transcriber emits " Live captions…" — and
    /// would otherwise indent every line but the first.
    @Test("surrounding whitespace is trimmed")
    func whitespaceTrimmed() {
        var captions = Captions()
        captions.receive("  Live captions  ", isFinal: true)
        #expect(captions.lines.first?.text == "Live captions")
    }

    /// A machine left playing all day must not grow this without limit.
    @Test("history is bounded, keeping the most recent")
    func bounded() {
        var captions = Captions()
        for index in 0..<(Captions.limit + 30) {
            captions.receive("line \(index)", isFinal: true)
        }

        #expect(captions.lines.count == Captions.limit)
        #expect(captions.lines.last?.text == "line \(Captions.limit + 29)")
        #expect(captions.lines.first?.text == "line 30")
    }

    @Test("clearing forgets everything")
    func clearing() {
        var captions = Captions()
        captions.receive("something", isFinal: true)
        captions.clear()

        #expect(captions.lines.isEmpty)
        #expect(captions.current == nil)
    }

    /// Lines carry stable identity so a view can tell an existing line being
    /// revised from a new one arriving.
    @Test("a line keeps its identity while it is being revised")
    func identityIsStableAcrossRevisions() {
        var captions = Captions()
        captions.receive("Live", isFinal: false)
        let first = captions.current?.id
        captions.receive("Live captions", isFinal: false)
        #expect(captions.current?.id == first)

        captions.receive("Live captions.", isFinal: true)
        captions.receive("Next", isFinal: false)
        #expect(captions.current?.id != first)
    }
}
