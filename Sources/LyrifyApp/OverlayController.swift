import AppKit
import LyrifyCore

/// Owns the Overlay's window and keeps it where the listener left it,
/// spinning the Disc's artwork in time with playback.
///
/// For now the Overlay is only its Minimized Disc — real album art,
/// expanding into a Now Playing card, and lyrics all land in later tickets.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the
/// rotation angle it draws comes from `DiscRotation`, the tested core seam.
@MainActor
final class OverlayController {
    private let window: DiscWindow
    private let view: DiscView
    private let positionPreference: OverlayPositionPreference
    private let visibilityPreference: OverlayVisibilityPreference

    private var rotation = DiscRotation()

    /// Redraws the spinning artwork between Anchors — the core decision
    /// comes from `DiscRotation`; this timer only asks it again and again.
    /// Armed only while playing; a pause cancels it, freezing the artwork
    /// exactly where `DiscRotation` says it stopped.
    private var spinTimer: Timer?
    private static let spinFrameInterval: TimeInterval = 1.0 / 30.0

    /// "Near the top edge," matching where the retired pill used to sit —
    /// a familiar first-launch spot, not a meaningful design commitment.
    private static let defaultTopInset: CGFloat = 8
    private static let defaultTrailingInset: CGFloat = 24

    // nonisolated(unsafe) so deinit may remove it; safe because it's written
    // once in init and never mutated again. Same rationale as
    // `SpotifyNotificationObserver`.
    private nonisolated(unsafe) var moveObserver: NSObjectProtocol?

    init(
        anchorSource: PlaybackAnchorSource,
        visibilityPreference: OverlayVisibilityPreference,
        positionPreference: OverlayPositionPreference
    ) {
        self.visibilityPreference = visibilityPreference
        self.positionPreference = positionPreference

        let view = DiscView()
        self.view = view
        self.window = DiscWindow(contentView: view)

        window.setFrameOrigin(positionPreference.origin ?? Self.defaultOrigin(for: view.frame.size))

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionMoved() }
        }

        refreshVisibility()

        anchorSource.onAnchor { [weak self] state in
            self?.render(state)
        }
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    /// What the status item's "Show Overlay" toggle calls after the
    /// listener flips it, so the change takes effect immediately.
    func refreshVisibility() {
        if visibilityPreference.isVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    private func positionMoved() {
        positionPreference.origin = window.frame.origin
    }

    private func render(_ state: PlaybackState) {
        let now = ContinuousClock.Instant.now
        rotation.anchor(isPlaying: state.isPlaying, at: now)
        view.update(rotationDegrees: rotation.angle(at: now))

        // Anchors arrive far more often than play/pause actually changes —
        // every notification, every re-anchor poll — so only touch the timer
        // on a genuine transition; `spinTimer`'s presence already encodes
        // whether one is running.
        guard state.isPlaying != (spinTimer != nil) else { return }

        guard state.isPlaying else {
            spinTimer?.invalidate()
            spinTimer = nil
            return
        }

        // `.common` mode, not the default: see `PlaybackAnchorSource.start()`
        // — the spin must still redraw while the status item's menu is open.
        let timer = Timer(timeInterval: Self.spinFrameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.redrawSpin() }
        }
        RunLoop.current.add(timer, forMode: .common)
        spinTimer = timer
    }

    private func redrawSpin() {
        view.update(rotationDegrees: rotation.angle(at: ContinuousClock.Instant.now))
    }

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - defaultTrailingInset,
            y: screen.visibleFrame.maxY - size.height - defaultTopInset
        )
    }
}
