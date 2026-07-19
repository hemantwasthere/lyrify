import Foundation

/// Finds Synced Lyrics for a Track from LRCLIB, the sole source for v1
/// (ADR-0001), through an injected transport so the pipeline is testable
/// without the network.
///
/// This is the exact-signature step only: artist, title, album and
/// whole-second duration must all line up. The widening, fail-closed Match
/// (ADR-0003) arrives in ticket #8; remembering outcomes so replays never
/// ask twice (ADR-0001) arrives in ticket #9.
public struct LyricsProvider: Sendable {
    private let transport: any LyricsTransport

    private static let baseURL = URL(string: "https://lrclib.net")!

    public init(transport: any LyricsTransport) {
        self.transport = transport
    }

    /// Synced Lyrics for the Track, or nothing.
    public func lyrics(for track: Track) async -> [LyricLine]? {
        var components = URLComponents(
            url: Self.baseURL.appending(path: "/api/get"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(track.durationInWholeSeconds)),
        ]

        guard let url = components.url,
              let (status, body) = try? await transport.get(url),
              status == 200,
              let record = try? JSONDecoder().decode(Record.self, from: body),
              let syncedText = record.syncedLyrics,
              let lines = try? SyncedLyricsParser.parse(syncedText),
              lines.isEmpty == false
        else { return nil }

        return lines
    }

    /// The slice of an LRCLIB record the exact step needs.
    private struct Record: Decodable {
        let syncedLyrics: String?
    }
}
