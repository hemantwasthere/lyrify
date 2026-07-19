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

    @Test("an exact-signature hit answers Synced Lyrics")
    func exactHit() async throws {
        let transport = FakeTransport(scripted: [
            (200, record(syncedLyrics: #"[00:10.00] first\n[00:20.00] second"#))
        ])
        let provider = LyricsProvider(transport: transport)

        let lyrics = await provider.lyrics(for: track())

        #expect(lyrics == [
            LyricLine(text: "first", start: 10),
            LyricLine(text: "second", start: 20),
        ])
    }

    @Test("the exact lookup sends artist, title, album and whole-second duration")
    func exactRequestShape() async throws {
        let transport = FakeTransport(scripted: [
            (200, record(syncedLyrics: #"[00:10.00] first"#))
        ])
        let provider = LyricsProvider(transport: transport)

        _ = await provider.lyrics(for: track())

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

    /// 404 is LRCLIB's "no such record" — an answer, not an error.
    @Test("a 404 answers nothing")
    func notFound() async {
        let transport = FakeTransport(scripted: [(404, Data())])
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lyrics(for: track()) == nil)
    }

    /// Plain Lyrics are treated as no lyrics at all: a two-line overlay
    /// cannot know which line is current.
    @Test("a record with only Plain Lyrics answers nothing")
    func plainOnly() async {
        let transport = FakeTransport(scripted: [(200, record(syncedLyrics: nil))])
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lyrics(for: track()) == nil)
    }

    @Test("a transport failure answers nothing")
    func transportFailure() async {
        let transport = FakeTransport(scripted: [])
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lyrics(for: track()) == nil)
    }

    @Test("an unparseable body answers nothing")
    func malformedBody() async {
        let transport = FakeTransport(scripted: [(200, Data("not json".utf8))])
        let provider = LyricsProvider(transport: transport)

        #expect(await provider.lyrics(for: track()) == nil)
    }
}
