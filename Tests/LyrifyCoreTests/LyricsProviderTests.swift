import Foundation
import Testing

@testable import LyrifyCore

/// The provider is tested at the transport seam: a scripted fake plays
/// LRCLIB's part, and the tests observe both the outcome and the requests
/// made. No test touches the network.
@Suite("Lyrics provider")
struct LyricsProviderTests {
    actor FakeTransport: LyricsTransport {
        private(set) var requested: [URL] = []
        private var scripted: [(status: Int, body: Data)]

        init(scripted: [(status: Int, body: Data)]) {
            self.scripted = scripted
        }

        func get(_ url: URL) async throws -> (status: Int, body: Data) {
            requested.append(url)
            guard scripted.isEmpty == false else {
                throw URLError(.badServerResponse)
            }
            return scripted.removeFirst()
        }
    }

    private func track() -> Track {
        Track(
            uri: "spotify:track:2X485T9Z5Ly0xyaghN73ed",
            name: "Let It Happen",
            artist: "Tame Impala",
            album: "Currents",
            duration: 467.586
        )
    }

    private func record(syncedLyrics: String?) -> Data {
        let lyrics = syncedLyrics.map { "\"\($0)\"" } ?? "null"
        return Data(#"{"id":1,"syncedLyrics":\#(lyrics)}"#.utf8)
    }

    private func candidate(duration: Double, syncedLyrics: String?) -> String {
        let lyrics = syncedLyrics.map { "\"\($0)\"" } ?? "null"
        return #"{"id":1,"duration":\#(duration),"syncedLyrics":\#(lyrics)}"#
    }

    private func searchBody(_ candidates: [String]) -> Data {
        Data("[\(candidates.joined(separator: ","))]".utf8)
    }

    /// Scripts the two exact steps missing, so the lookup reaches the search.
    private func missesThenSearch(_ candidates: [String]) -> [(status: Int, body: Data)] {
        [(404, Data()), (404, Data()), (200, searchBody(candidates))]
    }

    @Test("an exact-signature hit answers Synced Lyrics")
    func exactHit() async throws {
        let transport = FakeTransport(scripted: [
            (200, record(syncedLyrics: #"[00:10.00] first\n[00:20.00] second"#))
        ])
        let provider = LyricsProvider(transport: transport)

        let outcome = await provider.lookup(for: track())

        #expect(outcome == .found([
            LyricLine(text: "first", start: 10),
            LyricLine(text: "second", start: 20),
        ]))
    }

