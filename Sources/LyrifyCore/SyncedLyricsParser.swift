import Foundation

/// Turns the LRC-style timestamped text LRCLIB serves into Lyric Lines.
///
/// Kept free of AppKit like the other parsers, so timing conversion is
/// testable without the network. Malformed timestamps are specific errors,
/// never guesses.
public enum SyncedLyricsParser {
    public enum ParseError: Error, Equatable {
        case malformedTimestamp(String)
        case unterminatedTimestamp(String)
    }

    public static func parse(_ text: String) throws -> [LyricLine] {
        var lines: [LyricLine] = []

        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var starts: [TimeInterval] = []

            // Consume every leading timestamp: the compressed LRC form puts
            // several on one line, each the start of the same repeated text.
            while opensTimestamp(rest) {
                guard let close = rest.firstIndex(of: "]") else {
                    throw ParseError.unterminatedTimestamp(String(rest))
                }
                starts.append(try seconds(of: rest[rest.index(after: rest.startIndex)..<close]))
                rest = rest[rest.index(after: close)...]
            }

            // No timestamp at all: an LRC ID tag ([ar:…], [ti:…]), a blank
            // line, or Plain Lyrics — skippable, never an error.
            guard starts.isEmpty == false else { continue }

            let content = rest.trimmingCharacters(in: .whitespaces)
            for start in starts {
                lines.append(LyricLine(text: content, start: start))
            }
        }

        // Stable by construction: ties keep source order.
        return lines.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    /// A `[` opening on a digit begins a timestamp; anything else in brackets
    /// is metadata.
    private static func opensTimestamp(_ rest: Substring) -> Bool {
        rest.first == "[" && rest.dropFirst().first?.isNumber == true
    }

    /// `mm:ss.xx` (or `.xxx`, or no fraction) into seconds.
    private static func seconds(of stamp: Substring) throws -> TimeInterval {
        let parts = stamp.components(separatedBy: ":")
        guard parts.count == 2,
              let minutes = digits(parts[0])
        else { throw ParseError.malformedTimestamp(String(stamp)) }

        let secondParts = parts[1].components(separatedBy: ".")
        guard secondParts.count <= 2,
              secondParts[0].count == 2,
              let wholeSeconds = digits(secondParts[0]),
              wholeSeconds < 60
        else { throw ParseError.malformedTimestamp(String(stamp)) }

        var fraction = 0.0
        if secondParts.count == 2 {
            let fractionDigits = secondParts[1]
            guard (1...3).contains(fractionDigits.count), let value = digits(fractionDigits) else {
                throw ParseError.malformedTimestamp(String(stamp))
            }
            fraction = Double(value) / pow(10, Double(fractionDigits.count))
        }

        return Double(minutes) * 60 + Double(wholeSeconds) + fraction
    }

    /// `UInt.init` alone would accept `"+5"`; a timestamp component is ASCII
    /// digits or it is malformed.
    private static func digits(_ component: String) -> UInt? {
        guard component.isEmpty == false,
              component.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return UInt(component)
    }
}
