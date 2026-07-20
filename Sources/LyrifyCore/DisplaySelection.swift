import Foundation

/// Resolves which display actually carries the Overlay: the listener's
/// remembered choice when it's still attached, otherwise the main display —
/// without forgetting the remembered choice, so a reattached display is
/// picked up again automatically. Keeping the preference itself is the
/// caller's job; this seam only ever answers which display to use right now.
public enum DisplaySelection {
    public static func resolve(
        remembered: UInt32?,
        attached: [UInt32],
        mainDisplay: UInt32
    ) -> UInt32 {
        if let remembered, attached.contains(remembered) {
            return remembered
        }
        return mainDisplay
    }
}
