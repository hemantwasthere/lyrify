import Foundation
import Testing

@testable import LyrifyCore

/// The Floor is tested as a pure translation: events in, `PlaybackState` out.
/// No subprocess, no adapter, no browser. Every payload below is shaped after
/// one actually observed on 2026-08-02 — see
/// `docs/findings/2026-08-02-now-playing-floor.md`.
@Suite("Now Playing Floor")
struct NowPlayingFloorTests {
    private func event(_ json: String) -> Data { Data(json.utf8) }

    /// A whole reading, as the adapter's `get` produces it.
    private static let chromeVideo = """
        {"playbackRate": 1, "album": "", "elapsedTime": 0.002122,
         "timestamp": "2026-08-02T07:18:58Z", "bundleIdentifier": "com.google.Chrome",
         "title": "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)",
         "artist": "Rick Astley", "duration": 213.061, "playing": true}
        """

    @Test("a whole reading becomes a playing Track named by title and channel")
    func wholeReading() throws {
        var floor = NowPlayingFloor()
        try floor.merge(event(Self.chromeVideo))

        #expect(floor.holder == "com.google.Chrome")
        guard case .playing(let track, let position) = floor.state else {
            Issue.record("expected playing, got \(floor.state)")
            return
        }
        #expect(track.name == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
        #expect(track.artist == "Rick Astley")
        #expect(track.album.isEmpty)
        #expect(track.duration == 213.061)
        #expect(track.isLyrical)
        #expect(position == 0.002122)
    }

    /// The stream emits diffs carrying only what changed. Treating one as a
    /// whole reading would answer a Track with no title and no owner — which is
    /// exactly what a naive implementation does, so this is the test that
    /// matters most here.
    @Test("a diff event carrying one field is merged, not mistaken for a whole reading")
    func diffEventMerges() throws {
        var floor = NowPlayingFloor()
        try floor.merge(event(Self.chromeVideo))
        try floor.merge(event(#"{"elapsedTime": 91.511747}"#))

        #expect(floor.holder == "com.google.Chrome")
        guard case .playing(let track, let position) = floor.state else {
            Issue.record("expected playing, got \(floor.state)")
            return
        }
        #expect(track.artist == "Rick Astley")
        #expect(position == 91.511747)
    }

    @Test("a diff flipping playing pauses without losing the Track")
    func diffCanPause() throws {
        var floor = NowPlayingFloor()
        try floor.merge(event(Self.chromeVideo))
        try floor.merge(event(#"{"playing": false}"#))

        guard case .paused(let track, _) = floor.state else {
            Issue.record("expected paused, got \(floor.state)")
            return
        }
        #expect(track.artist == "Rick Astley")
    }

    /// The adapter prints `null` when nothing is playing anywhere. The Floor
    /// must forget what it held, or the Overlay keeps showing a stale Track.
    @Test("null empties the Floor rather than leaving a stale Track")
    func nullEmpties() throws {
        var floor = NowPlayingFloor()
        try floor.merge(event(Self.chromeVideo))
        try floor.merge(event("null"))

        #expect(floor.holder == nil)
        #expect(floor.state == .notRunning)
    }

    /// Live content — a Premiere or a stream — reports an infinite duration the
    /// adapter cannot encode, so the key is simply absent. Such a Track can
    /// never be Matched.
    @Test("a reading with no duration is a Track that could never be Matched")
    func liveContentIsNotLyrical() throws {
        var floor = NowPlayingFloor()
        try floor.merge(
            event(
                #"""
                {"elapsedTime": 0, "bundleIdentifier": "company.thebrowser.Browser",
                 "title": "INDIA'S GOT LATENT S2 EP4", "artist": "Samay Raina", "playing": true}
                """#))

        guard case .playing(let track, _) = floor.state else {
            Issue.record("expected playing, got \(floor.state)")
            return
        }
        #expect(track.artist == "Samay Raina")
        #expect(track.isLyrical == false)
        #expect(track.duration == 0)
    }

    /// Title and owner are the two fields nothing can be built without. The
    /// adapter documents media without a title as invalid, and an owner is
    /// mandatory in its output.
    @Test("a reading missing its title or its owner shows nothing")
    func mandatoryFieldsMissing() throws {
        var withoutTitle = NowPlayingFloor()
        try withoutTitle.merge(event(#"{"bundleIdentifier": "com.google.Chrome", "playing": true}"#))
        #expect(withoutTitle.state == .notRunning)

        var withoutOwner = NowPlayingFloor()
        try withoutOwner.merge(event(#"{"title": "Something", "playing": true}"#))
        #expect(withoutOwner.state == .notRunning)
    }

    @Test("a malformed number is a specific error, not a guess")
    func malformedNumber() {
        var floor = NowPlayingFloor()
        #expect(throws: NowPlayingFloor.ParseError.invalidNumber(field: "elapsedTime")) {
            try floor.merge(event(#"{"title": "t", "elapsedTime": "soon"}"#))
        }
        #expect(throws: NowPlayingFloor.ParseError.invalidNumber(field: "duration")) {
            try floor.merge(event(#"{"title": "t", "duration": "long"}"#))
        }
    }

    @Test("a line that is not an object at all is a specific error")
    func notAnObject() {
        var floor = NowPlayingFloor()
        #expect(throws: NowPlayingFloor.ParseError.notAReading) {
            try floor.merge(event("Invalid JSON value type in dictionary for key 'duration'"))
        }
    }

    /// A reading with no position yet is still a reading; it simply starts at
    /// the beginning rather than refusing to exist.
    @Test("a reading with no elapsed time starts at the beginning")
    func missingElapsedTime() throws {
        var floor = NowPlayingFloor()
        try floor.merge(
            event(
                #"{"bundleIdentifier": "com.google.Chrome", "title": "t", "artist": "c", "duration": 10, "playing": true}"#
            ))

        guard case .playing(_, let position) = floor.state else {
            Issue.record("expected playing, got \(floor.state)")
            return
        }
        #expect(position == 0)
    }
}
