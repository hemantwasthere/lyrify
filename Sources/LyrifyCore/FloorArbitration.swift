import Foundation

/// Who owns playback, decided from the Now Playing Floor.
///
/// macOS already answers this question for the whole system — the Floor is what
/// the media keys and Control Center obey — so Lyrify reads that answer rather
/// than inventing one. There is no preference and no source selector, because
/// the listener has already chosen by pressing play.
///
/// The Floor is single-valued. Exactly one application holds it and the other
/// Player is not observable at all, so this is a decision about *identity*
/// rather than a comparison between two readings: it says who to ask, and that
/// Player says what is playing.
///
/// A paused application keeps the Floor, which is why nothing here treats a
/// holder's existence as proof that something is playing. Whether it is playing
/// or paused is the Player's own answer, faithfully carried through — a paused
/// Track is still a Track worth showing, exactly as it always has been for
/// Spotify.
public enum FloorArbitration {
    public enum Owner: Equatable, Sendable {
        /// Followed over Apple Events instead, where the Track carries the URI
        /// that keys lyrics memoisation, the album the first widening step
        /// Matches on, and the transport controls.
        case spotify

        /// Followed through the Floor itself, which is all there is.
        case browser

        /// Something else holds the Floor — Music, a video player, a
        /// conferencing app. Showing its media as though it were a video would
        /// be a wrong Track, which costs more than a missing one.
        case unrecognised

        /// Nothing holds the Floor: nothing is playing anywhere.
        case nobody
    }

    public static let spotifyBundleIdentifier = "com.spotify.client"

    /// The browsers whose media is followed.
    ///
    /// An allowlist rather than "anything that is not Spotify", because the
    /// Floor carries every media application on the machine and most of them
    /// are not browsers. A browser missing from here is followed as
    /// `unrecognised` — quiet and honest — rather than wrongly, so adding one
    /// is a safe change.
    public static let browserBundleIdentifiers: Set<String> = [
        "company.thebrowser.Browser",  // Arc
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "app.zen-browser.zen",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.thebrowser.dia",  // Dia
    ]

    /// Who to follow, given who publishes to the Floor and — where the
    /// publisher is a helper process — the application behind it.
    ///
    /// The publishing identity is preferred and the parent consulted only for
    /// what it could not answer. No browser was ever observed publishing from a
    /// helper (see `docs/findings/2026-08-02-now-playing-floor.md`), so the
    /// parent is defence against a shape the adapter documents rather than one
    /// seen in the wild; its absence is not a defect.
    public static func owner(holder: String?, parent: String?) -> Owner {
        guard let holder else { return .nobody }

        for identifier in [holder, parent].compactMap({ $0 }) {
            if identifier == spotifyBundleIdentifier { return .spotify }
            if browserBundleIdentifiers.contains(identifier) { return .browser }
        }
        return .unrecognised
    }
}
