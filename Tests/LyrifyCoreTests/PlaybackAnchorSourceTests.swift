import Foundation
import Testing

@testable import LyrifyCore

/// The Anchor stream is tested at the `PlaybackSource` port: a scripted fake
/// plays the Player's part, and the tests observe what subscribers are handed.
/// No test scripts Spotify, and none needs it running.
@Suite("Playback anchor source")
@MainActor
struct PlaybackAnchorSourceTests {
    /// Answers a scripted observation per poll, and remembers how often it was
    /// asked. Runs dry by repeating its last answer, so a stream that polls
    /// more than a test scripted for does not fail on the count alone.
    final class ScriptedSource: PlaybackSource {
        private(set) var polls = 0
        private var scripted: [PlaybackState]

        init(_ scripted: [PlaybackState]) {
            self.scripted = scripted
        }

        func currentState() throws -> PlaybackState {
            polls += 1
            guard scripted.count > 1 else { return scripted.first ?? .notRunning }
            return scripted.removeFirst()
        }
    }

    /// Collects what one subscriber was handed.
    final class Subscriber {
        private(set) var received: [PlaybackState] = []
        func record(_ state: PlaybackState) { received.append(state) }
    }

    private static func track(duration: TimeInterval = 200) -> Track {
        Track(
            uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed",
            name: "Let It Happen",
            artist: "Tame Impala",
            album: "Currents",
            duration: duration
        )
    }

    /// The stream is documented as seeding itself so playback already underway
    /// appears without waiting for a state change. A subscriber registered
    /// before `start()` must therefore hear that seed.
    @Test("the seed observation reaches subscribers registered before the stream starts")
    func seedReachesSubscribersRegisteredBeforeStart() {
        let track = Self.track()
        let source = ScriptedSource([.playing(track, position: 12)])
        let stream = PlaybackAnchorSource(source: source, observations: { _ in nil })

        let subscriber = Subscriber()
        stream.onAnchor { subscriber.record($0) }
        stream.start()

        #expect(source.polls == 1)
        #expect(subscriber.received.count == 1)
        #expect(subscriber.received.first?.track == track)
        #expect(subscriber.received.first?.isPlaying == true)
    }

    /// The reason this type exists at all: the menu bar title and the Overlay
    /// must agree, which they can only do by being handed the same estimate
    /// from the same Anchor rather than each observing the Player themselves.
    @Test("every subscriber is handed the same estimate from one Anchor")
    func everySubscriberSharesOneAnchor() {
        let track = Self.track()
        let source = ScriptedSource([.playing(track, position: 30)])
        let stream = PlaybackAnchorSource(source: source, observations: { _ in nil })

        let menuBarTitle = Subscriber()
        let overlay = Subscriber()
        stream.onAnchor { menuBarTitle.record($0) }
        stream.onAnchor { overlay.record($0) }
        stream.start()

        // One reading of the Player, not one per subscriber.
        #expect(source.polls == 1)
        #expect(menuBarTitle.received.count == 1)
        #expect(menuBarTitle.received == overlay.received)
    }

    /// A closed Player is entirely normal, not an error. Subscribers are told
    /// so plainly, and are handed no Track to draw.
    @Test("a Player that is not running leaves subscribers with nothing to show")
    func aPlayerThatIsNotRunningStaysQuiet() {
        let source = ScriptedSource([.notRunning])
        let stream = PlaybackAnchorSource(source: source, observations: { _ in nil })

        let subscriber = Subscriber()
        stream.onAnchor { subscriber.record($0) }
        stream.start()

        #expect(subscriber.received == [.notRunning])
        #expect(subscriber.received.first?.track == nil)
    }

    /// Answers nothing and fails instead — a refused Automation permission.
    final class FailingSource: PlaybackSource {
        struct Refused: Error {}
        func currentState() throws -> PlaybackState { throw Refused() }
    }

    /// A source that fails must not surface as a broken title. Until a later
    /// ticket turns a refused permission into an explanatory state, the stream
    /// stays quiet rather than propagating.
    @Test("a source that fails leaves subscribers quiet rather than showing a broken title")
    func aFailingSourceStaysQuiet() {
        let stream = PlaybackAnchorSource(source: FailingSource(), observations: { _ in nil })

        let subscriber = Subscriber()
        stream.onAnchor { subscriber.record($0) }
        stream.start()

        #expect(subscriber.received == [.notRunning])
    }

    /// The notification is the other source of Anchors, and an observation
    /// arriving through it reaches subscribers exactly as a polled one does.
    @Test("an observation arriving by notification anchors like a polled one")
    func anObservationFromTheNotificationAnchors() {
        let track = Self.track()
        let source = ScriptedSource([.notRunning])

        // Stands in for the platform notification: hands back a box the stream
        // retains, through which the test can broadcast at will.
        final class Broadcaster {
            var send: (@MainActor (PlaybackState) -> Void)?
        }
        let broadcaster = Broadcaster()

        let stream = PlaybackAnchorSource(source: source) { handler in
            broadcaster.send = handler
            return broadcaster
        }

        let subscriber = Subscriber()
        stream.onAnchor { subscriber.record($0) }
        stream.start()

        broadcaster.send?(.playing(track, position: 5))

        #expect(subscriber.received.count == 2)
        #expect(subscriber.received.first == .notRunning)
        #expect(subscriber.received.last?.track == track)
    }
}
