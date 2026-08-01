import Foundation

/// Whether the Expanded card is held on the Lyrics view with its Info Bar
/// taken away, persisted across launches. Defaults to off — the card has
/// always carried its title and artist, and a new install should get what it
/// has always got.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class OverlayLyricsOnlyPreference {
    private static let key = "OverlayLyricsOnly"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
