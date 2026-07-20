import Foundation

/// Whether the listener wants the Overlay on screen at all, persisted across
/// launches. Defaults to visible, so the toggle is something a listener
/// turns off rather than something they must turn on.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class OverlayVisibilityPreference {
    private static let key = "OverlayVisible"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isVisible: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
