import Foundation
import LyrifyCore

/// The Offsets a listener has applied, persisted across launches so a video
/// corrected once stays corrected.
///
/// Deliberately untested — a thin `UserDefaults` wrapper whose only decisions
/// live in `LyricsOffsets`, which is tested.
final class LyricsOffsetsPreference {
    private static let key = "LyricsOffsets"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var offsets: LyricsOffsets {
        get {
            let stored = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
            return LyricsOffsets(stored: stored)
        }
        set { defaults.set(newValue.stored, forKey: Self.key) }
    }
}
