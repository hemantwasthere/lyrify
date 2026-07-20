import AppKit
import LyrifyCore

/// The status item: names the current Track and indicates whether Synced
/// Lyrics were found for it, alongside whatever the Overlay is showing.
///
/// Subscribes to the shared `PlaybackAnchorSource` and renders on every
/// Anchor. A Track change triggers one lyrics lookup, whose outcome fills the
/// icon and names itself in the menu.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let lyricsProvider: LyricsProvider
    private var lastTitle = ""
    private var outcomeItem: NSMenuItem?

    /// Owns the "Show Overlay" toggle. Held here because the menu item's
    /// `target` doesn't retain it.
    private var overlayVisibilityMenuController: OverlayVisibilityMenuController?

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

    init(
        anchorSource: PlaybackAnchorSource,
        lyricsProvider: LyricsProvider,
        overlayVisibility: OverlayVisibilityPreference,
        onVisibilityChange: @escaping () -> Void
    ) {
        self.lyricsProvider = lyricsProvider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        buildMenu(overlayVisibility: overlayVisibility, onVisibilityChange: onVisibilityChange)
        anchorSource.onAnchor { [weak self] state in
            self?.render(state)
            self?.reconcileLookup(with: state)
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

    private func buildMenu(overlayVisibility: OverlayVisibilityPreference, onVisibilityChange: @escaping () -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let outcome = NSMenuItem(title: "Nothing playing", action: nil, keyEquivalent: "")
        outcome.isEnabled = false
        menu.addItem(outcome)
        outcomeItem = outcome

        menu.addItem(.separator())

        let overlayVisibilityMenuController = OverlayVisibilityMenuController(
            preference: overlayVisibility,
            onChange: onVisibilityChange
        )
        self.overlayVisibilityMenuController = overlayVisibilityMenuController
        menu.addItem(overlayVisibilityMenuController.menuItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Lyrify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
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
    /// the same Track reappears; the provider's miss-inclusive memory makes
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
