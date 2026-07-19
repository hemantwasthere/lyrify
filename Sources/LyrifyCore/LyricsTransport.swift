import Foundation

/// How the lyrics provider reaches the network.
///
/// The port exists so the whole lookup pipeline — stepping, Matching,
/// remembering — can be driven by a scripted fake in tests; the production
/// implementation is a thin URLSession wrapper in the app target that adds
/// Lyrify's honest User-Agent (ADR-0001).
public protocol LyricsTransport: Sendable {
    /// Performs a GET, answering the HTTP status and body.
    ///
    /// Throws only when no response was obtained at all (offline, timeout);
    /// a non-success status is an answer, not an error — 404 is how LRCLIB
    /// says "no such record".
    func get(_ url: URL) async throws -> (status: Int, body: Data)
}
