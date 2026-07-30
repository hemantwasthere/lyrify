import Foundation
import LyrifyCore

/// The production transport: URLSession plus the honest User-Agent that
/// ADR-0001 owes LRCLIB — a free community service should always see who is
/// asking.
struct URLSessionLyricsTransport: LyricsTransport {
    private static let userAgent =
        "Lyrify/0.1.0 (+https://github.com/hemantwasthere/lyrify)"

    /// URLSession's own default is 60 seconds, which is far too patient for this.
    ///
    /// When LRCLIB is struggling it does not refuse connections, it accepts them
    /// and then hangs — measured on 2026-07-31, requests that eventually failed
    /// took over 25 seconds, and some never answered at all. At the default a
    /// single such request outlives most songs, and `LyricsProvider`'s retries
    /// never get a turn. Eight seconds is well beyond LRCLIB's healthy response
    /// time, so this gives up on a hung request rather than a slow one.
    private static let timeout: TimeInterval = 8

    func get(_ url: URL) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.timeout

        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, body)
    }
}
