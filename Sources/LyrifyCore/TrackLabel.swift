import Foundation

/// How a Track is named in one line: `name — artist`, truncated.
///
/// This was `MenuBarTitle`, and was named for its only caller until the status
/// item stopped showing text at all. The Overlay's Idle State is what reads it
/// now, so the wording lives here rather than in the view — pure, and testable
/// without a window.
public enum TrackLabel {
    /// Long enough to name almost anything, short enough that the Idle State
    /// stays one line in the narrowest card the Overlay can be dragged to.
    public static let maximumLength = 45

    private static let separator = " — "

    public static func text(for track: Track) -> String {
        truncated(track.name + separator + track.artist)
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maximumLength else { return text }

        let kept = text.prefix(maximumLength - 1)
            .trimmingCharacters(in: .whitespaces)
        return kept + "…"
    }
}
