import Foundation

/// What an artwork lookup concluded about a Track.
///
/// The three cases mean different things to whoever remembers them, exactly
/// like `LyricsOutcome`: `found` and `noArtwork` are confirmed answers the
/// provider's memory holds; `unavailable` proves nothing about the Track and
/// is retried on a later replay instead.
public enum ArtworkOutcome: Equatable, Sendable {
    /// The image bytes fetched from the Track's reported artwork URL.
    case found(Data)

    /// A confirmed miss: Spotify reported no artwork URL at all for this
    /// Track — an ad, most Non-Lyrical Items, or a Track that simply has
    /// none.
    case noArtwork

    /// No answer was obtained (offline, host failure, a non-success status).
    case unavailable
}

/// Fetches and remembers album artwork for a Track, mirroring
/// `LyricsProvider`'s shape closely — down to the actor-for-memory,
/// in-flight-dedup, and miss-inclusive caching policy.
///
/// The artwork URL itself is Spotify's to report, not this type's to guess;
/// callers supply it (via a live `PlayerBridge` read) so the actor's own
/// job stays narrow: given a Track and the URL Spotify reported for it right
/// now, answer what the artwork actually is.
public actor ArtworkProvider {
    private let transport: any LyricsTransport

    /// Confirmed outcomes by Track URI. Never holds `.unavailable`.
    private var remembered: [String: ArtworkOutcome] = [:]

    /// Lookups still underway, by Track URI — the same reentrancy guard
    /// `LyricsProvider` needs, for the same reason.
    private var inFlight: [String: Task<ArtworkOutcome, Never>] = [:]

    public init(transport: any LyricsTransport) {
        self.transport = transport
    }

    /// What is known about the Track's artwork — answered from memory when a
    /// confirmed outcome exists, otherwise fetched fresh from `artworkURL`.
    /// A nil `artworkURL` is answered as `.noArtwork` immediately, with no
    /// request made.
    public func lookup(for track: Track, artworkURL: URL?) async -> ArtworkOutcome {
        if let known = remembered[track.uri] { return known }
        if let pending = inFlight[track.uri] { return await pending.value }

        guard let artworkURL else {
            remembered[track.uri] = .noArtwork
            return .noArtwork
        }

        let flight = Task { await fetchOutcome(from: artworkURL) }
        inFlight[track.uri] = flight
        let outcome = await flight.value
        inFlight[track.uri] = nil

        if outcome != .unavailable {
            remembered[track.uri] = outcome
        }
        return outcome
    }

    private func fetchOutcome(from url: URL) async -> ArtworkOutcome {
        guard let (status, body) = try? await transport.get(url), status == 200 else {
            return .unavailable
        }
        return .found(body)
    }
}
