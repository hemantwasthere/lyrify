import Foundation

/// Turns the single delimited line produced by the Spotify scripting bridge
/// into a `PlaybackState`.
///
/// Spotify is the only player this parses for today — the line's shape is
/// dictated by the AppleScript that produces it. The generic name describes the
/// role, not a supported set.
///
/// Kept free of AppKit so the parsing — including the milliseconds conversion
/// that ADR-0002 warns about — is testable without Spotify running.
public enum PlayerScriptOutput {
    /// ASCII unit separator. Chosen because it cannot appear in a track title
    /// or artist name, unlike any printable delimiter.
    public static let fieldSeparator = "\u{1F}"

    /// The value the bridge emits when the player is stopped and there is no
    /// current track to report.
    public static let stoppedMarker = "stopped"

    public enum ParseError: Error, Equatable {
        case empty
        case unknownPlayerState(String)
        case wrongFieldCount(expected: Int, actual: Int)
        case invalidNumber(field: String, value: String)
    }

    private static let fieldCount = 7

    public static func parse(_ raw: String) throws -> PlaybackState {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw ParseError.empty }

        if trimmed == stoppedMarker { return .stopped }

        let fields = trimmed.components(separatedBy: fieldSeparator)
        guard fields.count == fieldCount else {
            throw ParseError.wrongFieldCount(expected: fieldCount, actual: fields.count)
        }

        let milliseconds = try number(fields[5], field: "duration")
        let position = try number(fields[6], field: "position")

        let track = Track(
            uri: fields[1],
            name: fields[2],
            artist: fields[3],
            album: fields[4],
            duration: milliseconds / 1000
        )

        return switch fields[0] {
        case "playing": .playing(track, position: position)
        case "paused": .paused(track, position: position)
        default: throw ParseError.unknownPlayerState(fields[0])
        }
    }

    private static func number(_ value: String, field: String) throws -> TimeInterval {
        // `Double(_:)` is deliberate: it rejects trailing junk, where
        // `NSString.doubleValue` would quietly return 0.
        guard let parsed = Double(value), parsed.isFinite else {
            throw ParseError.invalidNumber(field: field, value: value)
        }
        return parsed
    }
}
