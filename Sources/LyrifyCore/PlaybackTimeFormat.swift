import Foundation

/// What Full Layout's always-visible seek bar shows for elapsed and
/// remaining time — "m:ss", gaining an hours component past an hour.
///
/// Pure, so the formatting rules are testable without a live seek bar.
public enum PlaybackTimeFormat {
    public static func string(forSeconds seconds: TimeInterval) -> String {
        // A Playback Position can't be negative, but floating-point drift
        // right at a Track's boundary could otherwise produce one.
        let totalSeconds = Int(max(0, seconds))

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        guard hours > 0 else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}
