import Foundation

/// Whether the card tints itself from the current Track's album art, persisted
/// across launches. Defaults to on, matching what the Overlay has always drawn;
/// turning it off leaves a plain near-black card, which is what Spotify's own
/// "Background color" switch does to its miniplayer.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class OverlayBackgroundColorPreference {
    private static let key = "OverlayBackgroundColorEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
