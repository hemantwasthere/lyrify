import AppKit
import LyrifyCore

/// Shows the Overlay pill for the current Track's Synced Lyrics, driven by
/// the same Anchor stream the menu bar uses. The clock (via
/// `PlaybackAnchorSource`) supplies the Playback Position, the lyrics
/// provider's found outcome supplies the Synced Lyrics, and `LineSelection`
/// — the one tested seam — decides what to show and when that changes. This
/// controller only renders that answer and arms one timer for its
/// `nextChange`, so lines change on time without polling.
///
/// For now the Overlay is simply hidden unless Synced Lyrics were found for
/// the current Track; the Idle State that names a Track without lyrics is a
/// separate ticket.
///
/// Deliberately untested — thin app-layer wiring verified by hand; every
/// decision it acts on comes from tested core types.
@MainActor
final class OverlayController {
    private let anchorSource: PlaybackAnchorSource
    private let lyricsProvider: LyricsProvider
    private let window: OverlayWindow
    private let view: OverlayView

    /// The Track URI the current lookup — pending, found, or missed —
    /// belongs to. Mirrors `MenuBarController`'s rule: a slow answer for an
    /// abandoned Track must never overwrite what's on screen for the current
    /// one.
    private var lookupURI: String?

    /// The current Track's Synced Lyrics once found; nil while looking up, on
    /// a confirmed miss, or when unavailable — every one of those hides the
    /// Overlay.
    private var currentLyrics: [LyricLine]?

    /// Armed for the next Lyric Line's start; re-armed on every Anchor and on
    /// firing, cancelled whenever there is nothing to show so paused lines
    /// really stay frozen.
    private var changeTimer: Timer?

    init(anchorSource: PlaybackAnchorSource, lyricsProvider: LyricsProvider) {
        self.anchorSource = anchorSource
        self.lyricsProvider = lyricsProvider

        let view = OverlayView()
        self.view = view
        self.window = OverlayWindow(contentView: view)

        anchorSource.onAnchor { [weak self] state in
            self?.reconcileLookup(with: state)
            self?.render(state)
        }
    }

    /// One lookup per Track, exactly like the menu bar's — including the
    /// same trackless/URI-change rule, so the two controllers agree on
    /// exactly when a Track counts as "new." The provider's memoized
    /// outcomes make sharing it with the menu bar free: whichever of the two
    /// asks first triggers the network call, and the other rides the same
    /// answer.
    private func reconcileLookup(with state: PlaybackState) {
        guard let track = state.track else {
            lookupURI = nil
            currentLyrics = nil
            return
        }
        guard track.uri != lookupURI else { return }
        lookupURI = track.uri
        currentLyrics = nil

        guard track.isLyrical else { return }

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.lyricsProvider.lookup(for: track)

            guard self.lookupURI == track.uri else { return }
            guard case .found(let lines) = outcome else { return }
            self.currentLyrics = lines
            self.render(self.anchorSource.currentEstimate())
        }
    }

    private func render(_ state: PlaybackState) {
        changeTimer?.invalidate()
        changeTimer = nil

        guard let lyrics = currentLyrics, let position = state.position else {
            window.orderOut(nil)
            return
        }

        let answer = LineSelection.at(position, in: lyrics)
        view.update(with: answer.content)

        if let screen = NSScreen.main {
            window.reposition(on: screen)
        }
        window.orderFrontRegardless()

        guard state.isPlaying, let nextChange = answer.nextChange else { return }

        // `.common` mode, not the default: see `PlaybackAnchorSource.start()`
        // — a line change must still land while the status item's menu is
        // open, not just once it closes.
        let delay = max(0, nextChange - position)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render(self.anchorSource.currentEstimate())
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        changeTimer = timer
    }
}
