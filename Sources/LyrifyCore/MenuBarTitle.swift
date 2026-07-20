import Foundation

/// What the menu bar reads for a given `PlaybackState`.
///
/// Pure, so the wording and truncation rules are testable without a status item.
public enum MenuBarTitle {
    /// Long enough to be useful, short enough not to crowd out other menu bar
    /// items on a laptop display.
    public static let maximumLength = 45

    private static let separator = " — "

    /// The title to show, or `nil` when Lyrify should show only its icon.
    public static func text(for state: PlaybackState) -> String? {
        guard let track = state.track else { return nil }

        return text(for: track)
    }

    /// The same name — artist wording, for a caller that already has a
    /// `Track` in hand rather than a full `PlaybackState`. The Overlay's
    /// Idle State reuses this so it never drifts from the menu bar's wording.
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
