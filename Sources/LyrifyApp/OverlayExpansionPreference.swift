import Foundation

/// Whether the Overlay was last left Expanded (the Now Playing card) or
/// Minimized (the Disc), persisted across launches alongside its position.
/// Defaults to Minimized — the Disc is the Overlay's resting state.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class OverlayExpansionPreference {
    private static let key = "OverlayExpanded"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isExpanded: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
