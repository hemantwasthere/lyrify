import Foundation
import Testing

@testable import LyrifyCore

/// What Full Layout's always-visible seek bar shows for elapsed and
/// remaining time — pure formatting, so the m:ss/h:mm:ss rules and
/// truncation direction are testable without a live seek bar.
@Suite("Playback time format")
struct PlaybackTimeFormatTests {
    @Test("zero seconds reads as 0:00")
    func zero() {
        #expect(PlaybackTimeFormat.string(forSeconds: 0) == "0:00")
    }

    @Test("under a minute pads seconds to two digits")
    func underAMinute() {
        #expect(PlaybackTimeFormat.string(forSeconds: 5) == "0:05")
    }

    @Test("exactly one minute reads as 1:00")
    func exactlyOneMinute() {
        #expect(PlaybackTimeFormat.string(forSeconds: 60) == "1:00")
    }

    @Test("minutes and seconds both show, seconds zero-padded")
    func minutesAndSeconds() {
        #expect(PlaybackTimeFormat.string(forSeconds: 125) == "2:05")
    }

    @Test("an hour or more gains an hours component")
    func anHourOrMore() {
        #expect(PlaybackTimeFormat.string(forSeconds: 3661) == "1:01:01")
    }

    /// A Playback Position can't be negative, but floating-point drift right
    /// at a Track's boundary could otherwise produce one — must never show
    /// a negative time.
    @Test("negative seconds clamps to 0:00")
    func negativeClampsToZero() {
        #expect(PlaybackTimeFormat.string(forSeconds: -5) == "0:00")
    }

    /// Truncates towards zero rather than rounding, so the displayed second
    /// never ticks over before it has actually elapsed.
    @Test("fractional seconds truncate down, not round")
    func fractionalSecondsTruncateDown() {
        #expect(PlaybackTimeFormat.string(forSeconds: 65.9) == "1:05")
    }
}
