import AppKit
import LyrifyCore

/// Lyrify's only visible surface for now: a status item naming the current
/// Track and indicating whether Synced Lyrics were found for it.
///
/// Spotify's playback notification and the poll each feed the `PlaybackClock`
/// as Anchor sources, and the title renders from the clock's answer. The
/// notification carries the events; the poll is the slow re-anchor that
/// bounds Drift and catches what notifications cannot report. A Track change
/// triggers one lyrics lookup, whose outcome fills the icon and names itself
/// in the menu.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let bridge: SpotifyBridge
    private let lyricsProvider: LyricsProvider
    private var timer: Timer?
    private var notificationObserver: SpotifyNotificationObserver?
    private var clock = PlaybackClock()
    private var lastTitle = ""
    private var outcomeItem: NSMenuItem?

    /// The Track URI the lookup outcome on display belongs to. A completed
    /// lookup is applied only if this still matches — a slow answer for an
    /// abandoned Track must never overwrite the current one.
    private var lookupURI: String?

    /// What the indicator can say about the current Track's lyrics. A miss
    /// and unavailability read differently on purpose: one is a database gap,
    /// the other a network hiccup that will retry.
    private enum LookupOutcome {
        case nothingPlaying
        case nonLyrical
        case looking
        case found(lineCount: Int)
        case missed
        case unavailable

        var menuTitle: String {
            switch self {
            case .nothingPlaying: "Nothing playing"
            case .nonLyrical: "Nothing to look up"
            case .looking: "Looking up synced lyrics…"
            case .found(let lineCount): "Synced lyrics found (\(lineCount) lines)"
            case .missed: "No synced lyrics found"
            case .unavailable: "Lyrics lookup unavailable"
            }
        }

        var symbolName: String {
            if case .found = self { "quote.bubble.fill" } else { "quote.bubble" }
        }
    }

    /// The re-anchor cadence. This knob bounds two worst cases at once: how
    /// far Drift can accumulate between Anchors, and how long a seek — which
    /// produces no notification — can leave the Playback Position wrong. Ten
    /// seconds keeps both unnoticeable for a menu bar title; revisit downward
    /// if lyric-line accuracy ever demands a tighter Drift bound.
    private static let reAnchorInterval: TimeInterval = 10.0

    init(bridge: SpotifyBridge, lyricsProvider: LyricsProvider) {
        self.bridge = bridge
        self.lyricsProvider = lyricsProvider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        buildMenu()
        // The seed poll: playback already underway when Lyrify launches
        // appears without waiting for a state change.
        poll()
        startTimer()
        notificationObserver = SpotifyNotificationObserver { [weak self] observed in
            self?.anchor(observed)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "quote.bubble",
            accessibilityDescription: "Lyrify"
        )
        button.imagePosition = .imageLeading
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let outcome = NSMenuItem(title: "Nothing playing", action: nil, keyEquivalent: "")
        outcome.isEnabled = false
        menu.addItem(outcome)
        outcomeItem = outcome

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Lyrify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.reAnchorInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let observed: PlaybackState
        do {
            observed = try bridge.currentState()
        } catch {
            // A later ticket turns a refused permission into an explanatory
            // state. Until then, stay quiet rather than showing a broken title.
            observed = .notRunning
        }

        anchor(observed)
    }

    private func anchor(_ observed: PlaybackState) {
        let now = ContinuousClock.Instant.now
        clock.anchor(observed, at: now)

        let state = clock.estimatedState(at: now)
        render(state)
        reconcileLookup(with: state)
    }

    /// Estimated position changes on every query, so deduplicate on the title
    /// — the part of the state this surface actually shows.
    private func render(_ state: PlaybackState) {
        let title = MenuBarTitle.text(for: state).map { " " + $0 } ?? ""

        guard title != lastTitle else { return }
        lastTitle = title
        statusItem.button?.title = title
    }

    /// One lookup per Track: triggered when the clock's Track changes by URI,
    /// never re-triggered by position updates. A transient trackless blip
    /// (stopped, or one failed poll) forgets the URI and so re-triggers when
    /// the same Track reappears; the miss-inclusive cache (ticket #9) makes
    /// that repeat free.
    private func reconcileLookup(with state: PlaybackState) {
        guard let track = state.track else {
            if lookupURI != nil {
                lookupURI = nil
                show(.nothingPlaying)
            }
            return
        }
        guard track.uri != lookupURI else { return }
        lookupURI = track.uri

        guard track.isLyrical else {
            show(.nonLyrical)
            return
        }

        show(.looking)
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.lyricsProvider.lookup(for: track)

            guard self.lookupURI == track.uri else { return }
            switch outcome {
            case .found(let lines): self.show(.found(lineCount: lines.count))
            case .noSyncedLyrics: self.show(.missed)
            case .unavailable: self.show(.unavailable)
            }
        }
    }

    private func show(_ outcome: LookupOutcome) {
        outcomeItem?.title = outcome.menuTitle
        statusItem.button?.image = NSImage(
            systemSymbolName: outcome.symbolName,
            accessibilityDescription: "Lyrify"
        )
    }
}
