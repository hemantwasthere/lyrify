import Foundation
import Testing

@testable import LyrifyCore

/// The Disc's rotation angle, decided the same way `PlaybackClock` decides
/// Playback Position: an Anchor plus elapsed time estimates the current
/// value. Unlike Playback Position, the angle is never externally observed
/// — it's entirely self-computed — so pausing must freeze at whatever angle
/// was *estimated* at that instant, not some other stored value, and resume
/// must continue smoothly from there. Time only enters as instants passed
/// in, so every scenario here runs instantly — no timers, no live spinning.
@Suite("Disc rotation")
struct DiscRotationTests {
    private let t0 = ContinuousClock().now

    @Test("before any Anchor, the angle is zero")
    func noAnchor() {
        let rotation = DiscRotation()

        #expect(rotation.angle(at: t0) == 0)
    }

    @Test("while playing, the angle advances with elapsed time")
    func playingAdvances() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0)

        let estimated = rotation.angle(at: t0 + .seconds(1))

        #expect(estimated == DiscRotation.degreesPerSecond)
    }

    @Test("while paused, the angle stays frozen at the Anchor")
    func pausedFreezes() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0)
        rotation.anchor(isPlaying: false, at: t0 + .seconds(2))

        let frozen = DiscRotation.degreesPerSecond * 2
        #expect(rotation.angle(at: t0 + .seconds(2)) == frozen)
        #expect(rotation.angle(at: t0 + .seconds(300)) == frozen)
    }

    /// The angle is never externally reported the way Playback Position is
    /// — pausing must capture the angle as *estimated at that instant*, not
    /// some stale value, or the Disc would visibly jump the moment it froze.
    @Test("pausing freezes at the currently estimated angle, not a stale one")
    func pauseCapturesEstimatedAngle() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0)

        // Query well after the play Anchor, then pause even later — the
        // frozen angle must reflect elapsed time up to the pause instant.
        _ = rotation.angle(at: t0 + .seconds(1))
        rotation.anchor(isPlaying: false, at: t0 + .seconds(3))

        #expect(rotation.angle(at: t0 + .seconds(10)) == DiscRotation.degreesPerSecond * 3)
    }

    @Test("resuming continues from the frozen angle, not from zero")
    func resumeContinuesFromFrozenAngle() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0)
        rotation.anchor(isPlaying: false, at: t0 + .seconds(2))
        rotation.anchor(isPlaying: true, at: t0 + .seconds(10))

        let frozenAngle = DiscRotation.degreesPerSecond * 2
        let expected = (frozenAngle + DiscRotation.degreesPerSecond * 3).truncatingRemainder(dividingBy: 360)
        #expect(rotation.angle(at: t0 + .seconds(13)) == expected)
    }

    @Test("re-anchoring mid-play never jumps the angle")
    func reAnchorWhilePlayingIsContinuous() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0)
        rotation.anchor(isPlaying: true, at: t0 + .seconds(3))

        #expect(rotation.angle(at: t0 + .seconds(5)) == DiscRotation.degreesPerSecond * 5)
    }

    @Test("the angle wraps at 360 degrees")
    func wrapsAt360() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0)

        let secondsPerTurn = 360 / DiscRotation.degreesPerSecond
        let estimated = rotation.angle(at: t0 + .seconds(Int(secondsPerTurn) + 1))

        #expect(estimated == DiscRotation.degreesPerSecond)
        #expect((0..<360).contains(estimated))
    }

    /// A query behind the last Anchor (out-of-order delivery) must not
    /// rewind, mirroring `PlaybackClock`'s identical rule.
    @Test("a query earlier than the Anchor answers the Anchor's angle")
    func queryBeforeAnchor() {
        var rotation = DiscRotation()
        rotation.anchor(isPlaying: true, at: t0 + .seconds(5))

        #expect(rotation.angle(at: t0) == 0)
    }
}
