import Foundation

/// What a lyrics lookup concluded about a Track.
///
/// The three cases mean different things to whoever remembers them:
/// `found` and `noSyncedLyrics` are confirmed answers the provider's memory
/// holds; `unavailable` proves nothing about the Track and is retried on a
/// later replay instead.
public enum LyricsOutcome: Equatable, Sendable {
    /// Synced Lyrics confidently Matched to this Track.
    case found([LyricLine])

    /// A confirmed miss: nothing usable belongs to this Track — no record,
    /// an instrumental recording, or Plain Lyrics only.
    case noSyncedLyrics

    /// No answer was obtained (offline, service failure, unreadable body).
    case unavailable
}

/// Finds Synced Lyrics for a Track from LRCLIB, the sole source for v1
/// (ADR-0001), through an injected transport so the pipeline is testable
/// without the network.
///
/// An actor because it remembers: confirmed outcomes — found lyrics and
/// misses alike — are held in memory, keyed by Track URI, for the life of
/// the process, so a listener's loops and repeats never burden a free
/// community service twice (ADR-0001). Unavailability is deliberately not
/// remembered: a lookup that failed offline retries on a later replay.
public actor LyricsProvider {
    private let transport: any LyricsTransport

    /// Confirmed outcomes by Track URI. Never holds `.unavailable`.
    private var remembered: [String: LyricsOutcome] = [:]

    /// Lookups still underway, by Track URI. Actors are reentrant across
    /// `await`, so without this a second lookup arriving mid-flight would
    /// run the whole widening sequence again for the same Track.
    private var inFlight: [String: Task<LyricsOutcome, Never>] = [:]

    private static let baseURL = URL(string: "https://lrclib.net")!

    /// The fail-closed knob for the search step. A candidate whose duration
    /// strays further than this from the Track's is a different recording —
    /// a live take, a radio edit, a remaster — whose lyrics would drift
    /// steadily out of time. Two seconds absorbs rounding and encoder padding
    /// while refusing anything structurally different; wrong lyrics cost more
    /// than missing ones (ADR-0003).
    public static let durationTolerance: TimeInterval = 2

    /// How long to wait before each retry of a lookup that came back
    /// `unavailable`, and so how many retries there are.
    ///
    /// LRCLIB is a free community service and it does fall over — measured on
    /// 2026-07-31, consecutive requests returned 504, 504, then 200, and the day
    /// before it was 408s that took ten seconds each to arrive. One attempt per
    /// Track meant a single unlucky request cost the listener lyrics for the
    /// whole song, on a Track that plainly had them, with nothing on screen to
    /// say why. Backing off and asking again turns an outage that long into a
    /// pause rather than a silence.
    ///
    /// The delays lengthen so a service that is genuinely down is not hammered:
    /// four attempts spread over 19 seconds, then it gives up until the Track
    /// comes round again.
    public static let defaultRetryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(12)]

    private let retryDelays: [Duration]

    /// Injected so tests can run the retry path without waiting on a clock.
    private let sleep: @Sendable (Duration) async -> Void

    public init(
        transport: any LyricsTransport,
        retryDelays: [Duration] = LyricsProvider.defaultRetryDelays,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    /// What is known about the Track's lyrics — answered from memory when a
    /// confirmed outcome exists, otherwise concluded fresh from LRCLIB.
    public func lookup(for track: Track) async -> LyricsOutcome {
        // Nothing to Match on. A Non-Lyrical Item has no words, and an item
        // with no duration — live content — cannot be Matched by a service
        // that identifies recordings by their length. Either way the answer is
        // known without asking.
        guard track.isLyrical else { return .noSyncedLyrics }

        if let known = remembered[track.uri] { return known }
        if let pending = inFlight[track.uri] { return await pending.value }

        let flight = Task { await fetchWithRetries(for: track) }
        inFlight[track.uri] = flight
        let outcome = await flight.value
        inFlight[track.uri] = nil

        if outcome != .unavailable {
            remembered[track.uri] = outcome
        }
        return outcome
    }

    /// Runs the widening sequence, and runs it again after a pause for as long as
    /// the answer is `unavailable`.
    ///
    /// Only unavailability is retried. A confirmed miss and found lyrics are both
    /// answers about the Track, and asking twice would say the same thing while
    /// costing a free service a second request; `unavailable` is the one outcome
    /// that says nothing about the Track at all.
    ///
    /// The whole retry sequence lives inside the in-flight Task, so the menu bar
    /// and the Overlay — which look up the same Track independently — wait on one
    /// shared attempt rather than mounting their own.
    private func fetchWithRetries(for track: Track) async -> LyricsOutcome {
        var outcome = await fetchOutcome(for: track)

        for delay in retryDelays where outcome == .unavailable {
            await sleep(delay)
            if Task.isCancelled { return outcome }
            outcome = await fetchOutcome(for: track)
        }
        return outcome
    }

    /// ADR-0003's three widening steps: the exact signature, the same with
    /// the album dropped, then the search. If nothing survives, the answer is
    /// a confirmed miss — never a best guess.
    private func fetchOutcome(for track: Track) async -> LyricsOutcome {
        // A Track with no album cannot answer the album-qualified step, so
        // asking is a request spent on a certain miss. Keyed off the Track
        // lacking an album rather than off where it came from, so the pipeline
        // stays ignorant of origins and Spotify is untouched.
        let albumSteps = track.album.isEmpty ? [false] : [true, false]

        for includeAlbum in albumSteps {
            switch await exactLookup(for: track, includingAlbum: includeAlbum) {
            case .synced(let lines): return .found(lines)
            // An exact-signature instrumental is authoritative: this
            // recording has nothing to sing, and widening could only find
            // words that don't belong to it.
            case .instrumental: return .noSyncedLyrics
            case .missing: continue
            case .failed: return .unavailable
            }
        }

        return await search(for: track)
    }

    private enum StepResult {
        case synced([LyricLine])
        case instrumental
        case missing
        case failed
    }

    private func exactLookup(for track: Track, includingAlbum: Bool) async -> StepResult {
        var query = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "duration", value: String(track.durationInWholeSeconds)),
        ]
        if includingAlbum {
            query.append(URLQueryItem(name: "album_name", value: track.album))
        }

        guard let (status, body) = await fetch(path: "/api/get", query: query) else {
            return .failed
        }
        if status == 404 { return .missing }
        guard status == 200,
              let record = try? JSONDecoder().decode(Record.self, from: body)
        else { return .failed }

        if record.instrumental == true { return .instrumental }
        guard let lines = record.usableSyncedLines else { return .missing }
        return .synced(lines)
    }

    private func search(for track: Track) async -> LyricsOutcome {
        let query = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.name),
        ]
        guard let (status, body) = await fetch(path: "/api/search", query: query),
              status == 200,
              let candidates = try? JSONDecoder().decode([Record].self, from: body)
        else { return .unavailable }

        for candidate in candidates {
            guard candidate.instrumental != true,
                  let duration = candidate.duration,
                  abs(duration - track.duration) <= Self.durationTolerance,
                  let lines = candidate.usableSyncedLines
            else { continue }
            return .found(lines)
        }
        return .noSyncedLyrics
    }

    private func fetch(path: String, query: [URLQueryItem]) async -> (status: Int, body: Data)? {
        var components = URLComponents(
            url: Self.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query

        guard let url = components.url else { return nil }
        return try? await transport.get(url)
    }

    /// The slice of an LRCLIB record the Match needs.
    private struct Record: Decodable {
        let syncedLyrics: String?
        let duration: Double?
        let instrumental: Bool?

        /// Lyric Lines this record can honestly contribute, or nothing.
        var usableSyncedLines: [LyricLine]? {
            guard let syncedLyrics,
                  let lines = try? SyncedLyricsParser.parse(syncedLyrics),
                  lines.isEmpty == false
            else { return nil }
            return lines
        }
    }
}
