import Foundation

/// Whether Full Layout's artwork area shows the blurred, color-boosted
/// background or a plain copy of the artwork instead, persisted across
/// launches. Defaults to on, matching the settings panel's own toggle.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class BlurredBackgroundPreference {
    private static let key = "OverlayBlurredBackgroundEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
