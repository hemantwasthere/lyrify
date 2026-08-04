import AppKit
import LyrifyCore

/// The status item: the mark, and a menu that says what Lyrify has found for
/// the current Track.
///
/// The item is the icon and nothing else. It carried the Track name before, and
/// a name — artist pair is wide: it pushed every other item along the menu bar,
/// and moved them again on every song. The Overlay is where the Track is named,
/// which is the whole point of it; the status item only has to say that Lyrify
/// is running, and be somewhere to click.
///
/// Subscribes to the shared `PlaybackAnchorSource`. A Track change triggers one
/// lyrics lookup, whose outcome names itself in the menu.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let lyricsProvider: LyricsProvider
    private var outcomeItem: NSMenuItem?

    /// Owns the "Show Overlay" toggle. Held here because the menu item's
    /// `target` doesn't retain it.
    private var overlayVisibilityMenuController: OverlayVisibilityMenuController?

    /// Held for the same reason.
    private var minimizeTarget: MenuActionTarget?
    private var liveCaptionsTarget: MenuActionTarget?
    private var liveCaptionsItem: NSMenuItem?

    /// The Track URI the lookup outcome on display belongs to. A completed
    /// lookup is applied only if this still matches — a slow answer for an
    /// abandoned Track must never overwrite the current one.
    private var lookupURI: String?

    /// What the menu can say about the current Track's lyrics. A miss and
    /// unavailability read differently on purpose: one is a database gap, the
    /// other a network hiccup that will retry.
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
    }

    init(
        anchorSource: PlaybackAnchorSource,
        lyricsProvider: LyricsProvider,
        overlayVisibility: OverlayVisibilityPreference,
        onVisibilityChange: @escaping () -> Void,
        onMinimizeToDisc: @escaping () -> Void,
        liveCaptions: LiveCaptionsController
    ) {
        self.lyricsProvider = lyricsProvider
        // Square rather than variable: the content is one fixed-width icon, and
        // variable length would leave the item padded to whatever the last
        // title measured.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configureButton()
        buildMenu(
            overlayVisibility: overlayVisibility,
            onVisibilityChange: onVisibilityChange,
            onMinimizeToDisc: onMinimizeToDisc,
            liveCaptions: liveCaptions
        )
        anchorSource.onAnchor { [weak self] state in
            self?.reconcileLookup(with: state)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.make()
        button.imagePosition = .imageOnly
    }

    private func buildMenu(
        overlayVisibility: OverlayVisibilityPreference,
        onVisibilityChange: @escaping () -> Void,
        onMinimizeToDisc: @escaping () -> Void,
        liveCaptions: LiveCaptionsController
    ) {
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

        // The way back to the Disc. It used to be the Overlay's red dot, which
        // now quits — and without somewhere else to put it the Disc would only
        // ever be reachable on a first run, taking `DiscView` and its rotation
        // down with it.
        let minimizeTarget = MenuActionTarget(onMinimizeToDisc)
        self.minimizeTarget = minimizeTarget
        let minimize = NSMenuItem(title: "Minimize to Disc", action: #selector(MenuActionTarget.fire), keyEquivalent: "")
        minimize.target = minimizeTarget
        menu.addItem(minimize)

        // Off until asked for, and absent entirely where it cannot work — an
        // option that does nothing is worse than no option.
        let captionsTarget = MenuActionTarget { [weak self] in
            guard let item = self?.liveCaptionsItem else { return }
            let turningOn = item.state != .on
            liveCaptions.setEnabled(turningOn)
            item.state = liveCaptions.isEnabled ? .on : .off
        }
        self.liveCaptionsTarget = captionsTarget

        let captions = NSMenuItem(
            title: "Live Captions", action: #selector(MenuActionTarget.fire), keyEquivalent: "")
        captions.target = captionsTarget
        captions.state = liveCaptions.isEnabled ? .on : .off
        if LiveCaptionsController.isSupported == false {
            captions.isEnabled = false
            captions.toolTip = "Live Captions needs macOS 26 or later."
        }
        menu.addItem(captions)
        liveCaptionsItem = captions

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Lyrify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
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
    }
}

/// Carries a closure to a menu item, which needs an `@objc` target and does not
/// retain the one it is given.
@MainActor
final class MenuActionTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc func fire() { action() }
}
