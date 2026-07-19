import Foundation
import Testing

@testable import LyrifyCore

/// The clock is fed Anchors and answers the estimated `PlaybackState` at any
/// later instant. Time only enters as arguments, so every scenario here runs
/// instantly — no timers, no sleeping, no Spotify.
@Suite("Playback clock")
struct PlaybackClockTests {
    private let t0 = ContinuousClock().now

    private func track(duration: TimeInterval = 467.586) -> Track {
        Track(
            uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed",
            name: "Let It Happen",
            artist: "Tame Impala",
            album: "Currents",
            duration: duration
        )
    }

    @Test("before any Anchor, the clock answers not running")
    func noAnchors() {
        let clock = PlaybackClock()

        #expect(clock.estimatedState(at: t0) == .notRunning)
    }

    @Test("while playing, the Playback Position advances with elapsed time")
    func playingAdvances() {
        var clock = PlaybackClock()
        clock.anchor(.playing(track(), position: 10), at: t0)

        let estimated = clock.estimatedState(at: t0 + .milliseconds(2500))

        #expect(estimated == .playing(track(), position: 12.5))
    }

    /// The clock never claims a Playback Position the recording does not have.
    @Test("the estimate never runs past the end of the Track")
    func clampedAtTrackEnd() {
        var clock = PlaybackClock()
        clock.anchor(.playing(track(duration: 20), position: 18), at: t0)

        let estimated = clock.estimatedState(at: t0 + .seconds(60))

        #expect(estimated == .playing(track(duration: 20), position: 20))
    }

    @Test("while paused, the Playback Position stays frozen at the Anchor")
    func pausedFreezes() {
        var clock = PlaybackClock()
        clock.anchor(.paused(track(), position: 10), at: t0)

        let estimated = clock.estimatedState(at: t0 + .seconds(300))

        #expect(estimated == .paused(track(), position: 10))
    }

    /// A seek produces no notification, so it arrives as a later Anchor whose
    /// position disagrees with the estimate. No tolerance, no smoothing: the
    /// newest Anchor is simply the truth.
    @Test("a newer Anchor unconditionally replaces the estimate")
    func latestAnchorWins() {
        var clock = PlaybackClock()
        clock.anchor(.playing(track(), position: 100), at: t0)
        clock.anchor(.playing(track(), position: 30), at: t0 + .seconds(10))

        let estimated = clock.estimatedState(at: t0 + .seconds(12))

        #expect(estimated == .playing(track(), position: 32))
    }

    @Test("pausing then resuming picks up from the resume Anchor")
    func pauseThenResume() {
        var clock = PlaybackClock()
        clock.anchor(.playing(track(), position: 10), at: t0)
        clock.anchor(.paused(track(), position: 15), at: t0 + .seconds(5))
        clock.anchor(.playing(track(), position: 15), at: t0 + .seconds(65))

        let estimated = clock.estimatedState(at: t0 + .seconds(67))

        #expect(estimated == .playing(track(), position: 17))
    }

    /// Delivery order isn't guaranteed once Anchors come from more than one
    /// source; a query instant behind the Anchor must not rewind the position.
    @Test("a query earlier than the Anchor answers the Anchor's position")
    func queryBeforeAnchor() {
        var clock = PlaybackClock()
        clock.anchor(.playing(track(), position: 10), at: t0 + .seconds(5))

        let estimated = clock.estimatedState(at: t0)

        #expect(estimated == .playing(track(), position: 10))
    }

    @Test("stopped and not-running Anchors answer no position, however late the query")
    func quietStates() {
        var clock = PlaybackClock()

        clock.anchor(.stopped, at: t0)
        #expect(clock.estimatedState(at: t0 + .seconds(90)) == .stopped)

        clock.anchor(.notRunning, at: t0 + .seconds(100))
        #expect(clock.estimatedState(at: t0 + .seconds(190)) == .notRunning)
    }
}
