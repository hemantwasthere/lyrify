import Foundation
import Testing

@testable import LyrifyCore

/// Tested at the blurring seam, exactly like `ArtworkProviderTests` is
/// tested at the transport seam: a scripted fake plays the blur
/// computation's part, and the tests observe both the outcome and how many
/// times it was actually asked to blur.
@Suite("Blurred artwork provider")
struct BlurredArtworkProviderTests {
    actor FakeBlurring: ArtworkBlurring {
        private(set) var callCount = 0
        private var scripted: [Data?]

        init(scripted: [Data?]) {
            self.scripted = scripted
        }

        func blur(_ artwork: Data) async -> Data? {
            callCount += 1
            guard scripted.isEmpty == false else { return nil }
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

    private let artwork = Data([0xFF, 0xD8, 0xFF])

    @Test("a successful blur answers the blurred data")
    func found() async {
        let blurredData = Data([0x01, 0x02, 0x03])
        let blurring = FakeBlurring(scripted: [blurredData])
        let provider = BlurredArtworkProvider(blurring: blurring)

        let outcome = await provider.blurredBackground(for: track(), artwork: artwork)

        #expect(outcome == .found(blurredData))
    }

    /// Replaying a Track never re-computes its blur.
    @Test("a successful blur is remembered with no second computation")
    func foundRemembered() async {
        let blurredData = Data([0x01, 0x02, 0x03])
        let blurring = FakeBlurring(scripted: [blurredData])
        let provider = BlurredArtworkProvider(blurring: blurring)

        let first = await provider.blurredBackground(for: track(), artwork: artwork)
        let second = await provider.blurredBackground(for: track(), artwork: artwork)

        #expect(first == .found(blurredData))
        #expect(second == first)
        #expect(await blurring.callCount == 1)
    }

    /// Diverges from `ArtworkProvider`/`LyricsProvider`'s own convention on
    /// purpose — see this type's own doc comment: a blur failure is a pure
    /// function of the bytes handed in, not a network flake, so retrying it
    /// can never answer differently.
    @Test("a blur failure is remembered too, with no second computation")
    func failureRemembered() async {
        let blurring = FakeBlurring(scripted: [nil])
        let provider = BlurredArtworkProvider(blurring: blurring)

        let first = await provider.blurredBackground(for: track(), artwork: artwork)
        let second = await provider.blurredBackground(for: track(), artwork: artwork)

        #expect(first == .unavailable)
        #expect(second == .unavailable)
        #expect(await blurring.callCount == 1)
    }

    /// Holds every call open until released, so a test can overlap two
    /// lookups deterministically.
    actor GatedBlurring: ArtworkBlurring {
        private(set) var callCount = 0
        private var gates: [CheckedContinuation<Void, Never>] = []
        private let result: Data?

        init(result: Data?) {
            self.result = result
        }

        func blur(_ artwork: Data) async -> Data? {
            callCount += 1
            await withCheckedContinuation { gates.append($0) }
            return result
        }

        func release() {
            gates.forEach { $0.resume() }
            gates.removeAll()
        }
    }

    /// Skipping A→B→A faster than a blur completes must not compute the
    /// same Track's background twice: concurrent lookups share one flight.
    @Test("concurrent lookups for one Track share a single flight")
    func concurrentLookupsShareFlight() async {
        let blurredData = Data([0x01, 0x02, 0x03])
        let blurring = GatedBlurring(result: blurredData)
        let provider = BlurredArtworkProvider(blurring: blurring)

        async let first = provider.blurredBackground(for: track(), artwork: artwork)
        async let second = provider.blurredBackground(for: track(), artwork: artwork)

        while await blurring.callCount == 0 { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
        await blurring.release()

        let outcomes = await (first, second)
        #expect(outcomes.0 == .found(blurredData))
        #expect(outcomes.1 == outcomes.0)
        #expect(await blurring.callCount == 1)
    }
}
