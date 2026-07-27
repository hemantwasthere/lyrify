import Foundation

/// The Expanded card's dragged-resize dimensions, persisted across launches
/// alongside its position. Nil until the listener has resized it at least
/// once — the caller decides what default to use meanwhile, this type only
/// remembers. The Minimized Disc has its own fixed size and never consults
/// this.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class OverlaySizePreference {
    private static let widthKey = "OverlayCardWidth"
    private static let heightKey = "OverlayCardHeight"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var size: CGSize? {
        get {
            guard let width = defaults.object(forKey: Self.widthKey) as? Double,
                  let height = defaults.object(forKey: Self.heightKey) as? Double
            else { return nil }
            return CGSize(width: width, height: height)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Self.widthKey)
                defaults.removeObject(forKey: Self.heightKey)
                return
            }
            defaults.set(newValue.width, forKey: Self.widthKey)
            defaults.set(newValue.height, forKey: Self.heightKey)
        }
    }
}
