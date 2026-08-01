import Foundation
import Testing

@testable import LyrifyCore

/// The Overlay's one decision, made pure: given Synced Lyrics and a Playback
/// Position, whether an Active Line exists yet — and if so which, with its
/// Next Line — plus the Playback Position at which that answer next changes.
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

    /// The first words appear when they are sung, not when the Track starts —
    /// and until they do there is no Active Line to name.
    @Test("before the first line there is no Active Line yet: an Intro Gap")
    func introGap() {
        let answer = LineSelection.at(3, in: lyrics)

        #expect(answer == LineSelection.Answer(
            content: .introGap,
            nextChange: 10
        ))
    }

    /// The empty-text Gap Marker the parser preserves is how an Instrumental
    /// Gap declares itself — but it is a Lyric Line with a start time like any
    /// other, and answering it as the Active Line is what lets callers keep
    /// the lines either side of the gap on screen. Collapsing it into a gap
    /// case threw that context away.
    @Test("a Gap Marker is still the Active Line, not an absence of one")
    func markedGap() {
        let marked = [
            LyricLine(text: "first", start: 10),
            LyricLine(text: "", start: 20),
            LyricLine(text: "third", start: 30),
        ]

        let answer = LineSelection.at(25, in: marked)

        #expect(answer == LineSelection.Answer(
            content: .lines(
                active: LyricLine(text: "", start: 20),
                next: LyricLine(text: "third", start: 30)
            ),
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
            content: .introGap,
            nextChange: 5
        ))
        #expect(LineSelection.at(9, in: only) == LineSelection.Answer(
            content: .lines(active: LyricLine(text: "all there is", start: 5), next: nil),
            nextChange: nil
        ))
    }

    /// The provider never answers found with zero lines, but the selection
    /// must still be total.
    @Test("empty lyrics are an Intro Gap leading nowhere")
    func emptyLyrics() {
        #expect(LineSelection.at(10, in: []) == LineSelection.Answer(
            content: .introGap,
            nextChange: nil
        ))
    }
}
