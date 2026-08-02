import Foundation

/// A single recording being played, by Spotify or by a browser.
///
/// The URI is the canonical identity used wherever a Track must be named or
/// remembered — cache keys and per-track offsets. Spotify supplies its own; a
/// Track observed on the Now Playing Floor has none to supply, so one is
/// composed for it (see the browser initialiser).
///
/// Whether lyrics could ever exist for a Track is settled here, at
/// construction, by whichever initialiser knows the rules for that Player. It
/// is a property rather than a question asked of the URI later, because the two
/// Players answer it for entirely different reasons and no single prefix test
/// could serve both.
public struct Track: Equatable, Sendable {
    public let uri: String
    public let name: String
    public let artist: String
    public let album: String

    /// Length of the recording, in seconds.
    ///
    /// Spotify's scripting definition reports this in milliseconds despite
    /// declaring seconds; the conversion happens once, at the boundary, in
    /// `PlayerScriptOutput`. See ADR-0002.
    public let duration: TimeInterval

    /// Whether lyrics could ever exist for this Track.
    ///
    /// Answered at construction, differently per Player: Spotify says so by the
    /// kind of thing its URI names, a browser by whether the item has a
    /// duration to Match against at all.
    public let isLyrical: Bool

    /// A Track as Spotify names it.
    ///
    /// Anything that is not a Spotify track — an advertisement, a podcast
    /// episode, a local file — is a Non-Lyrical Item, and querying a lyrics
    /// database for one is nonsense.
    public init(
        uri: String,
        name: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) {
        self.uri = uri
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isLyrical = uri.hasPrefix("spotify:track:")
    }

    /// A Track observed on the Now Playing Floor.
    ///
    /// The title and channel are read into an artist and a track name here, at
    /// the boundary, so that everything downstream receives an ordinary Track
    /// and the lyrics pipeline never learns YouTube exists. There is no album;
    /// the Floor reports an empty one for every browser item.
    ///
    /// Identity is composed from the publishing application and the two fields
    /// that distinguish one video from the next. It has to be stable across
    /// readings — memoised lyrics are keyed on it — so it is built from the
    /// values themselves rather than hashed, `Hasher` being deliberately
    /// unstable between runs. The separator is the same one the Spotify
    /// bridge uses, chosen because it cannot occur in a title.
    ///
    /// A `duration` that is absent or not finite means live content: a
    /// Premiere or a stream, which reports no length because it has none. Such
    /// a Track can never be Matched — every lyrics lookup needs a duration —
    /// so it is not lyrical, and its duration reads as zero rather than
    /// pretending to a length nothing observed.
    public init(
        floorBundleIdentifier: String,
        title: String,
        channel: String,
        duration: TimeInterval?
    ) {
        // Identity is composed from the *raw* title and channel, never the
        // reading of them. Memoised lyrics are keyed on it, so sharpening how
        // titles are read must not silently orphan everything remembered.
        let separator = PlayerScriptOutput.fieldSeparator
        self.uri = "browser:\(floorBundleIdentifier):\(title)\(separator)\(channel)"

        let reading = VideoTitle.read(title: title, channel: channel)
        self.name = reading.name
        self.artist = reading.artist
        self.album = ""

        if let duration, duration.isFinite {
            self.duration = duration
            self.isLyrical = true
        } else {
            self.duration = 0
            self.isLyrical = false
        }
    }

    /// The duration in whole seconds, which is the form a lyrics lookup matches on.
    public var durationInWholeSeconds: Int {
        Int(duration.rounded())
    }

}
