import Foundation

/// Resolves a Track's Spotify share link — the same
/// `https://open.spotify.com/track/<id>` URL Spotify's own "Copy Song Link"
/// action would produce — from its Spotify URI alone (the URI is a Track's
/// canonical identity, per the glossary); no network call involved, no
/// lookup, just a string transformation.
///
/// A Non-Lyrical Item's differently-shaped URI, a malformed or empty one, or
/// no URI at all (no current Track), all resolve to nil rather than a broken
/// or nonsensical link: Fail Closed, the same governing policy Matching
/// applies to lyrics.
public enum SpotifyShareLink {
    public static func resolve(uri: String?) -> URL? {
        guard let uri, uri.hasPrefix(Track.trackURIPrefix) else { return nil }

        let id = uri.dropFirst(Track.trackURIPrefix.count)
        guard !id.isEmpty else { return nil }

        return URL(string: "https://open.spotify.com/track/\(id)")
    }
}
