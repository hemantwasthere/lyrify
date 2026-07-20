import Foundation
import Testing

@testable import LyrifyCore

/// The provider is tested at the transport seam, exactly like the lyrics
/// provider: a scripted fake plays the image host's part, and the tests
/// observe both the outcome and the requests made. No test touches the
/// network.
@Suite("Artwork provider")
struct ArtworkProviderTests {
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

    private let artworkURL = URL(string: "https://i.scdn.co/image/abc123")!

    @Test("a reachable artwork URL answers the fetched image data")
    func found() async {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let transport = FakeTransport(scripted: [(200, imageData)])
        let provider = ArtworkProvider(transport: transport)

        let outcome = await provider.lookup(for: track(), artworkURL: artworkURL)

        #expect(outcome == .found(imageData))
    }

    @Test("no artwork URL from Spotify is a confirmed no-artwork, with no request made")
    func noURLIsNoArtwork() async {
        let transport = FakeTransport(scripted: [])
        let provider = ArtworkProvider(transport: transport)

        let outcome = await provider.lookup(for: track(), artworkURL: nil)

        #expect(outcome == .noArtwork)
        #expect(await transport.requested.isEmpty)
    }

    @Test("a non-200 status is unavailable, not a confirmed no-artwork")
    func nonSuccessStatusIsUnavailable() async {
        let transport = FakeTransport(scripted: [(404, Data())])
        let provider = ArtworkProvider(transport: transport)

        let outcome = await provider.lookup(for: track(), artworkURL: artworkURL)

        #expect(outcome == .unavailable)
    }

    @Test("a transport failure is unavailable, not a confirmed no-artwork")
    func transportFailureIsUnavailable() async {
        let transport = FakeTransport(scripted: [])
        let provider = ArtworkProvider(transport: transport)

        let outcome = await provider.lookup(for: track(), artworkURL: artworkURL)

        #expect(outcome == .unavailable)
    }

    /// Replaying a Track never re-fetches its artwork.
    @Test("found artwork is remembered with no second request")
    func foundRemembered() async {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let transport = FakeTransport(scripted: [(200, imageData)])
        let provider = ArtworkProvider(transport: transport)

        let first = await provider.lookup(for: track(), artworkURL: artworkURL)
        let second = await provider.lookup(for: track(), artworkURL: artworkURL)

        #expect(first == .found(imageData))
        #expect(second == first)
        #expect(await transport.requested.count == 1)
    }

    /// Mirrors the lyrics provider's miss-inclusive caching policy: a
    /// confirmed no-artwork Track is never asked about again.
    @Test("no-artwork is remembered with no second lookup")
    func noArtworkRemembered() async {
        let transport = FakeTransport(scripted: [])
        let provider = ArtworkProvider(transport: transport)

        let first = await provider.lookup(for: track(), artworkURL: nil)
        let second = await provider.lookup(for: track(), artworkURL: nil)

        #expect(first == .noArtwork)
        #expect(second == .noArtwork)
        #expect(await transport.requested.isEmpty)
    }

    /// Unavailability proves nothing about the Track, so it is never
    /// remembered: back online, the artwork can still be fetched.
    @Test("a lookup after unavailability retries the transport")
    func unavailabilityRetries() async {
        let transport = FakeTransport(scripted: [])
        let provider = ArtworkProvider(transport: transport)

        let first = await provider.lookup(for: track(), artworkURL: artworkURL)
        let second = await provider.lookup(for: track(), artworkURL: artworkURL)

        #expect(first == .unavailable)
        #expect(second == .unavailable)
        #expect(await transport.requested.count == 2)
    }

    /// Holds every request open until released, so a test can overlap two
    /// lookups deterministically.
    actor GatedTransport: LyricsTransport {
        private(set) var requested: [URL] = []
        private var gates: [CheckedContinuation<Void, Never>] = []
        private let response: (status: Int, body: Data)

        init(response: (status: Int, body: Data)) {
            self.response = response
        }

        func get(_ url: URL) async throws -> (status: Int, body: Data) {
            requested.append(url)
            await withCheckedContinuation { gates.append($0) }
            return response
        }

        func release() {
            gates.forEach { $0.resume() }
            gates.removeAll()
        }
    }

    /// Skipping A→B→A faster than a fetch completes must not download the
    /// same Track's artwork twice: concurrent lookups share one flight.
    @Test("concurrent lookups for one Track share a single flight")
    func concurrentLookupsShareFlight() async {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let transport = GatedTransport(response: (200, imageData))
        let provider = ArtworkProvider(transport: transport)

        async let first = provider.lookup(for: track(), artworkURL: artworkURL)
        async let second = provider.lookup(for: track(), artworkURL: artworkURL)

        while await transport.requested.isEmpty { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
        await transport.release()

        let outcomes = await (first, second)
        #expect(outcomes.0 == .found(imageData))
        #expect(outcomes.1 == outcomes.0)
        #expect(await transport.requested.count == 1)
    }
}
