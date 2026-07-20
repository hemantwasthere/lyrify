import AppKit

/// Owns the Overlay's window and keeps it where the listener left it.
///
/// For now the Overlay is only its Minimized Disc — spinning with playback,
/// real album art, expanding into a Now Playing card, and lyrics all land in
/// later tickets. This controller's whole job today is presence: show or
/// hide per the listener's toggle, and remember exactly where it was
/// dragged.
///
/// Deliberately untested — thin AppKit wiring verified by hand.
@MainActor
final class OverlayController {
    private let window: DiscWindow
    private let positionPreference: OverlayPositionPreference
    private let visibilityPreference: OverlayVisibilityPreference

    /// "Near the top edge," matching where the retired pill used to sit —
    /// a familiar first-launch spot, not a meaningful design commitment.
    private static let defaultTopInset: CGFloat = 8
    private static let defaultTrailingInset: CGFloat = 24

    // nonisolated(unsafe) so deinit may remove it; safe because it's written
    // once in init and never mutated again. Same rationale as
    // `SpotifyNotificationObserver`.
    private nonisolated(unsafe) var moveObserver: NSObjectProtocol?

    init(visibilityPreference: OverlayVisibilityPreference, positionPreference: OverlayPositionPreference) {
        self.visibilityPreference = visibilityPreference
        self.positionPreference = positionPreference

        let view = DiscView()
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

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - defaultTrailingInset,
            y: screen.visibleFrame.maxY - size.height - defaultTopInset
        )
    }
}
