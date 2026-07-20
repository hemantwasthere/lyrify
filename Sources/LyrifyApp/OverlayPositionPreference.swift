import Foundation

/// Where the listener last dragged the Overlay, persisted across launches.
/// Nil until the Overlay has been dragged at least once — the caller decides
/// what to do with no remembered position, this type only remembers.
///
/// Deliberately untested — a thin `UserDefaults` wrapper with no decision of
/// its own to get wrong.
final class OverlayPositionPreference {
    private static let xKey = "OverlayPositionX"
    private static let yKey = "OverlayPositionY"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var origin: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Self.xKey) as? Double,
                  let y = defaults.object(forKey: Self.yKey) as? Double
            else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Self.xKey)
                defaults.removeObject(forKey: Self.yKey)
                return
            }
            defaults.set(newValue.x, forKey: Self.xKey)
            defaults.set(newValue.y, forKey: Self.yKey)
        }
    }
}
