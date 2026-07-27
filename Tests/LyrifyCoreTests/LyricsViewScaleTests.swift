import Foundation
import Testing

@testable import LyrifyCore

/// Maps the Lyrics view's available height to a line count and font size —
/// the Spotify-style "grow the card, see more lines at a bigger font"
/// behavior, independent of `LyricsWindow`'s own windowing logic.
@Suite("Lyrics view scale")
struct LyricsViewScaleTests {
    @Test("the minimum height answers the base scale: two lines at the base font size")
    func minimumHeight() {
        let scale = LyricsViewScale.resolve(forHeight: LyricsViewScale.minimumHeight)

        #expect(scale.lineCount == LyricsViewScale.minimumLineCount)
        #expect(scale.fontSize == LyricsViewScale.minimumFontSize)
    }

    @Test("a height below the minimum still answers the base scale, never fewer lines")
    func belowMinimumHeight() {
        let scale = LyricsViewScale.resolve(forHeight: 0)

        #expect(scale.lineCount == LyricsViewScale.minimumLineCount)
        #expect(scale.fontSize == LyricsViewScale.minimumFontSize)
    }

    @Test("a taller height answers more lines at a larger font")
    func tallerHeight() {
        let base = LyricsViewScale.resolve(forHeight: LyricsViewScale.minimumHeight)
        let taller = LyricsViewScale.resolve(forHeight: LyricsViewScale.minimumHeight + 200)

        #expect(taller.lineCount > base.lineCount)
        #expect(taller.fontSize > base.fontSize)
    }

    @Test("line count and font size are both clamped at a maximum, however tall the card grows")
    func clampedAtMaximum() {
        let scale = LyricsViewScale.resolve(forHeight: 100_000)

        #expect(scale.lineCount == LyricsViewScale.maximumLineCount)
        #expect(scale.fontSize == LyricsViewScale.maximumFontSize)
    }

    @Test("scale grows monotonically with height, never shrinking for a taller card")
    func monotonic() {
        var previous = LyricsViewScale.resolve(forHeight: LyricsViewScale.minimumHeight)

        for height in stride(
            from: LyricsViewScale.minimumHeight,
            through: LyricsViewScale.minimumHeight + 400,
            by: 20
        ) {
            let scale = LyricsViewScale.resolve(forHeight: height)
            #expect(scale.lineCount >= previous.lineCount)
            #expect(scale.fontSize >= previous.fontSize)
            previous = scale
        }
    }
}
