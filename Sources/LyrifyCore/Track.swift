import Foundation

/// A single recording playing in Spotify, identified by its Spotify URI.
///
/// The URI is the canonical identity used wherever a Track must be named or
/// remembered — cache keys, per-track offsets, and telling a Track apart from a
/// Non-Lyrical Item.
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
    }

    /// The duration in whole seconds, which is the form a lyrics lookup matches on.
    public var durationInWholeSeconds: Int {
        Int(duration.rounded())
    }

    /// Whether lyrics could ever exist for this item. Anything that is not a
    /// Spotify track — an advertisement, a podcast episode, a local file — is
    /// a Non-Lyrical Item, and querying a lyrics database for one is nonsense.
    public var isLyrical: Bool {
        uri.hasPrefix("spotify:track:")
    }
}
