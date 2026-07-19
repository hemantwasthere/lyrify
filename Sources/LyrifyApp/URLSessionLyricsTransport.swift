import Foundation
import LyrifyCore

/// The production transport: URLSession plus the honest User-Agent that
/// ADR-0001 owes LRCLIB — a free community service should always see who is
/// asking.
struct URLSessionLyricsTransport: LyricsTransport {
    private static let userAgent =
        "Lyrify/0.1.0 (+https://github.com/hemantwasthere/lyrify)"

    func get(_ url: URL) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, body)
    }
}