    @Test("the exact lookup sends artist, title, album and whole-second duration")
    func exactRequestShape() async throws {
        let transport = FakeTransport(scripted: [
            (200, record(syncedLyrics: #"[00:10.00] first"#))
        ])
        let provider = LyricsProvider(transport: transport)

        _ = await provider.lookup(for: track())

        let url = try #require(await transport.requested.first)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "lrclib.net")
        #expect(components.path == "/api/get")
        #expect(Set(components.queryItems ?? []) == Set([
            URLQueryItem(name: "artist_name", value: "Tame Impala"),
            URLQueryItem(name: "track_name", value: "Let It Happen"),
            URLQueryItem(name: "album_name", value: "Currents"),
            URLQueryItem(name: "duration", value: "468"),
        ]))
    }

    /// ADR-0003's three widening steps, observed as the request sequence:
    /// exact signature, the same without the album, then the search.
    @Test("a miss widens: album dropped, then search, then a confirmed miss")
    func widening() async throws {
        let transport = FakeTransport(scripted: [
            (404, Data()),
            (404, Data()),
            (200, Data("[]".utf8)),
        ])
        let provider = LyricsProvider(transport: transport)

        let outcome = await provider.lookup(for: track())

        #expect(outcome == .noSyncedLyrics)

        let requests = await transport.requested
        #expect(requests.count == 3)

        let secondURL = try #require(requests.dropFirst().first)
        let second = try #require(URLComponents(url: secondURL, resolvingAgainstBaseURL: false))
        #expect(second.path == "/api/get")
        #expect(Set(second.queryItems ?? []) == Set([
            URLQueryItem(name: "artist_name", value: "Tame Impala"),
            URLQueryItem(name: "track_name", value: "Let It Happen"),
            URLQueryItem(name: "duration", value: "468"),
        ]))

        let thirdURL = try #require(requests.last)
        let third = try #require(URLComponents(url: thirdURL, resolvingAgainstBaseURL: false))
        #expect(third.path == "/api/search")
        #expect(Set(third.queryItems ?? []) == Set([
            URLQueryItem(name: "artist_name", value: "Tame Impala"),
            URLQueryItem(name: "track_name", value: "Let It Happen"),
        ]))
    }

    /// The most common recovery ADR-0003 predicts: Spotify reports a deluxe
    /// edition where the lyrics database holds the original album.
    @Test("a deluxe-edition Track recovers its lyrics via the album-dropped step")
    func albumDroppedRecovery() async throws {
        let transport = FakeTransport(scripted: [
            (404, Data()),
            (200, record(syncedLyrics: #"[00:10.00] recovered"#)),
        ])
        let provider = LyricsProvider(transport: transport)

        let outcome = await provider.lookup(for: track())

        #expect(outcome == .found([LyricLine(text: "recovered", start: 10)]))
        #expect(await transport.requested.count == 2)
    }

    /// Duration is the arbiter: lyrics from a live take or radio edit drift
    /// steadily out of time, which reads as a broken app. Better nothing.
    @Test("search candidates outside the duration tolerance are refused")
    func durationGate() async {
        let transport = FakeTransport(scripted: missesThenSearch([
            candidate(duration: 420, syncedLyrics: #"[00:10.00] live take"#),
            candidate(duration: 500, syncedLyrics: #"[00:10.00] extended mix"#),
        ]))
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lookup(for: track()) == .noSyncedLyrics)
    }

    /// First survivor wins, and the gate is inclusive at exactly the
    /// tolerance.
    @Test("the first candidate within the duration tolerance wins")
    func firstSurvivorWins() async {
        let transport = FakeTransport(scripted: missesThenSearch([
            candidate(duration: 420, syncedLyrics: #"[00:10.00] wrong"#),
            candidate(duration: 465.586, syncedLyrics: #"[00:10.00] edge"#),
            candidate(duration: 467, syncedLyrics: #"[00:10.00] never reached"#),
        ]))
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lookup(for: track()) == .found([
            LyricLine(text: "edge", start: 10)
        ]))
    }

    /// An exact-signature instrumental is authoritative: this recording has
    /// nothing to sing. Widening could only find words that don't belong.
    @Test("an instrumental exact match is a confirmed miss and stops the widening")
    func instrumentalStops() async {
        let transport = FakeTransport(scripted: [
            (200, Data(#"{"id":1,"instrumental":true,"syncedLyrics":null}"#.utf8))
        ])
        let provider = LyricsProvider(transport: transport)

        let outcome = await provider.lookup(for: track())

        #expect(outcome == .noSyncedLyrics)
        #expect(await transport.requested.count == 1)
    }

    /// Plain-only is not authoritative the way instrumental is: another
    /// edition of the same recording may carry Synced Lyrics, and duration
    /// still guards the widening.
    @Test("a plain-only exact match keeps widening before confirming the miss")
    func plainOnlyWidens() async {
        let transport = FakeTransport(scripted: [
            (200, record(syncedLyrics: nil)),
            (404, Data()),
            (200, searchBody([])),
        ])
        let provider = LyricsProvider(transport: transport)

        let outcome = await provider.lookup(for: track())

        #expect(outcome == .noSyncedLyrics)
        #expect(await transport.requested.count == 3)
    }

    /// Community data can be contradictory: a candidate flagged instrumental
    /// yet carrying synced text is not evidence worth trusting.
    @Test("an instrumental search candidate is never accepted as lyrics")
    func instrumentalCandidateSkipped() async {
        let transport = FakeTransport(scripted: missesThenSearch([
            #"{"id":1,"duration":467.586,"instrumental":true,"syncedLyrics":"[00:10.00] stray"}"#
        ]))
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lookup(for: track()) == .noSyncedLyrics)
    }

    /// Offline is not "no lyrics exist": unavailability must stay
    /// distinguishable so a later replay can retry.
    @Test("a transport failure is unavailability, not a miss")
    func transportFailure() async {
        let transport = FakeTransport(scripted: [])
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lookup(for: track()) == .unavailable)
    }

    /// A body we cannot read proves nothing about the Track; caching a miss
    /// from it would be a guess.
    @Test("an unparseable body is unavailability")
    func malformedBody() async {
        let transport = FakeTransport(scripted: [(200, Data("not json".utf8))])
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lookup(for: track()) == .unavailable)
    }
}
