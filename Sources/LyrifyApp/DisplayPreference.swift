import Foundation

/// The listener's chosen display, persisted across launches. Storing the
/// preference is distinct from resolving it: `DisplaySelection` in the core
/// package decides which display to actually use, given this and what's
/// currently attached.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class DisplayPreference {
    private static let key = "OverlayDisplayID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var remembered: UInt32? {
        get { (defaults.object(forKey: Self.key) as? NSNumber)?.uint32Value }
        set {
            if let newValue {
                defaults.set(NSNumber(value: newValue), forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}
