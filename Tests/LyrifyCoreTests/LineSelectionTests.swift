import Foundation
import Testing

@testable import LyrifyCore

/// The Overlay's one decision, made pure: given Synced Lyrics and a Playback
/// Position, what shows — Active Line, Next Line, or an Instrumental Gap —
/// and the Playback Position at which that answer next changes.
@Suite("Line selection")
struct LineSelectionTests {
    private let lyrics = [
        LyricLine(text: "first", start: 10),
        LyricLine(text: "second", start: 20),
        LyricLine(text: "third", start: 30),
    ]

    @Test("between two starts, the earlier is Active and the later is Next")
    func betweenLines() {
        let answer = LineSelection.at(15, in: lyrics)

        #expect(answer == LineSelection.Answer(
            content: .lines(
                active: LyricLine(text: "first", start: 10),
                next: LyricLine(text: "second", start: 20)
            ),
            nextChange: 20
        ))
    }

    /// The first words appear when they are sung, not when the Track starts.
    @Test("before the first line is an Instrumental Gap leading into it")
    func introGap() {
        let answer = LineSelection.at(3, in: lyrics)

        #expect(answer == LineSelection.Answer(
            content: .instrumentalGap,
            nextChange: 10
        ))
    }

    /// The empty-text marker the parser preserves is how a mid-song gap is
    /// declared; showing it as words would pin nothing on screen.
    @Test("an empty-text Active Line is an Instrumental Gap")
    func markedGap() {
        let marked = [
            LyricLine(text: "first", start: 10),
            LyricLine(text: "", start: 20),
            LyricLine(text: "third", start: 30),
        ]

        let answer = LineSelection.at(25, in: marked)

        #expect(answer == LineSelection.Answer(
            content: .instrumentalGap,
            nextChange: 30
        ))
    }

    /// "The latest start time not yet passed": a line's own start counts as
    /// reached.
    @Test("a position exactly on a start selects that line")
    func exactStart() {
        let answer = LineSelection.at(20, in: lyrics)

        #expect(answer == LineSelection.Answer(
            content: .lines(
                active: LyricLine(text: "second", start: 20),
                next: LyricLine(text: "third", start: 30)
            ),
            nextChange: 30
        ))
    }

    /// A Lyric Line has no recorded end, so the last one remains current
    /// through the outro with no further transition to report.
    @Test("the last line persists past its start with no further change")
    func lastLinePersists() {
        let answer = LineSelection.at(300, in: lyrics)

        #expect(answer == LineSelection.Answer(
            content: .lines(active: LyricLine(text: "third", start: 30), next: nil),
            nextChange: nil
        ))
    }

    @Test("single-line lyrics have one transition and then nothing")
    func singleLine() {
        let only = [LyricLine(text: "all there is", start: 5)]

        #expect(LineSelection.at(2, in: only) == LineSelection.Answer(
            content: .instrumentalGap,
            nextChange: 5
        ))
        #expect(LineSelection.at(9, in: only) == LineSelection.Answer(
            content: .lines(active: LyricLine(text: "all there is", start: 5), next: nil),
            nextChange: nil
        ))
    }

    /// The provider never answers found with zero lines, but the selection
    /// must still be total.
    @Test("empty lyrics are a Gap leading nowhere")
    func emptyLyrics() {
        #expect(LineSelection.at(10, in: []) == LineSelection.Answer(
            content: .instrumentalGap,
            nextChange: nil
        ))
    }
}
