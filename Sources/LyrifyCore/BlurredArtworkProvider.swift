import Foundation

/// Turns raw artwork bytes into the treatment Full Layout's background uses
/// behind its smaller, sharp artwork copy — a Gaussian blur plus a
/// saturation boost, in production (`CoreImageArtworkBlur`). Injected so
/// `BlurredArtworkProvider` is testable without CoreImage in the loop, the
/// same reason `LyricsProvider`/`ArtworkProvider` take an injected transport
/// rather than calling `URLSession` directly.
public protocol ArtworkBlurring: Sendable {
    /// Nil means the computation itself failed (corrupt or unrecognized
    /// image data) — never thrown, since there is no retry that would help.
    func blur(_ artwork: Data) async -> Data?
}

/// Computes and remembers the blurred background treatment for a Track's
/// artwork, mirroring `ArtworkProvider`'s shape closely — actor-for-memory,
/// in-flight dedup, Track-URI-keyed.
///
/// One deliberate divergence from `ArtworkProvider`/`LyricsProvider`'s own
/// miss-inclusive policy: those two never remember `.unavailable`, because
/// a failed *network* fetch can easily succeed on a later replay. Here,
/// `blur(_:)` is a pure function of the artwork bytes already in hand — no
/// network, nothing that can change between calls — so a failure is
/// remembered too: retrying the exact same bytes through the exact same
/// computation can never produce a different answer.
public actor BlurredArtworkProvider {
    public enum Outcome: Equatable, Sendable {
        /// The blurred, color-boosted image bytes.
        case found(Data)

        /// The blur computation failed on this artwork's bytes.
        case unavailable
    }

    private let blurring: any ArtworkBlurring

    private var remembered: [String: Outcome] = [:]
    private var inFlight: [String: Task<Outcome, Never>] = [:]

    public init(blurring: any ArtworkBlurring) {
        self.blurring = blurring
    }

    /// The blurred background for `track`'s artwork — computed from
    /// `artwork`, the same bytes `ArtworkProvider.lookup(for:artworkURL:)`
    /// already answered as `.found(Data)` for this Track; the caller
    /// resolves that first, so this type never needs a fetch path of its
    /// own.
    public func blurredBackground(for track: Track, artwork: Data) async -> Outcome {
        if let known = remembered[track.uri] { return known }
        if let pending = inFlight[track.uri] { return await pending.value }

        let blurring = self.blurring
        let flight = Task {
            if let blurred = await blurring.blur(artwork) {
                return Outcome.found(blurred)
            }
            return Outcome.unavailable
        }
        inFlight[track.uri] = flight
        let outcome = await flight.value
        inFlight[track.uri] = nil
        remembered[track.uri] = outcome
        return outcome
    }
}
