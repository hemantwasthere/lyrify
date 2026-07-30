import Foundation
import Testing

@testable import LyrifyCore

/// The Overlay's outermost decision: hidden, the Idle State naming the
/// Track, or Synced Lyrics via `LineSelection` — in that priority order.
/// Hidden-by-toggle beats every other state; a Track with no Synced Lyrics
/// yet (looking, a confirmed miss, unavailability, or a Non-Lyrical Item —
/// all just "no lyrics" from here) is the Idle State.
@Suite("Overlay display")
struct OverlayDisplayTests {
    private let track = Track(
        uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed",
        name: "Let It Happen",
        artist: "Tame Impala",
        album: "Currents",
        duration: 467.586
    )

    private let lyrics = [
        LyricLine(text: "first", start: 10),
        LyricLine(text: "second", start: 20),
    ]

    @Test("hidden by toggle, even with a track playing and lyrics found")
    func hiddenByToggle() {
        let answer = OverlayDisplay.resolve(
            isVisible: false,
            state: .playing(track, position: 15),
            lyrics: lyrics
        )

        #expect(answer == OverlayDisplay.Answer(content: .hidden, nextChange: nil))
    }

    @Test("nothing playing hides, even when visible")
    func nothingPlayingHides() {
        #expect(OverlayDisplay.resolve(isVisible: true, state: .notRunning, lyrics: nil)
            == OverlayDisplay.Answer(content: .hidden, nextChange: nil))
        #expect(OverlayDisplay.resolve(isVisible: true, state: .stopped, lyrics: nil)
            == OverlayDisplay.Answer(content: .hidden, nextChange: nil))
    }

    /// Covers a confirmed miss, unavailability, a Non-Lyrical Item, and a
    /// lookup still in flight alike — every one of those is "no Synced
    /// Lyrics yet" from this seam's point of view.
    @Test("a track with no Synced Lyrics shows the Idle State, naming it exactly as the menu bar would")
    func idleNamesTheTrack() {
        let answer = OverlayDisplay.resolve(
            isVisible: true,
            state: .playing(track, position: 5),
            lyrics: nil
        )

        #expect(answer == OverlayDisplay.Answer(
            content: .idle(trackName: TrackLabel.text(for: track), note: nil),
            nextChange: nil
        ))
    }

    @Test("a track with Synced Lyrics delegates to Line Selection, carrying its nextChange")
    func lyricsDelegateToLineSelection() {
        let answer = OverlayDisplay.resolve(
            isVisible: true,
            state: .playing(track, position: 15),
            lyrics: lyrics
        )

        let expected = LineSelection.at(15, in: lyrics)
        #expect(answer == OverlayDisplay.Answer(content: .lines(expected.content), nextChange: expected.nextChange))
    }

    @Test("a paused track with Synced Lyrics still shows lines, frozen at its position")
    func pausedStillShowsLines() {
        let answer = OverlayDisplay.resolve(
            isVisible: true,
            state: .paused(track, position: 15),
            lyrics: lyrics
        )

        let expected = LineSelection.at(15, in: lyrics)
        #expect(answer == OverlayDisplay.Answer(content: .lines(expected.content), nextChange: expected.nextChange))
    }

    /// LRCLIB falls over, and when it does the Idle State used to look exactly
    /// like a song that simply has no lyrics — and exactly like Lyrify being
    /// broken. The note says whose problem it is.
    @Test("an unavailable lyrics service says so under the track name")
    func serviceUnavailableIsExplained() {
        let answer = OverlayDisplay.resolve(
            isVisible: true,
            state: .playing(track, position: 10),
            lyrics: nil,
            availability: .serviceUnavailable
        )

        guard case .idle(_, let note) = answer.content else {
            Issue.record("expected the Idle State, got \(answer.content)")
            return
        }
        #expect(note?.contains("LRCLIB") == true)
    }

    /// A lookup in flight says nothing: most land fast enough that a message
    /// would only flicker on screen and away again.
    @Test("a lookup still in flight adds no note")
    func searchingIsQuiet() {
        let answer = OverlayDisplay.resolve(
            isVisible: true,
            state: .playing(track, position: 10),
            lyrics: nil,
            availability: .searching
        )

        guard case .idle(_, let note) = answer.content else {
            Issue.record("expected the Idle State, got \(answer.content)")
            return
        }
        #expect(note == nil)
    }
}
